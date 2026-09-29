import Foundation
import Testing
@testable import SmartFanCore
import SmartFanLocalization

@Suite("Independent product identity")
struct ProductIdentityTests {
    @Test("Updates, IPC and resources use only the SmartFan identity")
    func independentIdentity() {
        #expect(UpdateChecker.releasesPageURL == "https://github.com/witt-bit/smart-fan/releases/latest")
        #expect(SmartFanDaemon.socketPath == "/var/run/smart-fan.sock")
        #expect(SmartFanDaemon.label == "org.witt.smartfan.daemon")
        #expect(SmartFanDaemon.installPath == "/Library/PrivilegedHelperTools/org.witt.smartfan.helper")
        #expect(LocalizationCatalog.resourceBundleName == "SmartFan_SmartFanLocalization.bundle")
    }

    @Test("The enclosing app bundle is found from an executable inside one")
    func enclosingBundle() {
        // The app invoking its own bundled CLI — the normal install path now.
        #expect(SmartFanDaemon.enclosingBundle(
            of: URL(fileURLWithPath: "/Applications/SmartFan.app/Contents/MacOS/smart-fan"))
            == "/Applications/SmartFan.app")
        // A deeper prefix still works (the walk is bounded, not fixed-depth).
        #expect(SmartFanDaemon.enclosingBundle(
            of: URL(fileURLWithPath: "/a/b/c/d/SmartFan.app/Contents/MacOS/smart-fan"))
            == "/a/b/c/d/SmartFan.app")
        // The build directory has no bundle above it.
        #expect(SmartFanDaemon.enclosingBundle(
            of: URL(fileURLWithPath: "/tmp/.build/release/smart-fan")) == nil)
        // The installed helper lives in a plain directory, not a bundle.
        #expect(SmartFanDaemon.enclosingBundle(
            of: URL(fileURLWithPath: SmartFanDaemon.installPath)) == nil)
    }
}
