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

enum CaptureTarget {
    case region(CaptureRegion)
    case window(SCWindow)

    var region: CaptureRegion? {
        if case let .region(region) = self {
            return region
        }
        return nil
    }

    func prepare() async throws -> PreparedCaptureTarget {
        switch self {
        case let .region(region):
            return PreparedCaptureTarget(
                filter: try await region.makeFilter(),
                config: region.makeStreamConfig(),
                pixelWidth: region.pixelWidth,
                pixelHeight: region.pixelHeight
            )
        case let .window(window):
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let pixelSize = Self.pixelSize(for: filter)
            let config = SCStreamConfiguration()
            config.width = pixelSize.width
            config.height = pixelSize.height
            config.scalesToFit = false
            config.showsCursor = true
            config.includeChildWindows = true

            return PreparedCaptureTarget(
                filter: filter,
                config: config,
                pixelWidth: pixelSize.width,
                pixelHeight: pixelSize.height
            )
        }
    }

    private static func pixelSize(for filter: SCContentFilter) -> (width: Int, height: Int) {
        let scale = CGFloat(filter.pointPixelScale)
        return (
            width: max(1, Int((filter.contentRect.width * scale).rounded())),
            height: max(1, Int((filter.contentRect.height * scale).rounded()))
        )
    }
}

struct PreparedCaptureTarget {
    let filter: SCContentFilter
    let config: SCStreamConfiguration
    let pixelWidth: Int
    let pixelHeight: Int
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
    case microphoneUnavailable
    case microphoneConnectionFailed
    case microphoneReadFailed

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "Could not find the selected display."
        case .saveFailed: return "Failed to save the capture."
        case .noFrames: return "No frames were captured."
        case .permissionDenied: return "Screen recording permission is required."
        case .microphoneUnavailable: return "The selected microphone is unavailable. Choose another input device in Settings."
        case .microphoneConnectionFailed: return "Could not connect to the selected microphone."
        case .microphoneReadFailed: return "Could not read audio from the selected microphone."
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

struct MouseClickOverlayStyle: Sendable {
    let colorHex: String
    let size: CGFloat
    let strokeWidth: CGFloat
    let opacity: CGFloat
    let duration: TimeInterval
}

extension MouseClickOverlayStyle {
    var color: NSColor {
        NSColor(hexRGBString: colorHex) ?? .white
    }
}

extension NSColor {
    convenience init?(hexRGBString: String) {
        var value = hexRGBString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        guard value.count == 6, let rgb = Int(value, radix: 16) else {
            return nil
        }

        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }

    var hexRGBString: String {
        guard let resolved = usingColorSpace(.sRGB) ?? usingColorSpace(.deviceRGB) else {
            return "#FFFFFF"
        }

        return String(
            format: "#%02X%02X%02X",
            Int((resolved.redComponent * 255.0).rounded()),
            Int((resolved.greenComponent * 255.0).rounded()),
            Int((resolved.blueComponent * 255.0).rounded())
        )
    }
}

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
    @AppStorage("showMouseClickVisualsInVideo") var showMouseClickVisualsInVideo: Bool = false
    @AppStorage("showMouseClickVisualsInGif") var showMouseClickVisualsInGif: Bool = false
    @AppStorage("gifMouseClicksUseVideoSettings") var gifMouseClicksUseVideoSettings: Bool = false
    @AppStorage("videoMouseClickColorHex") var videoMouseClickColorHex: String = "#FFFFFF"
    @AppStorage("videoMouseClickSize") var videoMouseClickSize: Double = 32
    @AppStorage("videoMouseClickStrokeWidth") var videoMouseClickStrokeWidth: Double = 3
    @AppStorage("videoMouseClickOpacity") var videoMouseClickOpacity: Double = 0.85
    @AppStorage("videoMouseClickDuration") var videoMouseClickDuration: Double = 0.45
    @AppStorage("gifMouseClickColorHex") var gifMouseClickColorHex: String = "#FFFFFF"
    @AppStorage("gifMouseClickSize") var gifMouseClickSize: Double = 24
    @AppStorage("gifMouseClickStrokeWidth") var gifMouseClickStrokeWidth: Double = 3
    @AppStorage("gifMouseClickOpacity") var gifMouseClickOpacity: Double = 0.8
    @AppStorage("gifMouseClickDuration") var gifMouseClickDuration: Double = 0.45
    @AppStorage("showTrimmer") var showTrimmer: Bool = true
    @AppStorage("recordAudio") var recordAudio: Bool = false
    @AppStorage("recordMicrophone") var recordMicrophone: Bool = false
    @AppStorage("selectedMicrophoneID") var selectedMicrophoneID: String = ""
    @AppStorage("showScreenshotEditor") var showScreenshotEditor: Bool = true
    @AppStorage("showGifTrimmer") var showGifTrimmer: Bool = true
    @AppStorage("saveImmediatelyScreenshot") var saveImmediatelyScreenshot: Bool = true
    @AppStorage("saveImmediatelyVideo") var saveImmediatelyVideo: Bool = true
    @AppStorage("saveImmediatelyGif") var saveImmediatelyGif: Bool = true
    @AppStorage("showScreenshotCapturePicker") var showScreenshotCapturePicker: Bool = true
    @AppStorage("showVideoCapturePicker") var showVideoCapturePicker: Bool = true
    @AppStorage("showGifCapturePicker") var showGifCapturePicker: Bool = true
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
    // Custom global hotkeys (stored as Carbon keyCode + modifiers bitmask).
    // Defaults: ⌃⌥⌘5 / ⌃⌥⌘6 / ⌃⌥⌘7
    // 6400 = controlKey (4096) | optionKey (2048) | cmdKey (256)
    @AppStorage("screenshotHotKeyCode") var screenshotHotKeyCode: Int = 23      // kVK_ANSI_5
    @AppStorage("screenshotHotKeyModifiers") var screenshotHotKeyModifiers: Int = 6400
    @AppStorage("videoHotKeyCode") var videoHotKeyCode: Int = 22                // kVK_ANSI_6
    @AppStorage("videoHotKeyModifiers") var videoHotKeyModifiers: Int = 6400
    @AppStorage("gifHotKeyCode") var gifHotKeyCode: Int = 26                    // kVK_ANSI_7
    @AppStorage("gifHotKeyModifiers") var gifHotKeyModifiers: Int = 6400

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

