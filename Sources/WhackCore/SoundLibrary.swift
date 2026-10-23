import Foundation
import AVFoundation

public struct Sound: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public let fileName: String
    public let duration: Double
    public let bundled: Bool
    public var symbol: String {
        switch id {
        case "boing": return "sparkles"
        case "squeak": return "hare.fill"
        case "sad-trombone": return "music.note"
        case "moan": return "waveform"
        default: return "waveform.circle.fill"
        }
    }
}

public struct Preferences: Codable, Equatable {
    public var selectedID = "boing"
    public var sensitivity = 0.5
    public var cooldown = 0.65
    public var volume = 0.7
    public init() {}
    mutating func normalize() {
        sensitivity = min(1, max(0, sensitivity))
        cooldown = min(2, max(0.2, cooldown))
        volume = min(1, max(0, volume))
    }
}

public enum LibraryError: LocalizedError {
    case invalidAudio, tooLong, tooLarge, invalidName, readOnly, corruptLibrary
    public var errorDescription: String? {
        switch self {
        case .invalidAudio: return "That file couldn’t be read as audio. Choose a playable MP3 or WAV file."
        case .tooLong: return "That clip is over 30 seconds. Choose a shorter reaction."
        case .tooLarge: return "That file is over 25 MB. Choose a smaller MP3 or WAV."
        case .invalidName: return "Give your sound a name between 1 and 60 characters."
        case .readOnly: return "Bundled sounds stay in the library. Add your own sound to customize it."
        case .corruptLibrary: return "The saved library couldn’t be read. Your audio files are still safe. Open the library folder to recover library.json, then reopen Whack."
        }
    }
}

