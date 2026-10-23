import Foundation
import WhackCore

final class TypingGuardTests {
    private func sample(_ milliseconds: Int, bump: Bool = false) -> MotionSample {
        MotionSample(time: Double(milliseconds) / 1000, x: 0, y: 0, z: bump ? 1.16 : 1)
    }

    private func replay(_ detector: inout TapReactionDetector, from start: Int = 0, through end: Int,
                        bumps: Set<Int>, keyboardEvents: [Int] = []) -> [Int] {
        var reactions: [Int] = []
        for i in start...end {
            let idle = keyboardEvents.filter { $0 <= i }.max().map { Double(i - $0) / 1000 } ?? .infinity
            if detector.process(sample(i, bump: bumps.contains(i)), keyboardIdleTime: { idle }) {
                reactions.append(i)
            }
        }
        return reactions
    }

    func testGentleTapStillReactsWithBoundedDelay() {
        var detector = TapReactionDetector()
        let reactions = replay(&detector, through: 1400, bumps: [801])
        expectEqual(reactions.count, 1)
        expectTrue(reactions.first.map { (921...925).contains($0) } ?? false)
    }

    func testRecentTypingIsRejectedWithoutConsumingReactionCooldown() {
        var detector = TapReactionDetector()
        detector.cooldown = 2
        let reactions = replay(&detector, through: 1800, bumps: [801, 1401], keyboardEvents: [790, 840])
        expectEqual(reactions.count, 1)
        expectTrue(reactions.first.map { (1521...1525).contains($0) } ?? false)
    }

    func testFirstKeystrokeArrivingAfterItsVibrationIsRejected() {
        var detector = TapReactionDetector()
        expectTrue(replay(&detector, through: 1400, bumps: [801], keyboardEvents: [835, 880]).isEmpty)
    }

    func testContinuousTypingStaysQuietAndTapsResumeAfterPause() {
        var detector = TapReactionDetector()
        let presses = Array(stride(from: 820, through: 3820, by: 140))
        let keyboardEvents = presses + presses.map { $0 + 60 }
        let bumps = Set(presses.map { $0 - 20 } + [4321])
        let reactions = replay(&detector, through: 4700, bumps: bumps, keyboardEvents: keyboardEvents)
        expectEqual(reactions.count, 1)
        expectTrue(reactions.first.map { (4441...4445).contains($0) } ?? false)
    }

    func testPendingReactionsCancelOnResetPlaybackAndSensitivityChange() {
        for action in 0...2 {
            var detector = TapReactionDetector()
            expectTrue(replay(&detector, through: 850, bumps: [801]).isEmpty)
            switch action {
            case 0: detector.reset()
            case 1: detector.suppress(until: 2)
            default: detector.sensitivity = 1
            }
            expectTrue(replay(&detector, from: 851, through: 1500, bumps: []).isEmpty)
        }
    }

    func testStaleAndInvalidInputCannotConfirmPendingReaction() {
        var detector = TapReactionDetector()
        expectTrue(replay(&detector, through: 850, bumps: [801]).isEmpty)
        expectFalse(detector.process(sample(10_000), keyboardIdleTime: { .infinity }))
        expectTrue(replay(&detector, from: 10_001, through: 10_800, bumps: []).isEmpty)
        for idle in [Double.nan, -1] {
            detector.reset()
            expectTrue(replay(&detector, through: 800, bumps: []).isEmpty)
            expectFalse(detector.process(sample(801, bump: true), keyboardIdleTime: { idle }))
            expectTrue(replay(&detector, from: 802, through: 1400, bumps: []).isEmpty)
        }
        detector.reset()
        expectTrue(replay(&detector, through: 850, bumps: [801]).isEmpty)
        expectFalse(detector.process(MotionSample(time: .nan, x: 0, y: 0, z: 1)))
        expectTrue(replay(&detector, from: 851, through: 1400, bumps: []).isEmpty)
    }

    func testConfirmedReactionsRespectConfiguredCooldown() {
        var detector = TapReactionDetector()
        detector.cooldown = 2
        let reactions = replay(&detector, through: 3800, bumps: [801, 1501, 2101, 3201])
        expectEqual(reactions.count, 2)
        expectTrue(reactions.last.map { (3321...3325).contains($0) } ?? false)
    }
}
