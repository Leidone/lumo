import AppKit
import ApplicationServices

/// The two privacy permissions some tools need. Both are optional: tools that need them
/// stay off until granted, and the UI explains why in plain words.
enum Permission: String {
    case accessibility, screenRecording

    @MainActor
    var isGranted: Bool {
        switch self {
        case .accessibility: return AXIsProcessTrusted()
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        }
    }

    /// Shows the system prompt (first time) and opens the matching Privacy pane.
    @MainActor
    func request() {
        switch self {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        openSettings()
    }

    @MainActor
    func openSettings() {
        let anchor = self == .accessibility ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
