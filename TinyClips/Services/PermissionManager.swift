import AppKit
import ScreenCaptureKit

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var hasPermission = false

    func checkPermission() -> Bool {
        // CGPreflightScreenCaptureAccess is unreliable on macOS 15+ — it can
        // return false even when permission is granted. Try ScreenCaptureKit
        // first as the source of truth, then fall back to the CG APIs.
        if hasPermission { return true }

        // Quick CG check — if it says yes, trust it
        if CGPreflightScreenCaptureAccess() {
            hasPermission = true
            return true
        }

        // CG said no, but it may be wrong. Do a real SCK query to confirm.
        let semaphore = DispatchSemaphore(value: 0)
        var sckGranted = false
        Task.detached {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                sckGranted = true
            } catch {}
            semaphore.signal()
        }
        semaphore.wait()

        if sckGranted {
            hasPermission = true
            return true
        }

        // Genuinely not granted — request access
        CGRequestScreenCaptureAccess()
        showPermissionAlert()
        return false
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "TinyClips needs screen recording permission to capture your screen. Please grant access in System Settings > Privacy & Security > Screen Recording, then restart TinyClips."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
