import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import WhackCore
import WhackSensor

@MainActor final class AppModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var sounds: [Sound] = SoundLibrary.bundled
    @Published private(set) var preferences = Preferences()
    @Published private(set) var isOn = false
    @Published private(set) var status = "Ready when you are."
    @Published private(set) var sensorIssue: String?
    @Published private(set) var outputIssue: String?
    @Published private(set) var systemOutputNeedsAttention = false
    @Published private(set) var playingID: String?
    @Published private(set) var tapCount = 0
    @Published private(set) var level: Double = 0
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var renameSound: Sound?
    @Published var renameText = ""
    @Published var deleteSound: Sound?
    private var library: SoundLibrary?
    private let sensor = MotionSensor()
    private var detector = TapDetector()
    private var player: AVAudioPlayer?
    private var watchdog: Timer?
    private var lastSampleAt: TimeInterval = 0
    private var lastMeterAt: TimeInterval = 0
    private var sleeping = false
    private var filePanel: NSOpenPanel?
    private var importDirectory: URL?
    var restorePanel: (() -> Void)?
    var hidePanel: (() -> Void)?
    private var sensorStartedAt: TimeInterval = 0
    private var wakeObservers: [NSObjectProtocol] = []
    var selectedID: String { preferences.selectedID }
    var selectedName: String { sounds.first { $0.id == selectedID }?.name ?? "Boing!" }
    var canEdit: Bool { library != nil }

    init(directory: URL = SoundLibrary.defaultDirectory, initialImportDirectory: URL? = nil) {
        super.init()
        importDirectory = initialImportDirectory
        do { library = try SoundLibrary(directory: directory); refresh() }
        catch { errorMessage = error.localizedDescription }
        refreshOutputStatus()
        sensor.onSample = { [weak self] sample in self?.receive(sample) }
        sensor.onError = { [weak self] error in
            // Tear down after the HID callback has returned.
            DispatchQueue.main.async { self?.sensorFailed(error) }
        }
        let notifications = NSWorkspace.shared.notificationCenter
        wakeObservers.append(notifications.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleep() }
        })
        wakeObservers.append(notifications.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wake() }
        })
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard canEdit else { return }
            startSensor()
        } else {
            isOn = false; sensor.stop(); watchdog?.invalidate(); watchdog = nil
            detector.reset(); player?.stop(); player = nil; playingID = nil
            level = 0; status = "Taking a breather."
        }
    }

    private func startSensor() {
        detector.reset()
        detector.sensitivity = preferences.sensitivity
        detector.cooldown = preferences.cooldown
        do {
            try sensor.start()
            isOn = true; sensorIssue = nil; status = "Getting a feel for your Mac…"
            lastSampleAt = ProcessInfo.processInfo.systemUptime
            sensorStartedAt = lastSampleAt
            if let player, player.isPlaying {
                detector.suppress(until: lastSampleAt + max(0, player.duration - player.currentTime) + 0.2)
            }
            watchdog?.invalidate()
            watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isOn, !self.sleeping else { return }
                    self.refreshOutputStatus()
                    if ProcessInfo.processInfo.systemUptime - self.lastSampleAt > 2 { self.sensorFailed(SensorError.noSamples) }
                }
            }
        } catch { sensorFailed(error) }
    }

    private func receive(_ sample: MotionSample) {
        guard isOn, !sleeping else { return }
        lastSampleAt = sample.time
        let hit = detector.process(sample)
        if sample.time - lastMeterAt > 0.08 {
            lastMeterAt = sample.time
            level = min(1, detector.amplitude / detector.threshold)
            if status.hasPrefix("Getting"), sample.time - sensorStartedAt >= 0.6 { status = "Listening for a gentle tap." }
        }
        if hit, let sound = sounds.first(where: { $0.id == selectedID }) {
            tapCount += 1
            play(sound)
        }
    }

    private func sensorFailed(_ error: Error) {
        setEnabled(false)
        sensorIssue = error.localizedDescription
        status = "Tap reactions unavailable."
    }

    private func sleep() {
        sleeping = true
        sensor.stop(); watchdog?.invalidate(); watchdog = nil
        player?.stop(); player = nil; playingID = nil; level = 0
        if isOn { status = "Resting with your Mac." }
    }

    private func wake() {
        sleeping = false
        if isOn { startSensor() }
    }

    func shutdown() {
        setEnabled(false)
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        wakeObservers.removeAll()
    }

    func preview(_ sound: Sound) {
        if playingID == sound.id { player?.stop(); player = nil; playingID = nil }
        else { play(sound) }
    }

    private func play(_ sound: Sound) {
        guard let library else { return }
        refreshOutputStatus()
        do {
            player?.stop(); playingID = nil
            let audio = try AVAudioPlayer(contentsOf: library.url(for: sound))
            audio.volume = Float(preferences.volume)
            audio.delegate = self
            guard audio.prepareToPlay() else { throw LibraryError.invalidAudio }
            detector.suppress(until: ProcessInfo.processInfo.systemUptime + audio.duration + 0.2)
            guard audio.play() else { throw LibraryError.invalidAudio }
            player = audio; playingID = sound.id
        } catch {
            player = nil; playingID = nil
            errorMessage = "Couldn’t play \(sound.name). \(error.localizedDescription)" + (sound.bundled ? "" : " Use Replace… to choose the audio again.")
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.playingID = nil; self.player = nil
            if !flag { self.errorMessage = "Playback was interrupted. Try previewing the sound again." }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.playingID = nil; self.player = nil
            self.errorMessage = "That sound couldn’t be decoded. Replace it with a playable MP3 or WAV."
        }
    }

    func select(_ sound: Sound) { update { $0.selectedID = sound.id } }
    func setSensitivity(_ value: Double) { update { $0.sensitivity = value } }
    func setCooldown(_ value: Double) { update { $0.cooldown = value } }
    func setVolume(_ value: Double) {
        update { $0.volume = value }
        player?.volume = Float(preferences.volume)
        refreshOutputStatus()
    }

    func refreshOutputStatus() {
        let systemIssue = AudioOutput.issue()
        let issue = systemIssue ?? (preferences.volume == 0 ? "Whack’s volume is at zero. Turn it up in Settings to hear reactions." : nil)
        if systemOutputNeedsAttention != (systemIssue != nil) { systemOutputNeedsAttention = systemIssue != nil }
        if outputIssue != issue { outputIssue = issue }
    }

    func openSoundSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
    }

    private func update(_ mutate: (inout Preferences) -> Void) {
        guard let library else { return }
        var next = preferences
        mutate(&next)
        do { try library.updatePreferences(next); refresh() }
        catch { errorMessage = "Couldn’t save your settings. \(error.localizedDescription)" }
    }

    func chooseFiles(replacing sound: Sound? = nil) {
        guard filePanel == nil else { filePanel?.makeKeyAndOrderFront(nil); return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        filePanel = panel
        panel.title = sound == nil ? "Add a reaction" : "Replace \(sound!.name)"
        panel.prompt = sound == nil ? "Add sound" : "Replace"
        panel.allowedContentTypes = [.mp3, .wav]
        panel.allowsMultipleSelection = sound == nil
        panel.canChooseDirectories = false
        panel.directoryURL = importDirectory
        // Let the originating sound menu finish closing before presenting a new
        // window; closing its parent popover during menu tracking can cancel it.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hidePanel?()
            NSApp.activate(ignoringOtherApps: true)
            panel.begin { [weak self] response in
                guard let self else { return }
                self.filePanel = nil
                if response == .OK {
                    self.importDirectory = panel.url?.deletingLastPathComponent()
                    if let sound, let url = panel.url {
                        if self.playingID == sound.id { self.player?.stop(); self.player = nil; self.playingID = nil }
                        self.change { library in try library.replace(sound, from: url) }
                    } else { self.importFiles(panel.urls) }
                }
                self.restorePanel?()
            }
        }
    }

    func importFiles(_ urls: [URL]) {
        guard let library else { return }
        var failures: [String] = []
        for url in urls {
            do { try library.add(from: url) }
            catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        refresh()
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n\n") }
    }

    func beginRename(_ sound: Sound) { renameText = sound.name; renameSound = sound }
    func saveRename() {
        guard let sound = renameSound else { return }
        change { try $0.rename(sound, to: renameText) }
        renameSound = nil
    }
    func confirmDelete() {
        guard let sound = deleteSound else { return }
        if playingID == sound.id { player?.stop(); player = nil; playingID = nil }
        change { try $0.delete(sound) }
        deleteSound = nil
    }
    func revealLibrary() { NSWorkspace.shared.open(library?.directory ?? SoundLibrary.defaultDirectory) }

    private func change(_ operation: (SoundLibrary) throws -> Void) {
        guard let library else { return }
        do { try operation(library); refresh() }
        catch { errorMessage = error.localizedDescription }
    }
    private func refresh() {
        guard let library else { return }
        sounds = library.sounds; preferences = library.preferences
        detector.sensitivity = preferences.sensitivity; detector.cooldown = preferences.cooldown
    }
}