public final class SoundLibrary {
    private struct Manifest: Codable {
        var version = 1
        var sounds: [Sound] = []
        var preferences = Preferences()
    }
    public let directory: URL
    private var manifest = Manifest()
    private let manager = FileManager.default
    public static let bundled: [Sound] = [
        Sound(id: "boing", name: "Boing!", fileName: "boing.wav", duration: 0.72, bundled: true),
        Sound(id: "squeak", name: "Rubber squeak", fileName: "squeak.wav", duration: 0.55, bundled: true),
        Sound(id: "sad-trombone", name: "Tiny trombone", fileName: "sad-trombone.wav", duration: 1.15, bundled: true),
        Sound(id: "moan", name: "Moan", fileName: "moan.wav", duration: 1.1, bundled: true)
    ]
    public var sounds: [Sound] { Self.bundled + manifest.sounds }
    public var preferences: Preferences { manifest.preferences }
    public var selected: Sound { sounds.first { $0.id == preferences.selectedID } ?? Self.bundled[0] }
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whack", isDirectory: true)
    }

    public init(directory: URL = SoundLibrary.defaultDirectory) throws {
        self.directory = directory
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifestURL = directory.appendingPathComponent("library.json")
        if manager.fileExists(atPath: manifestURL.path) {
            do { manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL)) }
            catch { throw LibraryError.corruptLibrary }
            let ids = manifest.sounds.map(\.id)
            let filenames = manifest.sounds.map(\.fileName)
            guard manifest.version == 1, Set(ids).count == ids.count,
                  Set(filenames).count == filenames.count,
                  manifest.sounds.allSatisfy({ sound in
                      !sound.bundled && !Self.bundled.contains(where: { $0.id == sound.id }) &&
                      UUID(uuidString: sound.id) != nil &&
                      sound.fileName == URL(fileURLWithPath: sound.fileName).lastPathComponent &&
                      !sound.fileName.hasPrefix(".") &&
                      ["mp3", "wav"].contains(URL(fileURLWithPath: sound.fileName).pathExtension) &&
                      sound.duration.isFinite && sound.duration > 0 && sound.duration <= 30
                  }) else { throw LibraryError.corruptLibrary }
            manifest.preferences.normalize()
            if !sounds.contains(where: { $0.id == preferences.selectedID }) {
                manifest.preferences.selectedID = Self.bundled[0].id
            }
        }
    }

    public func url(for sound: Sound) -> URL {
        if sound.bundled {
            let packaged = Bundle.main.resourceURL?.appendingPathComponent("Whack_WhackCore.bundle")
            let resources = packaged.flatMap { Bundle(url: $0) } ?? Bundle.module
            return resources.url(forResource: sound.fileName, withExtension: nil, subdirectory: "Sounds")!
        }
        return directory.appendingPathComponent(sound.fileName)
    }

    public func updatePreferences(_ preferences: Preferences) throws {
        var updated = manifest
        updated.preferences = preferences
        updated.preferences.normalize()
        if !sounds.contains(where: { $0.id == updated.preferences.selectedID }) {
            updated.preferences.selectedID = Self.bundled[0].id
        }
        try commit(updated)
    }

    @discardableResult public func add(from source: URL) throws -> Sound {
        let imported = try copyAudio(source, id: UUID().uuidString, name: source.deletingPathExtension().lastPathComponent)
        var updated = manifest
        updated.sounds.append(imported)
        updated.preferences.selectedID = imported.id
        do { try commit(updated) }
        catch { try? manager.removeItem(at: url(for: imported)); throw error }
        return imported
    }

    public func rename(_ sound: Sound, to name: String) throws {
        guard let index = manifest.sounds.firstIndex(where: { $0.id == sound.id }) else { throw LibraryError.readOnly }
        var updated = manifest
        updated.sounds[index].name = try validName(name)
        try commit(updated)
    }

    public func replace(_ sound: Sound, from source: URL) throws {
        guard let index = manifest.sounds.firstIndex(where: { $0.id == sound.id }) else { throw LibraryError.readOnly }
        let imported = try copyAudio(source, id: sound.id, name: sound.name)
        let previous = manifest.sounds[index]
        var updated = manifest
        updated.sounds[index] = imported
        do { try commit(updated) }
        catch { try? manager.removeItem(at: url(for: imported)); throw error }
        // Commit first: a failed save must never lose the previous audio.
        try? manager.removeItem(at: url(for: previous))
    }

    public func delete(_ sound: Sound) throws {
        guard let previous = manifest.sounds.first(where: { $0.id == sound.id }) else { throw LibraryError.readOnly }
        var updated = manifest
        updated.sounds.removeAll { $0.id == sound.id }
        if updated.preferences.selectedID == sound.id { updated.preferences.selectedID = Self.bundled[0].id }
        try commit(updated)
        try? manager.removeItem(at: url(for: previous))
    }

    private func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60 else { throw LibraryError.invalidName }
        return trimmed
    }

    private func copyAudio(_ source: URL, id: String, name: String) throws -> Sound {
        guard ["mp3", "wav"].contains(source.pathExtension.lowercased()) else { throw LibraryError.invalidAudio }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw LibraryError.invalidAudio }
        guard (values.fileSize ?? Int.max) <= 25 * 1024 * 1024 else { throw LibraryError.tooLarge }
        let fileName = UUID().uuidString + "." + source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent(fileName)
        try manager.copyItem(at: source, to: destination)
        do {
            let duration = try Self.validateAudio(at: destination)
            return Sound(id: id, name: try validName(String(name.prefix(60))), fileName: fileName, duration: duration, bundled: false)
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    public static func validateAudio(at url: URL) throws -> Double {
        do {
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            guard duration.isFinite, duration > 0, file.processingFormat.channelCount <= 2 else { throw LibraryError.invalidAudio }
            guard duration <= 30 else { throw LibraryError.tooLong }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { throw LibraryError.invalidAudio }
            var decoded: AVAudioFramePosition = 0
            while file.framePosition < file.length {
                try file.read(into: buffer)
                guard buffer.frameLength > 0 else { throw LibraryError.invalidAudio }
                decoded += AVAudioFramePosition(buffer.frameLength)
            }
            guard decoded > 0 else { throw LibraryError.invalidAudio }
            return duration
        } catch let error as LibraryError { throw error }
        catch { throw LibraryError.invalidAudio }
    }

    private func commit(_ updated: Manifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updated).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
        manifest = updated
    }
}
