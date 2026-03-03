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

// MARK: - Uploadcare

struct UploadcareUploadResult {
    let uuid: String
    let fileURL: URL
}

enum UploadcareError: LocalizedError {
    case missingPublicKey
    case fileTooLarge
    case invalidResponse
    case api(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingPublicKey:
            return "Uploadcare public API key is missing."
        case .fileTooLarge:
            return "Uploadcare direct upload supports files up to 100 MiB. Please upload a smaller file."
        case .invalidResponse:
            return "Uploadcare returned an invalid response."
        case .api(_, let message):
            return message
        }
    }
}

final class UploadcareService {
    static let shared = UploadcareService()

    private init() {}

    func upload(fileURL: URL, publicKey: String, cdnSubdomain: String) async throws -> UploadcareUploadResult {
        let key = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw UploadcareError.missingPublicKey
        }

        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = values.fileSize ?? 0
        if fileSize > 104_857_600 {
            throw UploadcareError.fileTooLarge
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://upload.uploadcare.com/base/")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendFormField(named: "UPLOADCARE_PUB_KEY", value: key, boundary: boundary)
        body.appendFormField(named: "UPLOADCARE_STORE", value: "auto", boundary: boundary)

        let fileData = try Data(contentsOf: fileURL)
        body.appendFileField(
            named: "file",
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType(for: fileURL),
            fileData: fileData,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else {
            throw UploadcareError.invalidResponse
        }

        if !(200..<300).contains(http.statusCode) {
            throw UploadcareError.api(
                statusCode: http.statusCode,
                message: uploadcareErrorMessage(from: data, statusCode: http.statusCode)
            )
        }

        struct Response: Decodable { let file: String }
        guard let parsed = try? JSONDecoder().decode(Response.self, from: data),
              !parsed.file.isEmpty else {
            throw UploadcareError.invalidResponse
        }

        let url = makeCDNURL(uuid: parsed.file, cdnSubdomain: cdnSubdomain)
        return UploadcareUploadResult(uuid: parsed.file, fileURL: url)
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }

    private func makeCDNURL(uuid: String, cdnSubdomain: String) -> URL {
        let trimmed = cdnSubdomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if trimmed.isEmpty {
            return URL(string: "https://ucarecdn.com/\(uuid)/")!
        }

        let host = trimmed.contains(".") ? trimmed : "\(trimmed).ucarecdn.com"
        return URL(string: "https://\(host)/\(uuid)/") ?? URL(string: "https://ucarecdn.com/\(uuid)/")!
    }

    private func uploadcareErrorMessage(from data: Data, statusCode: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = object["error"] as? String, !message.isEmpty {
                return message
            }
            if let message = object["error_content"] as? String, !message.isEmpty {
                return message
            }
            if let message = object["detail"] as? String, !message.isEmpty {
                return message
            }
        }
        return "Uploadcare upload failed (HTTP \(statusCode))."
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendFormField(named name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendFileField(named name: String, fileName: String, mimeType: String, fileData: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }
}
