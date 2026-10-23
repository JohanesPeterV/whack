import AppKit
import AVFoundation
import SwiftUI
import WhackCore
import WhackSensor

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var model: AppModel!
    private var diagnosticSensor: MotionSensor?
    private var snapshotWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.whackAssets.url(forResource: "whack", withExtension: "png"), let logo = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = logo
        }
        // Used by the build smoke check to exercise the actual packaged executable.
        if CommandLine.arguments.contains("--bundle-check") {
            runBundleCheck(); return
        }
        if CommandLine.arguments.contains("--sensor-check") {
            runSensorCheck(); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--test-library"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            model = AppModel(directory: directory, initialImportDirectory: directory.deletingLastPathComponent())
        } else {
            model = AppModel()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            snapshot(to: CommandLine.arguments[index + 1]); return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "hand.tap.fill", accessibilityDescription: "Whack")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.toolTip = "Whack! — give your Mac a voice"
        // Activation and native file dialogs can prematurely dismiss a transient
        // accessory-app popover. Dismiss on an actual outside click or Escape.
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(rootView: WhackView(model: model))
        model.restorePanel = { [weak self] in self?.showPopover() }
        model.hidePanel = { [weak self] in self?.popover.performClose(nil) }
        if !CommandLine.arguments.contains("--test-library") {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, event.window == self.popover.contentViewController?.view.window,
               event.window?.attachedSheet == nil {
                self.popover.performClose(nil); return nil
            }
            return event
        }
        showPopover()
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    private func showPopover() {
        guard let button = item.button else { return }
        model.refreshOutputStatus()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if item != nil { showPopover() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) { model?.refreshOutputStatus() }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown(); diagnosticSensor?.stop()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

    private func snapshot(to path: String) {
        model.showSettings = CommandLine.arguments.contains("--settings")
        let controller = NSHostingController(rootView: WhackView(model: model))
        controller.view.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        let size = controller.view.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        snapshotWindow = window
        window.contentViewController = controller
        window.setContentSize(size)
        window.center(); window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let view = controller.view
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try data.write(to: URL(fileURLWithPath: path)); print("Saved \(path)"); exit(0) }
            catch { print(error.localizedDescription); exit(1) }
        }
    }

    private func runSensorCheck() {
        let sensor = MotionSensor()
        diagnosticSensor = sensor
        do {
            try sensor.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let count = sensor.sampleCount
                sensor.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    let stopped = sensor.sampleCount == count
                    print("Packaged Whack sensor check: \(count) valid samples; uid=\(getuid()); stopped=\(stopped)")
                    fflush(stdout)
                    exit(count > 0 && stopped ? 0 : 1)
                }
            }
        } catch {
            print("Packaged Whack sensor check failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func runBundleCheck() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("whack-bundle-check-\(UUID().uuidString)")
        do {
            let library = try SoundLibrary(directory: directory)
            defer { try? FileManager.default.removeItem(at: directory) }
            guard let logo = Bundle.whackAssets.url(forResource: "whack", withExtension: "png"),
                  logo.path.hasPrefix(Bundle.main.bundleURL.path + "/"), NSImage(contentsOf: logo) != nil else {
                throw NSError(domain: "WhackBundleCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Packaged logo is missing"])
            }
            for sound in library.sounds {
                let url = library.url(for: sound)
                guard url.path.hasPrefix(Bundle.main.bundleURL.path + "/") else {
                    throw NSError(domain: "WhackBundleCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sound loaded outside the app bundle"])
                }
                _ = try SoundLibrary.validateAudio(at: url)
                let audio = try AVAudioPlayer(contentsOf: url)
                audio.volume = 0
                guard audio.prepareToPlay(), audio.play() else { throw LibraryError.invalidAudio }
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                guard audio.currentTime > 0 else { throw LibraryError.invalidAudio }
                audio.stop()
            }
            print("Packaged resources verified: original logo and 4 playable sounds; all paths inside app bundle.")
        } catch { print(error.localizedDescription); exit(1) }
        exit(0)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
