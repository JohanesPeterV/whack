import CoreGraphics
import Foundation

/// Reads elapsed time only, never keys, characters, or event contents. This uses
/// the session's event counters without installing an event tap or key monitor.
public enum KeyboardActivity {
    public static func idleTime() -> TimeInterval {
        min(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyUp),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .flagsChanged))
    }
}

/// Confirms a motion candidate only after keyboard activity has been ruled out.
/// A key's vibration can reach the accelerometer before its keyboard event.
public struct TapReactionDetector {
    public static let typingQuietInterval: TimeInterval = 0.35
    public static let confirmationDelay: TimeInterval = 0.12
    private var motion = TapDetector()
    private var pendingAt: TimeInterval?
    public var cooldown: TimeInterval = 0.65
    public var sensitivity: Double {
        get { motion.sensitivity }
        set { motion.sensitivity = newValue; pendingAt = nil }
    }
    public var amplitude: Double { motion.amplitude }
    public var threshold: Double { motion.threshold }

    public init() {
        // Rejected keyboard bumps must not consume the full reaction cooldown.
        // The configured cooldown starts when a reaction is actually confirmed.
        motion.cooldown = 0.2
    }

    public mutating func reset() {
        pendingAt = nil
        motion.reset()
    }

    public mutating func suppress(until time: TimeInterval) {
        pendingAt = nil
        motion.suppress(until: time)
    }

    public mutating func process(_ sample: MotionSample,
                                 keyboardIdleTime: () -> TimeInterval = KeyboardActivity.idleTime) -> Bool {
        guard sample.time.isFinite, sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else {
            pendingAt = nil
            return false
        }
        let candidate = motion.process(sample)
        guard candidate || pendingAt != nil else { return false }
        // Query the OS only for a candidate or its short confirmation window.
        // NaN and negative values fail closed; infinity represents no activity.
        guard keyboardIdleTime() >= Self.typingQuietInterval else {
            pendingAt = nil
            return false
        }
        guard let pendingAt else {
            self.pendingAt = sample.time
            return false
        }
        let age = sample.time - pendingAt
        guard age >= 0, age <= 0.25 else {
            self.pendingAt = nil // Drop stale candidates after a stall or sleep.
            return false
        }
        guard age >= Self.confirmationDelay else { return false }
        self.pendingAt = nil
        motion.suppress(until: sample.time + max(0.2, cooldown))
        return true
    }
}
