import Foundation
import SwiftUI
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import Security

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

    var pixelWidth: Int {
        max(1, Int((sourceRect.width * scaleFactor).rounded()))
    }

    var pixelHeight: Int {
        max(1, Int((sourceRect.height * scaleFactor).rounded()))
    }

    func makeStreamConfig() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = pixelWidth
        config.height = pixelHeight
        config.scalesToFit = true
        config.showsCursor = true
        return config
    }

    func makeFilter() async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == self.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let includeTinyClips = CaptureSettings.shared.includeTinyClipsInCapture
        let excludedApps: [SCRunningApplication] = includeTinyClips ? [] : content.applications.filter {
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
    @AppStorage("copyScreenshotToClipboard") var copyScreenshotToClipboard: Bool = true
    @AppStorage("copyVideoToClipboard") var copyVideoToClipboard: Bool = false
    @AppStorage("copyGifToClipboard") var copyGifToClipboard: Bool = false
    @AppStorage("showInFinder") var showInFinder: Bool = false
    @AppStorage("showSaveNotifications") var showSaveNotifications: Bool = false
    @AppStorage("showInDock") var showInDock: Bool = false
    @AppStorage("fileNameTemplate") var fileNameTemplate: String = "TinyClips {date} at {time}"
    @AppStorage("uploadcareEnabled") var uploadcareEnabled: Bool = false
    @AppStorage("clipsManagerShowAutoTags") var clipsManagerShowAutoTags: Bool = true
    @AppStorage("clipsManagerShowNotesPreview") var clipsManagerShowNotesPreview: Bool = true
    @AppStorage("clipsManagerShowQuickActions") var clipsManagerShowQuickActions: Bool = true
    @AppStorage("clipsManagerShowUploadStatus") var clipsManagerShowUploadStatus: Bool = true
    @AppStorage("clipsManagerConfirmDelete") var clipsManagerConfirmDelete: Bool = true
    @AppStorage("clipsManagerCompactListDensity") var clipsManagerCompactListDensity: Bool = false
    @AppStorage("clipsManagerSelectionRowTapSelects") var clipsManagerSelectionRowTapSelects: Bool = true
    @AppStorage("clipsManagerIgnoreNonTinyClipsFiles") var clipsManagerIgnoreNonTinyClipsFiles: Bool = false
    @AppStorage("clipsManagerRememberLastState") var clipsManagerRememberLastState: Bool = true
    @AppStorage("clipsManagerDefaultViewMode") var clipsManagerDefaultViewMode: String = "grid"
    @AppStorage("clipsManagerDefaultSortOption") var clipsManagerDefaultSortOption: String = "Newest First"
    @AppStorage("clipsManagerDefaultFilterType") var clipsManagerDefaultFilterType: String = "All"
    @AppStorage("clipsManagerDefaultDateFilter") var clipsManagerDefaultDateFilter: String = "Any Date"
    @AppStorage("clipsManagerAutoRefreshSeconds") var clipsManagerAutoRefreshSeconds: Int = 0
    @AppStorage("clipsManagerArchiveOldClips") var clipsManagerArchiveOldClips: Bool = false
    @AppStorage("clipsManagerArchiveAfterDays") var clipsManagerArchiveAfterDays: Int = 30
    @AppStorage("clipsManagerAutoUploadAfterSave") var clipsManagerAutoUploadAfterSave: Bool = false
    @AppStorage("clipsManagerAutoCopyUploadLink") var clipsManagerAutoCopyUploadLink: Bool = false
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
    @AppStorage("screenshotCountdownEnabled") var screenshotCountdownEnabled: Bool = false
    @AppStorage("screenshotCountdownDuration") var screenshotCountdownDuration: Int = 3
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("alwaysCaptureMainDisplay") var alwaysCaptureMainDisplay: Bool = false
    @AppStorage("showRegionIndicator") var showRegionIndicator: Bool = true
    @AppStorage("includeTinyClipsInCapture") var includeTinyClipsInCapture: Bool = false

#if APPSTORE
    var hasCustomSaveDirectory: Bool {
        !saveDirectoryBookmark.isEmpty
    }
#endif

    var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: screenshotFormat) ?? .jpeg }
        set { screenshotFormat = newValue.rawValue }
    }

    func shouldCopyToClipboard(for type: CaptureType) -> Bool {
        switch type {
        case .screenshot:
            return copyScreenshotToClipboard
        case .video:
            return copyVideoToClipboard
        case .gif:
            return copyGifToClipboard
        }
    }

    func resetToDefaults() {
        // Remove all keys in one pass so only a single objectWillChange fires
        let keys: [String] = [
            "saveDirectory", "copyToClipboard", "copyScreenshotToClipboard", "copyVideoToClipboard", "copyGifToClipboard",
            "showInFinder", "showSaveNotifications", "showInDock",
            "autoUpdateEnabled",
            "fileNameTemplate",
            "uploadcareEnabled", "clipsManagerShowAutoTags", "clipsManagerShowNotesPreview", "clipsManagerShowQuickActions",
            "clipsManagerShowUploadStatus", "clipsManagerConfirmDelete", "clipsManagerCompactListDensity",
            "clipsManagerSelectionRowTapSelects", "clipsManagerIgnoreNonTinyClipsFiles", "clipsManagerRememberLastState",
            "clipsManagerDefaultViewMode", "clipsManagerDefaultSortOption", "clipsManagerDefaultFilterType", "clipsManagerDefaultDateFilter",
            "clipsManagerAutoRefreshSeconds", "clipsManagerArchiveOldClips", "clipsManagerArchiveAfterDays",
            "clipsManagerAutoUploadAfterSave", "clipsManagerAutoCopyUploadLink",
            "clipsManagerLastViewMode", "clipsManagerLastSortOption", "clipsManagerLastFilterType", "clipsManagerLastDateFilter",
            "clipsManagerLastSmartCollection", "clipsManagerLastSearchText", "clipsManagerLastSelectedTag", "clipsManagerLastSelectedCollection",
            "gifFrameRate", "gifMaxWidth", "videoFrameRate", "showTrimmer",
            "recordAudio", "recordMicrophone", "showScreenshotEditor", "showGifTrimmer",
            "saveImmediatelyScreenshot", "saveImmediatelyVideo", "saveImmediatelyGif",
            "screenshotFormat", "screenshotScale", "jpegQuality",
            "videoCountdownEnabled", "videoCountdownDuration",
            "gifCountdownEnabled", "gifCountdownDuration",
            "screenshotCountdownEnabled", "screenshotCountdownDuration",
            "hasCompletedOnboarding", "alwaysCaptureMainDisplay", "showRegionIndicator",
            "includeTinyClipsInCapture",
            "appStoreClipCountForReview", "appStoreReviewRequested"
        ]
#if APPSTORE
        let masKeys: [String] = ["saveDirectoryBookmark", "saveDirectoryDisplayPath"]
#else
        let masKeys: [String] = []
#endif
        for key in keys + masKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UploadcareCredentialsStore.shared.clearAll()
        objectWillChange.send()
    }
}

