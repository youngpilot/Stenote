import AppKit
import InputMethodKit

// IMKServer must stay alive for the full process lifetime.
// Its name must match InputMethodConnectionName in Info.plist exactly.
let server = IMKServer(
    name: "com.youngpilot.SteneoIM.IMK_Connection",
    bundleIdentifier: "com.youngpilot.Steneo.InputMethod"
)

NotificationBridge.shared.start()

NSApplication.shared.run()
