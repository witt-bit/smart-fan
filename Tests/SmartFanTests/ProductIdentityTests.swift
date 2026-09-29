import Testing
@testable import SmartFanCore
import SmartFanLocalization

@Suite("Independent product identity")
struct ProductIdentityTests {
    @Test("Updates, IPC and resources use only the SmartFan identity")
    func independentIdentity() {
        #expect(UpdateChecker.releasesAPIURL.absoluteString == "https://api.github.com/repos/witt/smart-fan/releases/latest")
        #expect(UpdateChecker.releasesPageURL == "https://github.com/witt/smart-fan/releases/latest")
        #expect(SmartFanDaemon.socketPath == "/var/run/smart-fan.sock")
        #expect(SmartFanDaemon.label == "org.witt.smartfan.daemon")
        #expect(SmartFanDaemon.installPath == "/Library/PrivilegedHelperTools/org.witt.smartfan.helper")
        #expect(LocalizationCatalog.resourceBundleName == "SmartFan_SmartFanLocalization.bundle")
    }
}
