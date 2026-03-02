import AppKit
import UserNotifications

class SaveService {
    static let shared = SaveService()

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

        let filename = generatedFileName(for: type, fileExtension: fileExtension)

#if APPSTORE
        return uniqueURL(in: directoryURL, filename: filename)
#else
        return uniqueURL(in: URL(fileURLWithPath: directory), filename: filename)
#endif
    }

    func generatedFileName(for type: CaptureType, fileExtension: String, date: Date = Date()) -> String {
        let settings = CaptureSettings.shared
        let rawTemplate = settings.fileNameTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = rawTemplate.isEmpty ? "TinyClips {date} at {time}" : rawTemplate

        var stem = template
            .replacingOccurrences(of: "{app}", with: "TinyClips")
            .replacingOccurrences(of: "{type}", with: type.label)
            .replacingOccurrences(of: "{date}", with: formatted(date, format: "yyyy-MM-dd"))
            .replacingOccurrences(of: "{time}", with: formatted(date, format: "HH.mm.ss"))
            .replacingOccurrences(of: "{datetime}", with: formatted(date, format: "yyyy-MM-dd_HH.mm.ss"))

        stem = sanitizedFilenameStem(stem, fallbackDate: date)

        let cleanExtension = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        return cleanExtension.isEmpty ? stem : "\(stem).\(cleanExtension)"
    }

    func namingPreview(for type: CaptureType = .screenshot) -> String {
        generatedFileName(for: type, fileExtension: type.fileExtension)
    }

    private func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func sanitizedFilenameStem(_ stem: String, fallbackDate: Date) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?*\"<>|")
        var cleaned = stem
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .\n\t"))

        if cleaned.isEmpty {
            cleaned = "TinyClips \(formatted(fallbackDate, format: "yyyy-MM-dd_HH.mm.ss"))"
        }

        return cleaned
    }

    private func uniqueURL(in directoryURL: URL, filename: String) -> URL {
        let initialURL = directoryURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        let ext = initialURL.pathExtension
        let stem = initialURL.deletingPathExtension().lastPathComponent
        var suffix = 2

        while true {
            let candidateName = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            let candidateURL = directoryURL.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            suffix += 1
        }
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