    func shouldShowCapturePicker(for type: CaptureType) -> Bool {
        switch type {
        case .screenshot:
            return showScreenshotCapturePicker
        case .video:
            return showVideoCapturePicker
        case .gif:
            return showGifCapturePicker
        }
    }

    func mouseClickOverlayStyle(for type: CaptureType) -> MouseClickOverlayStyle {
        switch type {
        case .video:
            return MouseClickOverlayStyle(
                colorHex: videoMouseClickColorHex,
                size: CGFloat(videoMouseClickSize),
                strokeWidth: CGFloat(videoMouseClickStrokeWidth),
                opacity: CGFloat(videoMouseClickOpacity),
                duration: videoMouseClickDuration
            )
        case .gif:
            if gifMouseClicksUseVideoSettings {
                return mouseClickOverlayStyle(for: .video)
            }
            return MouseClickOverlayStyle(
                colorHex: gifMouseClickColorHex,
                size: CGFloat(gifMouseClickSize),
                strokeWidth: CGFloat(gifMouseClickStrokeWidth),
                opacity: CGFloat(gifMouseClickOpacity),
                duration: gifMouseClickDuration
            )
        case .screenshot:
            return MouseClickOverlayStyle(
                colorHex: "#FFFFFF",
                size: 32,
                strokeWidth: 3,
                opacity: 0.85,
                duration: 0.45
            )
        }
    }

    func shouldShowMouseClickVisuals(for type: CaptureType) -> Bool {
        switch type {
        case .video:
            return showMouseClickVisualsInVideo
        case .gif:
            return gifMouseClicksUseVideoSettings ? showMouseClickVisualsInVideo : showMouseClickVisualsInGif
        case .screenshot:
            return false
        }
    }

    func setShowMouseClickVisuals(_ isEnabled: Bool, for type: CaptureType) {
        switch type {
        case .video:
            showMouseClickVisualsInVideo = isEnabled
        case .gif:
            if gifMouseClicksUseVideoSettings {
                showMouseClickVisualsInVideo = isEnabled
            } else {
                showMouseClickVisualsInGif = isEnabled
            }
        case .screenshot:
            break
        }
    }

    var videoMouseClickColor: NSColor {
        get { NSColor(hexRGBString: videoMouseClickColorHex) ?? .white }
        set { videoMouseClickColorHex = newValue.hexRGBString }
    }

    var gifMouseClickColor: NSColor {
        get { NSColor(hexRGBString: gifMouseClickColorHex) ?? .white }
        set { gifMouseClickColorHex = newValue.hexRGBString }
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
            "gifFrameRate", "gifMaxWidth", "videoFrameRate", "showMouseClickVisualsInVideo", "showMouseClickVisualsInGif",
            "gifMouseClicksUseVideoSettings",
            "videoMouseClickColorHex", "videoMouseClickSize", "videoMouseClickStrokeWidth", "videoMouseClickOpacity", "videoMouseClickDuration",
            "gifMouseClickColorHex", "gifMouseClickSize", "gifMouseClickStrokeWidth", "gifMouseClickOpacity", "gifMouseClickDuration",
            "showTrimmer",
            "recordAudio", "recordMicrophone", "selectedMicrophoneID", "showScreenshotEditor", "showGifTrimmer",
            "saveImmediatelyScreenshot", "saveImmediatelyVideo", "saveImmediatelyGif",
            "showScreenshotCapturePicker", "showVideoCapturePicker", "showGifCapturePicker",
            "screenshotFormat", "screenshotScale", "jpegQuality",
            "videoCountdownEnabled", "videoCountdownDuration",
            "gifCountdownEnabled", "gifCountdownDuration",
            "screenshotCountdownEnabled", "screenshotCountdownDuration",
            "hasCompletedOnboarding", "alwaysCaptureMainDisplay", "showRegionIndicator",
            "includeTinyClipsInCapture",
            "screenshotHotKeyCode", "screenshotHotKeyModifiers",
            "videoHotKeyCode", "videoHotKeyModifiers",
            "gifHotKeyCode", "gifHotKeyModifiers",
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
