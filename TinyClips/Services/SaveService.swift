import AppKit
import UserNotifications

class SaveService {
    static let shared = SaveService()

    func generateURL(for type: CaptureType) -> URL {
        let directory = UserDefaults.standard.string(forKey: "saveDirectory")
            ?? (NSHomeDirectory() + "/Desktop")

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        let filename = "TinyClips \(timestamp).\(type.fileExtension)"
        return URL(fileURLWithPath: directory).appendingPathComponent(filename)
    }

    @MainActor
    func handleSavedFile(url: URL, type: CaptureType) {
        let settings = CaptureSettings.shared

        if settings.copyToClipboard {
            copyToClipboard(url: url, type: type)
        }

        if settings.showInFinder {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        showNotification(type: type, url: url)
    }

    private func copyToClipboard(url: URL, type: CaptureType) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch type {
        case .screenshot:
            if let image = NSImage(contentsOf: url) {
                pasteboard.writeObjects([image])
            }
        case .video, .gif:
            pasteboard.writeObjects([url as NSURL])
        }
    }

    private func showNotification(type: CaptureType, url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "\(type.label) Saved"
        content.body = url.lastPathComponent
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "TinyClips"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
