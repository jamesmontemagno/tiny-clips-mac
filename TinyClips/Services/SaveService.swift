import AppKit
import UserNotifications

class SaveService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SaveService()
    private let notificationURLKey = "savedFileURL"

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

#if APPSTORE
    private let saveDirectoryBookmarkKey = "saveDirectoryBookmark"
    private var activeSecurityScopedDirectoryURL: URL?
    private let bookmarkQueue = DispatchQueue(label: "com.tinyclips.save-service.bookmark")
#endif

    func generateURL(for type: CaptureType) -> URL {
        return generateURL(for: type, fileExtension: type.fileExtension)
    }

    func generateURL(for type: CaptureType, fileExtension: String) -> URL {
#if APPSTORE
        let directoryURL = outputDirectoryURL(for: type)

        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
#else
        let directory = UserDefaults.standard.string(forKey: "saveDirectory")
            ?? (NSHomeDirectory() + "/Desktop")

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
#endif

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        let filename = "TinyClips \(timestamp).\(fileExtension)"

#if APPSTORE
        return directoryURL.appendingPathComponent(filename)
#else
        return URL(fileURLWithPath: directory).appendingPathComponent(filename)
#endif
    }

#if APPSTORE
    private func outputDirectoryURL(for type: CaptureType) -> URL {
        if let customDirectory = customDirectoryURLFromBookmark() {
            return customDirectory
        }
        return defaultDirectoryURL(for: type)
    }

    private func defaultDirectoryURL(for type: CaptureType) -> URL {
        let fallbackBase = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let baseURL: URL

        switch type {
        case .video:
            baseURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? fallbackBase
        case .screenshot, .gif:
            baseURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? fallbackBase
        }

        return baseURL.appendingPathComponent("TinyClips", isDirectory: true)
    }

    private func customDirectoryURLFromBookmark() -> URL? {
        bookmarkQueue.sync {
            if let activeSecurityScopedDirectoryURL {
                return activeSecurityScopedDirectoryURL
            }

            guard let bookmarkData = UserDefaults.standard.data(forKey: saveDirectoryBookmarkKey), !bookmarkData.isEmpty else {
                return nil
            }

            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale,
                   let refreshedBookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(refreshedBookmark, forKey: saveDirectoryBookmarkKey)
                }

                guard url.startAccessingSecurityScopedResource() else {
                    return nil
                }

                activeSecurityScopedDirectoryURL = url
                return url
            } catch {
                UserDefaults.standard.removeObject(forKey: saveDirectoryBookmarkKey)
                return nil
            }
        }
    }
#endif

    @MainActor
    func handleSavedFile(url: URL, type: CaptureType) {
        let settings = CaptureSettings.shared

        if settings.copyToClipboard {
            copyToClipboard(url: url, type: type)
        }

        if settings.showInFinder {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        if settings.showSaveNotifications {
            showNotification(type: type, url: url)
        }
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
        content.userInfo = [notificationURLKey: url.path]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard let savedFilePath = response.notification.request.content.userInfo[notificationURLKey] as? String else {
            return
        }

        let savedFileURL = URL(fileURLWithPath: savedFilePath)
        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([savedFileURL])
        }
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
