import Foundation
import AppKit

// MARK: - Clip Item

struct ClipItem: Identifiable, Equatable {
    static let fileNamePrefix = "TinyClips "

    let id: String
    let url: URL
    let type: ClipType
    let createdAt: Date

    enum ClipType: String, CaseIterable {
        case screenshot
        case video
        case gif

        var systemImage: String {
            switch self {
            case .screenshot: return "camera"
            case .video: return "video"
            case .gif: return "photo.on.rectangle"
            }
        }

        var label: String {
            switch self {
            case .screenshot: return "Screenshot"
            case .video: return "Video"
            case .gif: return "GIF"
            }
        }

        var fileExtensions: [String] {
            switch self {
            case .screenshot: return ["png", "jpg", "jpeg"]
            case .video: return ["mp4", "mov"]
            case .gif: return ["gif"]
            }
        }
    }

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id
    }

    static func from(url: URL) -> ClipItem? {
        let ext = url.pathExtension.lowercased()
        let type: ClipType
        if ClipType.screenshot.fileExtensions.contains(ext) {
            type = .screenshot
        } else if ClipType.video.fileExtensions.contains(ext) {
            type = .video
        } else if ClipType.gif.fileExtensions.contains(ext) {
            type = .gif
        } else {
            return nil
        }

        let createdAt: Date
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let date = attrs[.creationDate] as? Date {
            createdAt = date
        } else {
            createdAt = Date()
        }

        return ClipItem(id: url.path, url: url, type: type, createdAt: createdAt)
    }
}
