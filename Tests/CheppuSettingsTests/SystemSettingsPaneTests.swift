import CheppuCore
import Testing

@testable import CheppuSettings

// Where the button next to a permission goes. Nothing here opens anything: what
// is asserted is the address, because the failure this guards against is a
// button that opens System Settings' front door and leaves the user to hunt
// (`docs/product-experience.md` §9).
@Suite("System Settings pane")
struct SystemSettingsPaneTests {
    @Test("Each permission is opened at its own pane, not at the front door")
    func eachPermissionIsOpenedAtItsOwnPane() {
        // The `x-apple.systempreferences` scheme with the pane named after it
        // is what opens the pane itself. A plain scheme, or the same address
        // for both, would be Cheppu saying "it is in there somewhere".
        #expect(SystemSettingsPane.address(of: .microphone).hasSuffix("Privacy_Microphone"))
        #expect(SystemSettingsPane.address(of: .accessibility).hasSuffix("Privacy_Accessibility"))

        for permission in Permission.allCases {
            #expect(
                SystemSettingsPane.address(of: permission)
                    .hasPrefix("x-apple.systempreferences:")
            )
        }
    }

    @Test("The Accessibility pane is the one the app has always opened")
    func theAccessibilityPaneIsTheOneTheAppHasAlwaysOpened() {
        // The menu bar's "The Hotkey Needs Accessibility…" and the Settings
        // window's button are the same journey, and they are now the same line
        // of code. Written out once here so that changing it is a decision
        // rather than a typo.
        #expect(
            SystemSettingsPane.address(of: .accessibility)
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }
}
