import Foundation
import SwiftUI
import AppKit
import ScreenCaptureKit

// MARK: - Capture Region

struct CaptureRegion: Sendable {
    let sourceRect: CGRect
    let displayID: CGDirectDisplayID
    let scaleFactor: CGFloat

    func makeStreamConfig() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Int(sourceRect.width * scaleFactor)
        config.height = Int(sourceRect.height * scaleFactor)
        config.scalesToFit = false
        config.showsCursor = true
        return config
    }

    func makeFilter() async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == self.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let excludedApps = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        return SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
    }
}

// MARK: - Capture Type

enum CaptureType: String {
    case screenshot, video, gif

    var fileExtension: String {
        switch self {
        case .screenshot: return "png"
        case .video: return "mp4"
        case .gif: return "gif"
        }
    }

    var label: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .video: return "Video"
        case .gif: return "GIF"
        }
    }
}

// MARK: - Capture Error

enum CaptureError: LocalizedError {
    case displayNotFound
    case saveFailed
    case noFrames
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "Could not find the selected display."
        case .saveFailed: return "Failed to save the capture."
        case .noFrames: return "No frames were captured."
        case .permissionDenied: return "Screen recording permission is required."
        }
    }
}

// MARK: - Settings

class CaptureSettings: ObservableObject {
    static let shared = CaptureSettings()

    @AppStorage("saveDirectory") var saveDirectory: String = NSHomeDirectory() + "/Desktop"
    @AppStorage("copyToClipboard") var copyToClipboard: Bool = true
    @AppStorage("showInFinder") var showInFinder: Bool = false
    @AppStorage("gifFrameRate") var gifFrameRate: Double = 10
    @AppStorage("gifMaxWidth") var gifMaxWidth: Int = 640
    @AppStorage("videoFrameRate") var videoFrameRate: Int = 30
    @AppStorage("showTrimmer") var showTrimmer: Bool = true
    @AppStorage("recordAudio") var recordAudio: Bool = false
    @AppStorage("recordMicrophone") var recordMicrophone: Bool = false
    @AppStorage("showScreenshotEditor") var showScreenshotEditor: Bool = true
}
