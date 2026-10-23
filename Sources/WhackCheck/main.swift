import Foundation
import AVFoundation
import WhackCore
import WhackSensor

// A bounded local hardware check. Does not install a helper or request elevation.
let sensor = MotionSensor()
var detector = TapDetector()
var taps = 0
var peak = 0.0
let audio = CommandLine.arguments.contains("--audio")
let temporaryLibrary = FileManager.default.temporaryDirectory.appendingPathComponent("whack-check-\(UUID().uuidString)")
let player = try AVAudioPlayer(contentsOf: SoundLibrary(directory: temporaryLibrary).url(for: SoundLibrary.bundled[0]))
try? FileManager.default.removeItem(at: temporaryLibrary)
player.volume = 0.35
sensor.onSample = { sample in
    let hit = detector.process(sample)
    peak = max(peak, detector.amplitude)
    if hit {
        taps += 1
        print("tap \(taps): \(String(format: "%.3f", detector.amplitude)) g")
        if audio {
            detector.suppress(until: sample.time + player.duration + 0.2)
            player.currentTime = 0
            player.play()
        }
    }
}
let duration: Double = CommandLine.arguments.contains("--interactive") ? 20 : 3
do {
    try sensor.start()
    print("Reading motion for \(Int(duration)) seconds (uid \(getuid()))." + (audio ? " Audio reactions enabled." : ""))
    RunLoop.main.run(until: Date().addingTimeInterval(duration))
    sensor.stop()
    print("\(sensor.sampleCount) valid reports, \(taps) taps, peak \(String(format: "%.4f", peak)) g")
    exit(sensor.sampleCount > 0 ? 0 : 1)
} catch {
    print(error.localizedDescription)
    exit(1)
}
