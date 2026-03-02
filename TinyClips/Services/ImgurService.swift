import Foundation

// MARK: - Imgur Upload Result

struct ImgurUploadResult {
    let link: String
    let deleteHash: String
}

// MARK: - Imgur Error

enum ImgurError: LocalizedError {
    case fileTooLarge
    case uploadFailed(String)
    case invalidResponse
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "File is too large for Imgur (max 10 MB for images, 200 MB for videos/GIFs)."
        case .uploadFailed(let message):
            return "Imgur upload failed: \(message)"
        case .invalidResponse:
            return "Invalid response from Imgur."
        case .rateLimited:
            return "Imgur rate limit reached. Please try again later."
        }
    }
}

// MARK: - Imgur Service

@MainActor
class ImgurService {
    static let shared = ImgurService()

    // Anonymous uploads only need the Client ID (not the secret).
    // Register at https://api.imgur.com/oauth2/addclient to get your own.
    private let clientID = "YOUR_IMGUR_CLIENT_ID"

    private let imageEndpoint = URL(string: "https://api.imgur.com/3/image")!
    private let videoEndpoint = URL(string: "https://api.imgur.com/3/upload")!

    private let maxImageSize: Int64 = 10_485_760    // 10 MB
    private let maxVideoSize: Int64 = 209_715_200   // 200 MB

    private init() {}

    // MARK: - Upload

    func upload(fileURL: URL) async throws -> ImgurUploadResult {
        let ext = fileURL.pathExtension.lowercased()
        let isVideo = ext == "mp4"
        let isAnimated = ext == "gif" || isVideo

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0
        let sizeLimit = isAnimated ? maxVideoSize : maxImageSize

        guard fileSize <= sizeLimit else {
            throw ImgurError.fileTooLarge
        }

        let fileData = try Data(contentsOf: fileURL)
        let endpoint = isVideo ? videoEndpoint : imageEndpoint

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fieldName = isVideo ? "video" : "image"
        let mimeType = mimeType(for: ext)

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImgurError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw ImgurError.rateLimited
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = json["data"] as? [String: Any] else {
            throw ImgurError.invalidResponse
        }

        guard let success = json["success"] as? Bool, success,
              let link = responseData["link"] as? String else {
            let errorMessage = (responseData["error"] as? String) ?? "Unknown error"
            throw ImgurError.uploadFailed(errorMessage)
        }

        let deleteHash = (responseData["deletehash"] as? String) ?? ""
        return ImgurUploadResult(link: link, deleteHash: deleteHash)
    }

    // MARK: - Helpers

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Data Helper

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
