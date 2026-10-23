import Foundation
import WhackCore

final class LibraryTests {
    private var directory: URL!
    private var library: SoundLibrary!

    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("whack-tests-\(UUID().uuidString)")
        library = try SoundLibrary(directory: directory.appendingPathComponent("Library"))
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func original(_ name: String = "My sound.wav", bundledIndex: Int = 0) throws -> URL {
        let source = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: library.url(for: SoundLibrary.bundled[bundledIndex]), to: source)
        return source
    }

    func testImportSurvivesOriginalDeletionAndRestart() throws {
        let source = try original()
        let sound = try library.add(from: source)
        try library.rename(sound, to: "My reaction")
        var preferences = library.preferences
        preferences.sensitivity = 0.8; preferences.cooldown = 0.9
        try library.updatePreferences(preferences)
        try FileManager.default.removeItem(at: source)
        let restarted = try SoundLibrary(directory: library.directory)
        expectEqual(restarted.selected.id, sound.id)
        expectEqual(restarted.selected.name, "My reaction")
        expectEqual(restarted.preferences.sensitivity, 0.8)
        expectEqual(restarted.preferences.cooldown, 0.9)
        expectGreater(try SoundLibrary.validateAudio(at: restarted.url(for: restarted.selected)), 0)
    }

    func testDeletingSelectedCustomSoundFallsBackAndKeepsOriginal() throws {
        let source = try original()
        let sound = try library.add(from: source)
        try library.delete(sound)
        expectEqual(library.selected.id, "boing")
        expectTrue(FileManager.default.fileExists(atPath: source.path))
        expectFalse(FileManager.default.fileExists(atPath: library.url(for: sound).path))
        expectEqual(try SoundLibrary(directory: library.directory).selected.id, "boing")
    }

    func testReplacePreservesIdentityNameAndSelectionAcrossRestart() throws {
        let sound = try library.add(from: original())
        let oldURL = library.url(for: sound)
        let replacement = try original("Other.wav", bundledIndex: 1)
        try library.replace(sound, from: replacement)
        let restarted = try SoundLibrary(directory: library.directory)
        expectEqual(restarted.selected.id, sound.id)
        expectEqual(restarted.selected.name, sound.name)
        expectEqual(restarted.selected.duration, 0.55, accuracy: 0.002)
        expectFalse(FileManager.default.fileExists(atPath: oldURL.path))
        expectTrue(FileManager.default.fileExists(atPath: replacement.path))
    }

    func testInvalidReplacementKeepsPreviousAudioAndManifest() throws {
        let sound = try library.add(from: original())
        let corrupt = directory.appendingPathComponent("broken.mp3")
        try Data("not audio".utf8).write(to: corrupt)
        let before = try Data(contentsOf: library.directory.appendingPathComponent("library.json"))
        expectThrows(try library.replace(sound, from: corrupt))
        expectEqual(before, try Data(contentsOf: library.directory.appendingPathComponent("library.json")))
        expectGreater(try SoundLibrary.validateAudio(at: library.url(for: sound)), 0)
        expectEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path).count, 2)
    }

    func testCorruptManifestIsNotSilentlyOverwritten() throws {
        let manifest = library.directory.appendingPathComponent("library.json")
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: manifest)
        expectThrows(try SoundLibrary(directory: library.directory))
        expectEqual(try Data(contentsOf: manifest), corrupt)
    }

    func testManifestRejectsPathsOutsideLibrary() throws {
        _ = try library.add(from: original())
        let manifestURL = library.directory.appendingPathComponent("library.json")
        var json = try require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        var sounds = try require(json["sounds"] as? [[String: Any]])
        sounds[0]["fileName"] = "../outside.wav"; json["sounds"] = sounds
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
        expectThrows(try SoundLibrary(directory: library.directory))
    }

    func testFailedSaveDoesNotCommitAnImportOrDeleteExistingAudio() throws {
        let sound = try library.add(from: original())
        let manifestURL = library.directory.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: manifestURL)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false)
        expectThrows(try library.delete(sound))
        expectEqual(library.selected.id, sound.id)
        expectTrue(FileManager.default.fileExists(atPath: library.url(for: sound).path))
        expectThrows(try library.add(from: original("Second.wav")))
        expectEqual(library.sounds.count, 5)
        expectEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path).count, 2)
    }

    func testInvalidNamesAndBundledMutationsAreRejected() throws {
        let sound = try library.add(from: original())
        expectThrows(try library.rename(sound, to: "  "))
        expectThrows(try library.rename(sound, to: String(repeating: "a", count: 61)))
        expectThrows(try library.delete(SoundLibrary.bundled[0]))
        expectThrows(try library.replace(SoundLibrary.bundled[0], from: original("Other.wav")))
    }

    func testAllBundledSoundsDecodeAndHaveExpectedDuration() throws {
        for sound in SoundLibrary.bundled {
            expectEqual(try SoundLibrary.validateAudio(at: library.url(for: sound)), sound.duration, accuracy: 0.002)
        }
    }

    func testPreferencesAreClampedAndUnknownSelectionFallsBack() throws {
        var preferences = library.preferences
        preferences.sensitivity = 9; preferences.cooldown = -1; preferences.volume = 2
        preferences.selectedID = "missing"
        try library.updatePreferences(preferences)
        expectEqual(library.preferences.sensitivity, 1)
        expectEqual(library.preferences.cooldown, 0.2)
        expectEqual(library.preferences.volume, 1)
        expectEqual(library.selected.id, "boing")
    }

    func testRealMP3ImportAndReplacement() throws {
        let mp3 = try require(Bundle.module.url(forResource: "boing", withExtension: "mp3", subdirectory: "Fixtures"))
        let sound = try library.add(from: mp3)
        expectEqual(library.url(for: sound).pathExtension, "mp3")
        expectGreater(try SoundLibrary.validateAudio(at: library.url(for: sound)), 0.7)
        let wav = try original()
        try library.replace(sound, from: wav)
        expectEqual(library.url(for: library.selected).pathExtension, "wav")
        try library.replace(library.selected, from: mp3)
        expectEqual(library.url(for: library.selected).pathExtension, "mp3")
        let restarted = try SoundLibrary(directory: library.directory)
        expectGreater(try SoundLibrary.validateAudio(at: restarted.url(for: restarted.selected)), 0.7)
    }

    func testRejectOversizedAndLongAudioWithoutLeavingCopies() throws {
        let oversized = directory.appendingPathComponent("large.wav")
        try Data(repeating: 0, count: 25 * 1024 * 1024 + 1).write(to: oversized)
        do { _ = try library.add(from: oversized); expectTrue(false) }
        catch LibraryError.tooLarge {} // Must fail before attempting to decode.
        let originalData = try Data(contentsOf: library.url(for: SoundLibrary.bundled[0]))
        var longData = originalData.prefix(44)
        let pcm = originalData.dropFirst(44)
        for _ in 0..<44 { longData.append(pcm) }
        func littleEndian(_ value: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        longData.replaceSubrange(4..<8, with: littleEndian(longData.count - 8))
        longData.replaceSubrange(40..<44, with: littleEndian(longData.count - 44))
        let longURL = directory.appendingPathComponent("long.wav")
        try longData.write(to: longURL)
        do { _ = try library.add(from: longURL); expectTrue(false) }
        catch LibraryError.tooLong {}
        expectEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path).count, 0)
    }
}