// MARK: - Uploadcare credentials

final class UploadcareCredentialsStore {
    static let shared = UploadcareCredentialsStore()

    struct Credentials: Codable {
        var publicKey: String
        var secretKey: String

        static let empty = Credentials(publicKey: "", secretKey: "")
    }

    private enum Account {
        static let credentials = "uploadcare-credentials"
    }

    private let service = "com.refractored.tinyclips.uploadcare"
    private var cachedCredentials: Credentials?
    private init() {}

    func credentials() -> Credentials {
        if let cachedCredentials {
            return cachedCredentials
        }
        let loaded = loadCredentialsFromKeychain() ?? .empty
        cachedCredentials = loaded
        return loaded
    }

    func setPublicKey(_ value: String) {
        var updated = credentials()
        updated.publicKey = value
        persistCredentials(updated)
    }

    func setSecretKey(_ value: String) {
        var updated = credentials()
        updated.secretKey = value
        persistCredentials(updated)
    }

    func clearAll() {
        cachedCredentials = .empty
        removeKeychainValue(for: Account.credentials)
    }

    private func loadCredentialsFromKeychain() -> Credentials? {
        guard let data = keychainData(for: Account.credentials),
              let decoded = try? JSONDecoder().decode(Credentials.self, from: data) else {
            return nil
        }
        return Credentials(
            publicKey: decoded.publicKey.trimmingCharacters(in: .whitespacesAndNewlines),
            secretKey: decoded.secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func persistCredentials(_ credentials: Credentials) {
        let normalized = Credentials(
            publicKey: credentials.publicKey.trimmingCharacters(in: .whitespacesAndNewlines),
            secretKey: credentials.secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        cachedCredentials = normalized

        if normalized.publicKey.isEmpty && normalized.secretKey.isEmpty {
            removeKeychainValue(for: Account.credentials)
            return
        }

        guard let data = try? JSONEncoder().encode(normalized) else { return }
        setKeychainData(data, for: Account.credentials)
    }

    private func keychainData(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return data
    }

    private func setKeychainData(_ data: Data, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            _ = SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func removeKeychainValue(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
