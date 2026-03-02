import Foundation
import SwiftUI
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - Capture Region

struct CaptureRegion: Sendable {
    let sourceRect: CGRect
    let displayID: CGDirectDisplayID
    let scaleFactor: CGFloat

    static func fullScreen(for screen: NSScreen) -> CaptureRegion? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }

        return CaptureRegion(
            sourceRect: CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height),
            displayID: displayID,
            scaleFactor: screen.backingScaleFactor
        )
    }

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
        case .screenshot: return CaptureSettings.shared.imageFormat.rawValue
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

// MARK: - Image Format

enum ImageFormat: String, CaseIterable {
    case png = "png"
    case jpeg = "jpg"

    var label: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }
}

// MARK: - Settings

class CaptureSettings: ObservableObject {
    static let shared = CaptureSettings()

    @AppStorage("saveDirectory") var saveDirectory: String = NSHomeDirectory() + "/Desktop"
#if APPSTORE
    @AppStorage("saveDirectoryBookmark") var saveDirectoryBookmark: Data = Data()
    @AppStorage("saveDirectoryDisplayPath") var saveDirectoryDisplayPath: String = ""
#endif
    @AppStorage("copyToClipboard") var copyToClipboard: Bool = true
    @AppStorage("showInFinder") var showInFinder: Bool = false
    @AppStorage("showSaveNotifications") var showSaveNotifications: Bool = false
    @AppStorage("fileNameTemplate") var fileNameTemplate: String = "TinyClips {date} at {time}"
    @AppStorage("gifFrameRate") var gifFrameRate: Double = 10
    @AppStorage("gifMaxWidth") var gifMaxWidth: Int = 640
    @AppStorage("videoFrameRate") var videoFrameRate: Int = 30
    @AppStorage("showTrimmer") var showTrimmer: Bool = true
    @AppStorage("recordAudio") var recordAudio: Bool = false
    @AppStorage("recordMicrophone") var recordMicrophone: Bool = false
    @AppStorage("showScreenshotEditor") var showScreenshotEditor: Bool = true
    @AppStorage("showGifTrimmer") var showGifTrimmer: Bool = true
    @AppStorage("saveImmediatelyScreenshot") var saveImmediatelyScreenshot: Bool = true
    @AppStorage("saveImmediatelyVideo") var saveImmediatelyVideo: Bool = true
    @AppStorage("saveImmediatelyGif") var saveImmediatelyGif: Bool = true
    @AppStorage("screenshotFormat") var screenshotFormat: String = ImageFormat.jpeg.rawValue
    @AppStorage("screenshotScale") var screenshotScale: Int = 100
    @AppStorage("jpegQuality") var jpegQuality: Double = 0.85
    @AppStorage("videoCountdownEnabled") var videoCountdownEnabled: Bool = true
    @AppStorage("videoCountdownDuration") var videoCountdownDuration: Int = 3
    @AppStorage("gifCountdownEnabled") var gifCountdownEnabled: Bool = true
    @AppStorage("gifCountdownDuration") var gifCountdownDuration: Int = 3
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("alwaysCaptureMainDisplay") var alwaysCaptureMainDisplay: Bool = false
    @AppStorage("showRegionIndicator") var showRegionIndicator: Bool = true

#if APPSTORE
    var hasCustomSaveDirectory: Bool {
        !saveDirectoryBookmark.isEmpty
    }
#endif

    var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: screenshotFormat) ?? .jpeg }
        set { screenshotFormat = newValue.rawValue }
    }

    func resetToDefaults() {
        // Remove all keys in one pass so only a single objectWillChange fires
        let keys: [String] = [
            "saveDirectory", "copyToClipboard", "showInFinder", "showSaveNotifications",
            "fileNameTemplate",
            "gifFrameRate", "gifMaxWidth", "videoFrameRate", "showTrimmer",
            "recordAudio", "recordMicrophone", "showScreenshotEditor", "showGifTrimmer",
            "saveImmediatelyScreenshot", "saveImmediatelyVideo", "saveImmediatelyGif",
            "screenshotFormat", "screenshotScale", "jpegQuality",
            "videoCountdownEnabled", "videoCountdownDuration",
            "gifCountdownEnabled", "gifCountdownDuration",
            "hasCompletedOnboarding", "alwaysCaptureMainDisplay", "showRegionIndicator"
        ]
#if APPSTORE
        let masKeys: [String] = ["saveDirectoryBookmark", "saveDirectoryDisplayPath"]
#else
        let masKeys: [String] = []
#endif
        for key in keys + masKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        objectWillChange.send()
    }
}