final class DetectorTests {
    private func sample(_ time: Double, _ z: Double = 1) -> MotionSample { MotionSample(time: time, x: 0, y: 0, z: z) }
    private func settle(_ detector: inout TapDetector, from: Int = 0, through: Int = 800) {
        for i in from...through { expectFalse(detector.process(sample(Double(i) / 1000))) }
    }

    func testGravityAndSmallTypingLikeNoiseDoNotTrigger() {
        var detector = TapDetector()
        for i in 0...4000 {
            expectFalse(detector.process(sample(Double(i) / 1000, 1 + sin(Double(i)) * 0.012)))
        }
    }

    func testBalancedDetectsObservedGentleTapBelowOldThreshold() {
        var detector = TapDetector()
        settle(&detector)
        expectEqual(detector.threshold, 0.05, accuracy: 0.0001)
        expectTrue(detector.process(sample(0.801, 1.16)))
    }

    func testImpulseTriggersOnceAndRearmsAfterQuiet() {
        var detector = TapDetector()
        settle(&detector)
        expectTrue(detector.process(sample(0.801, 1.45)))
        for i in 802...1400 {
            expectFalse(detector.process(sample(Double(i) / 1000, 1 + 0.3 * exp(-Double(i - 802) / 50) * sin(Double(i)))))
        }
        settle(&detector, from: 1401, through: 1800)
        expectTrue(detector.process(sample(1.801, 0.6)))
    }

    func testPlaybackSuppressionBlocksSpeakerVibration() {
        var detector = TapDetector()
        settle(&detector)
        detector.suppress(until: 2)
        for i in 801...1999 { expectFalse(detector.process(sample(Double(i) / 1000, i % 2 == 0 ? 1.5 : 0.5))) }
        settle(&detector, from: 2000, through: 2500)
        expectTrue(detector.process(sample(2.501, 1.45)))
    }

    func testWakeGapRecalibratesWithoutPhantomTap() {
        var detector = TapDetector()
        settle(&detector)
        expectFalse(detector.process(sample(10, 0.5)))
        expectFalse(detector.process(sample(10.001, 1.2)))
    }

    func testResetRequiresWarmupAndRejectsInvalidSamples() {
        var detector = TapDetector()
        settle(&detector)
        detector.reset()
        expectFalse(detector.process(sample(1, 1.9)))
        expectFalse(detector.process(sample(1.001, 0.7)))
        expectFalse(detector.process(sample(.nan)))
        expectFalse(detector.process(sample(1.002, .infinity)))
    }

    func testHighSensitivityDetectsSmallerImpulse() {
        var light = TapDetector(); light.sensitivity = 1
        var firm = TapDetector(); firm.sensitivity = 0
        settle(&light); settle(&firm)
        expectTrue(light.process(sample(0.801, 1.08)))
        expectFalse(firm.process(sample(0.801, 1.08)))
    }

    func testReportDecoderHandlesSignedLittleEndianQ16() throws {
        var bytes = [UInt8](repeating: 0, count: 22)
        for (offset, value) in [(6, Int32(-65536)), (10, Int32(32768)), (14, Int32(65536))] {
            let bits = UInt32(bitPattern: value)
            for i in 0..<4 { bytes[offset + i] = UInt8(truncatingIfNeeded: bits >> (i * 8)) }
        }
        let sample = try require(MotionSample.decode(bytes, time: 10))
        expectEqual(sample.x, -1); expectEqual(sample.y, 0.5); expectEqual(sample.z, 1)
        expectNil(MotionSample.decode(Array(bytes.prefix(18)), time: 10))
        expectNil(MotionSample.decode(bytes + [0], time: 10))
    }
}
