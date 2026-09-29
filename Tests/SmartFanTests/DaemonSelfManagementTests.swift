import Foundation
import Testing
@testable import SmartFanCore

@Suite("Daemon self-management")
struct DaemonSelfManagementTests {
    @Test("The install command quotes the path for the shell")
    func installCommandQuoting() {
        // A plain path is single-quoted.
        #expect(SmartFanDaemon.installShellCommand(cli: "/Applications/SmartFan.app/Contents/MacOS/smart-fan", ownerUID: 501)
                == "'/Applications/SmartFan.app/Contents/MacOS/smart-fan' install --owner-uid 501")
        // A space in the path (a user can put the app anywhere) stays one argument.
        let spaced = SmartFanDaemon.installShellCommand(cli: "/Volumes/My Disk/SmartFan.app/Contents/MacOS/smart-fan", ownerUID: 502)
        #expect(spaced == "'/Volumes/My Disk/SmartFan.app/Contents/MacOS/smart-fan' install --owner-uid 502")
        // An embedded single quote is escaped so it cannot end the quoting.
        let quoted = SmartFanDaemon.installShellCommand(cli: "/tmp/it's/smart-fan", ownerUID: 1)
        #expect(quoted == "'/tmp/it'\\''s/smart-fan' install --owner-uid 1")
    }

    @Test("The AppleScript wrapper escapes the command")
    func appleScriptEscaping() {
        let script = SmartFanDaemon.appleScript(shellCommand: "/bin/launchctl kickstart -k system/org.witt.smartfan.daemon")
        #expect(script == "do shell script \"/bin/launchctl kickstart -k system/org.witt.smartfan.daemon\" with administrator privileges")

        // Double quotes and backslashes inside the command must not break out of the
        // AppleScript string.
        let nasty = SmartFanDaemon.appleScript(shellCommand: "echo \"a\\b\"")
        #expect(nasty == "do shell script \"echo \\\"a\\\\b\\\"\" with administrator privileges")
    }

    @Test("Helper identity compares file contents")
    func helperIdentity() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("smartfan-id-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a")
        let b = dir.appendingPathComponent("b")
        let c = dir.appendingPathComponent("c")
        try Data("same".utf8).write(to: a)
        try Data("same".utf8).write(to: b)
        try Data("different".utf8).write(to: c)

        #expect(SmartFanDaemon.sha256(ofFile: a.path) == SmartFanDaemon.sha256(ofFile: b.path))
        #expect(SmartFanDaemon.sha256(ofFile: a.path) != SmartFanDaemon.sha256(ofFile: c.path))
        // A missing file has no digest rather than an empty one.
        #expect(SmartFanDaemon.sha256(ofFile: dir.appendingPathComponent("missing").path) == nil)
    }

    @Test("A clean machine reports nothing installed and no bundled binary")
    func cleanMachine() {
        // The test process is not run from an app bundle, so there is nothing to
        // install from — the UI's fallback path.
        #expect(SmartFanDaemon.embeddedCLIPath == nil)
    }
}
