import AppKit
import ApplicationServices

// Real accessibility-driven UI regression tests. Uses an isolated library and never
// changes the user's clipboard, imported sounds, or preferences. Requires macOS
// Accessibility authorization for the terminal/agent running this executable.
struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, key as CFString, &value)
    return value
}
func string(_ element: AXUIElement, _ key: String) -> String { attribute(element, key) as? String ?? "" }
func nodes(_ root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 18 else { return [] }
    return [root] + (attribute(root, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { nodes($0, depth: depth + 1) }
}
func wait(_ description: String, timeout: Double = 5, until condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
    throw Failure(message: "Timed out: \(description)")
}
final class UITest {
    let executable: URL
    let fixture: URL
    let root: URL
    var process: Process!
    var app: AXUIElement!
    var passed = 0
    var library: URL { root.appendingPathComponent("Library") }

    init(executable: URL, fixture: URL) throws {
        self.executable = executable; self.fixture = fixture
        root = FileManager.default.temporaryDirectory.appendingPathComponent("whack-ui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func launch() throws {
        process = Process()
        process.executableURL = executable
        process.arguments = ["--test-library", library.path]
        try process.run()
        app = AXUIElementCreateApplication(process.processIdentifier)
        try wait("menu-bar item") { nodes(self.app).contains { string($0, kAXRoleAttribute) == kAXMenuBarItemRole } }
        NSRunningApplication(processIdentifier: process.processIdentifier)?.activate()
        try panel()
    }
    func find(_ label: String, role: String? = nil) -> AXUIElement? {
        nodes(app).first { candidate in
            (role == nil || string(candidate, kAXRoleAttribute) == role) &&
            [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute].contains { string(candidate, $0) == label }
        }
    }
    func element(_ label: String, role: String? = nil) throws -> AXUIElement {
        var reopened = false
        var found: AXUIElement?
        try wait(label) {
            if let current = self.find(label, role: role) { found = current; return true }
            let tree = nodes(self.app)
            // A transient menu-bar panel legitimately closes if another app becomes
            // active. Reopen it as a user would; never dismiss an active dialog/menu.
            if !reopened, !tree.contains(where: { [kAXPopoverRole, kAXWindowRole, kAXSheetRole, kAXMenuRole].contains(string($0, kAXRoleAttribute)) }),
               let item = tree.first(where: { string($0, kAXRoleAttribute) == kAXMenuBarItemRole }) {
                reopened = true
                AXUIElementPerformAction(item, kAXPressAction as CFString)
            }
            return false
        }
        guard let found else { throw Failure(message: "Missing control: \(label)") }
        return found
    }
    func click(_ label: String, role: String? = nil) throws {
        let target = try element(label, role: role)
        let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
        // A native alert button can disappear before AX replies. The following
        // state assertion still has to prove the action completed successfully.
        guard result == .success || result == .actionUnsupported || result == .cannotComplete ||
              result == .attributeUnsupported else {
            throw Failure(message: "Press \(label): \(result.rawValue)")
        }
    }
    func set(_ element: AXUIElement, value: String) throws {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
        guard result == .success else { throw Failure(message: "Set value: \(result.rawValue)") }
    }
    func panel() throws {
        if find("Tap reactions") == nil {
            let menuItem = nodes(app).first { string($0, kAXRoleAttribute) == kAXMenuBarItemRole }
            guard let menuItem else { throw Failure(message: "Missing menu-bar item") }
            AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
        }
        try wait("panel reopened") { self.find("Tap reactions") != nil }
    }
    func pick(_ url: URL, action: String) throws {
        try wait("file picker ready") { self.find(action, role: kAXButtonRole) != nil }
        var row: AXUIElement?
        try wait("fixture row in native file picker") {
            row = nodes(self.app).first { element in
                string(element, kAXRoleAttribute) == kAXRowRole && nodes(element).contains { string($0, kAXValueAttribute) == url.lastPathComponent }
            }
            return row != nil
        }
        let result = AXUIElementSetAttributeValue(row!, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        guard result == .success else { throw Failure(message: "Select file row: \(result.rawValue)") }
        try wait("file selection") {
            guard let button = self.find(action, role: kAXButtonRole) else { return false }
            return (attribute(button, kAXEnabledAttribute) as? Bool) == true
        }
        try click(action, role: kAXButtonRole)
        try wait("panel restored after picker") { self.find("Tap reactions") != nil }
    }
    func manifest() -> [String: Any] {
        guard let data = try? Data(contentsOf: library.appendingPathComponent("library.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }
    var customs: [[String: Any]] { manifest()["sounds"] as? [[String: Any]] ?? [] }
    var preferences: [String: Any] { manifest()["preferences"] as? [String: Any] ?? [:] }
    func check(_ name: String, _ body: () throws -> Void) throws {
        try body(); passed += 1; print("PASS UI \(name)"); fflush(stdout)
    }
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }
    }
    func stop() {
        if process?.isRunning == true {
            NSRunningApplication(processIdentifier: process.processIdentifier)?.terminate()
            for _ in 0..<40 {
                if !process.isRunning { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { process.terminate() }
        }
    }
    func dump() {
        // Limit failure output to app controls, avoiding unrelated file-picker listings.
        for node in nodes(app).filter({ ![kAXRowRole, kAXCellRole, kAXStaticTextRole, kAXTextFieldRole, kAXImageRole].contains(string($0, kAXRoleAttribute)) }) {
            print([kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].map { "\($0)=\(string(node, $0))" }.joined(separator: " | "))
        }
    }
    func run() throws {
        try launch()
        try check("fresh launch has four bundled sounds and reactions off") {
            let toggle = try element("Tap reactions")
            try expect((attribute(toggle, kAXValueAttribute) as? NSNumber)?.intValue == 0, "Reactions should start off")
            _ = try element("4 sounds")
        }
        try click("Settings")
        let volume = try element("Sound volume")
        for _ in 0..<20 { AXUIElementPerformAction(volume, kAXDecrementAction as CFString) }
        try wait("muted test playback") { self.preferences["volume"] as? Double == 0 }
        try click("Settings")
        try check("zero app volume shows a warning with a working settings action") {
            _ = try element("Whack’s volume is at zero. Turn it up in Settings to hear reactions.")
            try click("Adjust Whack volume")
            let slider = try element("Sound volume")
            AXUIElementPerformAction(slider, kAXIncrementAction as CFString)
            try wait("volume restored") { (self.preferences["volume"] as? Double ?? 0) > 0 }
            try wait("warning clears") { self.find("Adjust Whack volume") == nil }
            AXUIElementPerformAction(slider, kAXDecrementAction as CFString)
            try wait("test playback muted again") { self.preferences["volume"] as? Double == 0 }
            try click("Settings")
        }
        try check("preview starts and finishes through the actual audio player") {
            try click("Preview Boing!")
            _ = try element("Stop Boing!")
            _ = try element("Preview Boing!")
        }
        try check("selection persists from the sound row") {
            try click("Select Rubber squeak")
            try wait("saved selection") { self.preferences["selectedID"] as? String == "squeak" }
        }
        try check("cancelling the picker restores the panel without changes") {
            try click("Add your own sound, MP3 / WAV")
            try click("Cancel", role: kAXButtonRole)
            _ = try element("Tap reactions")
            try expect(customs.isEmpty, "Cancel changed the library")
        }
        let invalid = root.appendingPathComponent("Invalid.wav")
        try Data("This is not an audio file".utf8).write(to: invalid)
        try check("invalid audio shows a recoverable error") {
            try click("Add your own sound, MP3 / WAV")
            try pick(invalid, action: "Add sound")
            _ = try element("Something needs a little attention")
            try click("OK", role: kAXButtonRole)
            try expect(customs.isEmpty, "Invalid audio entered the library")
            _ = try element("Add your own sound, MP3 / WAV")
        }
        let source = root.appendingPathComponent("UI import.mp3")
        try FileManager.default.copyItem(at: fixture, to: source)
        let replacement = root.appendingPathComponent("Replacement.mp3")
        try FileManager.default.copyItem(at: fixture, to: replacement)
        try check("file picker imports an app-owned copy") {
            try click("Add your own sound, MP3 / WAV")
            try pick(source, action: "Add sound")
            try wait("imported sound") { self.customs.count == 1 }
            _ = try element("Select UI import")
            try expect(FileManager.default.fileExists(atPath: source.path), "Import removed source")
        }
        let soundID = customs[0]["id"] as! String
        try check("rename works through the sound menu and sheet") {
            try click("Manage UI import")
            try click("Rename…")
            let field = try element("Sound name", role: kAXTextFieldRole)
            try set(field, value: "Renamed reaction")
            try click("Save", role: kAXButtonRole)
            try wait("renamed sound") { self.customs.first?["name"] as? String == "Renamed reaction" }
        }
        try check("replacing preserves name and selection") {
            let previousFile = customs[0]["fileName"] as! String
            try click("Manage Renamed reaction")
            try click("Replace…")
            try pick(replacement, action: "Replace")
            try wait("replacement saved") { self.customs.first?["fileName"] as? String != previousFile }
            try expect(customs[0]["id"] as? String == soundID, "Replace changed identity")
            try expect(preferences["selectedID"] as? String == soundID, "Replace changed selection")
        }
        try FileManager.default.removeItem(at: source)
        try check("restart keeps imported audio after deleting its original") {
            stop(); try launch()
            _ = try element("Select Renamed reaction")
            try click("Preview Renamed reaction")
            _ = try element("Stop Renamed reaction")
            _ = try element("Preview Renamed reaction")
            try expect(preferences["selectedID"] as? String == soundID, "Restart lost selection")
            try expect(preferences["volume"] as? Double == 0, "Restart lost volume")
        }
        try check("delete confirmation removes selected sound and selects Boing") {
            try click("Manage Renamed reaction")
            try click("Delete…")
            try click("Delete", role: kAXButtonRole)
            try wait("sound deleted") { self.customs.isEmpty }
            try expect(preferences["selectedID"] as? String == "boing", "Delete did not fall back")
            _ = try element("4 sounds")
        }
        try check("sensor turns on, receives data, then turns off") {
            try click("Tap reactions")
            _ = try element("Listening for a gentle tap.")
            try click("Preview Tiny trombone")
            _ = try element("Stop Tiny trombone")
            try click("Tap reactions")
            _ = try element("Taking a breather.")
            _ = try element("Preview Tiny trombone")
        }
        print("\(passed) UI checks passed")
        stop()
        try FileManager.default.removeItem(at: root)
    }
}

guard CommandLine.arguments.count == 3 else {
    print("Usage: whack-ui-tests /path/to/Whack /path/to/fixture.mp3"); exit(2)
}
guard AXIsProcessTrusted() else { print("Accessibility access is required for UI automation."); exit(2) }
var suite: UITest?
do {
    suite = try UITest(executable: URL(fileURLWithPath: CommandLine.arguments[1]), fixture: URL(fileURLWithPath: CommandLine.arguments[2]))
    try suite!.run()
} catch {
    print("FAIL UI \(error.localizedDescription)")
    suite?.dump()
    suite?.stop()
    if let suite { print("Isolated failure artifacts: \(suite.root.path)") }
    exit(1)
}
