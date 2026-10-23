import Foundation

public struct MotionSample {
    public let time: TimeInterval
    public let x: Double
    public let y: Double
    public let z: Double

    public init(time: TimeInterval, x: Double, y: Double, z: Double) {
        self.time = time; self.x = x; self.y = y; self.z = z
    }

    /// Apple SPU's 22-byte accelerometer report: little-endian Q16 g at offset 6.
    public static func decode(_ bytes: [UInt8], time: TimeInterval) -> MotionSample? {
        guard bytes.count == 22 else { return nil }
        func axis(_ offset: Int) -> Double {
            let bits = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            return Double(Int32(bitPattern: bits)) / 65_536
        }
        let sample = MotionSample(time: time, x: axis(6), y: axis(10), z: axis(14))
        guard abs(sample.x) < 32, abs(sample.y) < 32, abs(sample.z) < 32 else { return nil }
        return sample
    }
}

/// Time-based gravity removal, a rising-edge trigger, and quiet re-arming.
/// Defaults are a starting point; physical typing/tap separation needs hardware validation.
public struct TapDetector {
    public var sensitivity: Double = 0.5
    public var cooldown: TimeInterval = 0.65
    public private(set) var amplitude: Double = 0
    // Exponential scaling gives useful precision for gentle taps. Balanced is
    // 0.05 g; the previous linear midpoint (0.17 g) missed observed 0.16 g taps.
    public var threshold: Double { 0.25 * pow(0.01 / 0.25, min(1, max(0, sensitivity))) }
    private var baseline: MotionSample?
    private var startedAt: TimeInterval = 0
    private var blockedUntil: TimeInterval = 0
    private var quietSince: TimeInterval?
    private var armed = false

    public init() {}

    public mutating func reset() {
        baseline = nil; amplitude = 0; armed = false; quietSince = nil
        blockedUntil = 0
    }

    /// Called before previews and reactions, covering the entire clip plus speaker decay.
    public mutating func suppress(until time: TimeInterval) {
        blockedUntil = max(blockedUntil, time)
        armed = false; quietSince = nil
    }

    public mutating func process(_ sample: MotionSample) -> Bool {
        guard sample.time.isFinite, sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else { return false }
        guard let previous = baseline else {
            baseline = sample; startedAt = sample.time
            return false
        }
        let delta = sample.time - previous.time
        guard delta > 0 else { return false }
        // Recalibrate after sleep or a sensor interruption.
        if delta > 0.25 {
            baseline = sample; startedAt = sample.time; armed = false; quietSince = nil
            return false
        }
        let alpha = 1 - exp(-delta / 0.08)
        let dx = sample.x - previous.x, dy = sample.y - previous.y, dz = sample.z - previous.z
        amplitude = sqrt(dx * dx + dy * dy + dz * dz)
        baseline = MotionSample(time: sample.time, x: previous.x + alpha * dx,
                                y: previous.y + alpha * dy, z: previous.z + alpha * dz)
        guard sample.time - startedAt >= 0.5, sample.time >= blockedUntil else {
            quietSince = nil; armed = false
            return false
        }
        if amplitude < threshold * 0.4 {
            if quietSince == nil { quietSince = sample.time }
            if sample.time - (quietSince ?? sample.time) >= 0.08 { armed = true }
        } else {
            quietSince = nil
        }
        guard armed, amplitude >= threshold else { return false }
        armed = false
        blockedUntil = sample.time + max(0.2, cooldown)
        return true
    }
}
