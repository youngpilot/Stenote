import AppKit
import InputMethodKit

// IMKServer must stay alive for the full process lifetime.
// Its name must match InputMethodConnectionName in Info.plist exactly.
let server = IMKServer(
    name: "com.youngpilot.StenoteIM.IMK_Connection",
    bundleIdentifier: "com.youngpilot.Stenote.InputMethod"
)

NotificationBridge.shared.start()

NSApplication.shared.run()
