import Foundation

private var failures: [String] = []
private var testCount = 0
private func fail(_ message: String, _ file: StaticString, _ line: UInt) {
    failures.append("\(file):\(line): \(message)")
}
func expectTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { fail("Expected true", file, line) } } catch { fail("\(error)", file, line) }
}
func expectFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { fail("Expected false", file, line) } } catch { fail("\(error)", file, line) }
}
func expectEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try lhs(), b = try rhs()
        if a != b { fail("Expected \(a) == \(b)", file, line) }
    } catch { fail("\(error)", file, line) }
}
func expectEqual(_ lhs: @autoclosure () throws -> Double, _ rhs: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(); if abs(a - rhs) > accuracy { fail("Expected \(a) ≈ \(rhs)", file, line) } }
    catch { fail("\(error)", file, line) }
}
func expectGreater<T: Comparable>(_ lhs: @autoclosure () throws -> T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    do { if try lhs() <= rhs { fail("Expected greater than \(rhs)", file, line) } }
    catch { fail("\(error)", file, line) }
}
func expectThrows(_ operation: @autoclosure () throws -> Any, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try operation(); fail("Expected an error", file, line) } catch {}
}
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { fail("Expected nil", file, line) }
}
func require<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "WhackTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Required value was nil"]) }
    return value
}
private func run(_ name: String, _ operation: () throws -> Void) {
    testCount += 1
    let before = failures.count
    do { try operation() } catch { failures.append("\(name): \(error)") }
    print("\(before == failures.count ? "PASS" : "FAIL") \(name)")
}
private func libraryTest(_ name: String, _ operation: (LibraryTests) throws -> Void) {
    run(name) {
        let suite = LibraryTests()
        try suite.setUpWithError()
        defer { try? suite.tearDownWithError() }
        try operation(suite)
    }
}

libraryTest("Import survives source deletion and restart") { try $0.testImportSurvivesOriginalDeletionAndRestart() }
libraryTest("Delete selected falls back and keeps original") { try $0.testDeletingSelectedCustomSoundFallsBackAndKeepsOriginal() }
libraryTest("Replace preserves identity, name and selection") { try $0.testReplacePreservesIdentityNameAndSelectionAcrossRestart() }
libraryTest("Invalid replacement preserves previous audio") { try $0.testInvalidReplacementKeepsPreviousAudioAndManifest() }
libraryTest("Corrupt manifest stays untouched") { try $0.testCorruptManifestIsNotSilentlyOverwritten() }
libraryTest("Reject path traversal") { try $0.testManifestRejectsPathsOutsideLibrary() }
libraryTest("Failed saves preserve data") { try $0.testFailedSaveDoesNotCommitAnImportOrDeleteExistingAudio() }
libraryTest("Reject invalid names and bundled mutations") { try $0.testInvalidNamesAndBundledMutationsAreRejected() }
libraryTest("Bundled WAV files decode") { try $0.testAllBundledSoundsDecodeAndHaveExpectedDuration() }
libraryTest("Clamp settings and recover selection") { try $0.testPreferencesAreClampedAndUnknownSelectionFallsBack() }
libraryTest("Real MP3 import and WAV/MP3 replacement") { try $0.testRealMP3ImportAndReplacement() }
libraryTest("Reject oversized and long files without leftovers") { try $0.testRejectOversizedAndLongAudioWithoutLeavingCopies() }
let detector = DetectorTests()
run("Reject gravity and small typing-like noise") { detector.testGravityAndSmallTypingLikeNoiseDoNotTrigger() }
run("Balanced detects observed gentle taps") { detector.testBalancedDetectsObservedGentleTapBelowOldThreshold() }
run("One trigger per impulse; rearm after quiet") { detector.testImpulseTriggersOnceAndRearmsAfterQuiet() }
run("Suppress speaker vibration during playback") { detector.testPlaybackSuppressionBlocksSpeakerVibration() }
run("Recalibrate after sleep") { detector.testWakeGapRecalibratesWithoutPhantomTap() }
run("Warm up after reset and reject invalid samples") { detector.testResetRequiresWarmupAndRejectsInvalidSamples() }
run("Sensitivity changes the tap threshold") { detector.testHighSensitivityDetectsSmallerImpulse() }
run("Decode signed Q16 sensor reports") { try detector.testReportDecoderHandlesSignedLittleEndianQ16() }
print("\(testCount) checks, \(failures.count) failures")
for failure in failures { print(failure) }
exit(failures.isEmpty ? 0 : 1)
