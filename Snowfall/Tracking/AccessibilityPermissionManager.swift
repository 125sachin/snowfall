import AppKit
import ApplicationServices
import Observation

/// Tracks Accessibility trust. Used only for window tracking; never required for snowfall itself.
@MainActor
@Observable
final class AccessibilityPermissionManager {
    private(set) var isTrusted = AXIsProcessTrusted()
    @ObservationIgnored private var promptedThisSession = false

    /// Re-reads trust (cheap). Returns true if it changed (granted or revoked).
    @discardableResult
    func refresh() -> Bool {
        let now = AXIsProcessTrusted()
        defer { isTrusted = now }
        return now != isTrusted
    }

    /// User-initiated. Shows the system prompt at most once per launch, then opens System Settings.
    func requestAccess() {
        if !promptedThisSession {
            promptedThisSession = true
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        } else {
            openSystemSettings()
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
