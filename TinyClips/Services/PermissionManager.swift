import AppKit
import AVFoundation
import ScreenCaptureKit
import UserNotifications
#if !APPSTORE
import IOKit.hid
#endif

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var hasPermission = false

    func checkPermission() async -> Bool {
        await checkScreenRecordingPermission(requestIfNeeded: true)
    }

    func hasScreenRecordingPermission() -> Bool {
        if hasPermission { return true }

        if CGPreflightScreenCaptureAccess() {
            hasPermission = true
            return true
        }

        return false
    }

    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func microphonePermissionGranted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await notificationPermissionStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func notificationPermissionGranted() async -> Bool {
        let status = await notificationPermissionStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

#if !APPSTORE
    /// Global `NSEvent` key-down monitoring (used by the keyboard overlay) requires
    /// the user to grant Input Monitoring in Privacy & Security. Without it, only
    /// modifier (`flagsChanged`) events are delivered for other apps. Sandboxed
    /// builds cannot use Input Monitoring at all, so this is gated to the direct
    /// distribution target.
    func hasInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Triggers the system's Input Monitoring prompt the first time it is called
    /// for this app. On subsequent launches macOS returns the current grant
    /// state without prompting again.
    @discardableResult
    func requestInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestListenEventAccess()
        }
        return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
#endif

    // MARK: - Internal

    private func checkScreenRecordingPermission(requestIfNeeded: Bool) async -> Bool {
        // CGPreflightScreenCaptureAccess is unreliable on macOS 15+ — it can
        // return false even when permission is granted. Try ScreenCaptureKit
        // first as the source of truth, then fall back to the CG APIs.
        if hasPermission { return true }

        // Quick CG check — if it says yes, trust it
        if CGPreflightScreenCaptureAccess() {
            hasPermission = true
            return true
        }

        guard requestIfNeeded else {
            return false
        }

        // CG said no, but it may be wrong. Do a real SCK query to confirm.
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            hasPermission = true
            return true
        } catch {}

        // Genuinely not granted — request access
        _ = CGRequestScreenCaptureAccess()
        return false
    }

    private func notificationPermissionStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

}
