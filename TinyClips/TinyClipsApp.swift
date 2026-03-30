import SwiftUI
import ScreenCaptureKit
import Combine
#if APPSTORE
import StoreKit
#endif

@main
struct TinyClipsApp: App {
    @StateObject private var captureManager = CaptureManager()
    @ObservedObject private var sparkleController = SparkleController.shared

    init() {
        _ = SparkleController.shared
        NSApplication.shared.setActivationPolicy(CaptureSettings.shared.showInDock ? .regular : .accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(captureManager: captureManager, sparkleController: sparkleController)
        } label: {
            MenuBarLabelView(captureManager: captureManager)
        }

        Window("Clips Manager", id: "clips-manager") {
            clipsManagerRootView()
        }
        .defaultSize(width: 980, height: 540)

        Window("Tiny Clips Settings", id: "settings-window") {
            SettingsView()
        }
        .defaultSize(width: 720, height: 460)
    }
}

// MARK: - Menu Bar Content

private struct MenuBarContentView: View {
    @ObservedObject var captureManager: CaptureManager
    @ObservedObject var sparkleController: SparkleController
    @ObservedObject private var settings = CaptureSettings.shared
    @Environment(\.openWindow) private var openWindow
#if APPSTORE
    @Environment(\.requestReview) private var requestReview
    @AppStorage("appStoreClipCountForReview") private var appStoreClipCountForReview = 0
    @AppStorage("appStoreReviewRequested") private var appStoreReviewRequested = false
#endif

    var body: some View {
        if !captureManager.isRecording {
            Button("Screenshot…") {
                captureManager.takeScreenshot()
            }
            .keyboardShortcut(screenshotKey, modifiers: screenshotModifiers)
            .accessibilityHint("Starts screenshot capture.")

            Button("Record Video...") {
                captureManager.startVideoRecording()
            }
            .keyboardShortcut(videoKey, modifiers: videoModifiers)
            .accessibilityHint("Starts video recording.")

            Button("Record GIF...") {
                captureManager.startGifRecording()
            }
            .keyboardShortcut(gifKey, modifiers: gifModifiers)
            .accessibilityHint("Starts GIF recording.")

            Divider()
        } else {
            Button("Stop Recording") {
                captureManager.stopRecording()
            }
            .keyboardShortcut(".", modifiers: .command)
            .accessibilityHint("Stops the current recording.")

            Divider()
        }
#if !APPSTORE
        Button("Check for Updates\u{2026}") {
            // Open Settings first so Sparkle has a parent window for its update dialog.
            // Without a key window (which doesn't exist after the menu bar menu closes),
            // Sparkle cannot present its UI and shows "Update failed" instead.
            openWindow(id: "settings-window")
            bringSettingsWindowToFront()
            checkForUpdatesAfterSettingsWindowAppears()
        }
#endif
        Button("Clips Manager…") {
            openWindow(id: "clips-manager")
            bringClipsManagerWindowToFront()
        }

#if APPSTORE
        if appStoreClipCountForReview >= 25 && !appStoreReviewRequested {
            Button("Rate TinyClips…") {
                appStoreReviewRequested = true
                requestReview()
            }
        }
#endif

        Button("Guide…") {
            captureManager.showGuide()
        }

        Button("Settings…") {
            openWindow(id: "settings-window")
            bringSettingsWindowToFront()
        }
        .keyboardShortcut(",", modifiers: .command)
        .accessibilityHint("Opens TinyClips settings.")

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func checkForUpdatesAfterSettingsWindowAppears() {
        // Poll until the Settings window becomes key (or a 2 s timeout elapses) so
        // Sparkle has a valid parent window for its update dialog. A menu bar app has
        // no key window after the menu closes, which causes Sparkle to show "Update
        // failed" when checkForUpdates is called immediately.
        let start = Date()
        let timeout: TimeInterval = 2.0
        func tryCheck() {
            let settingsIsKey = NSApp.keyWindow.map { $0.identifier?.rawValue == "settings-window" || $0.title == "Tiny Clips Settings" } ?? false
            if settingsIsKey || Date().timeIntervalSince(start) >= timeout {
                sparkleController.checkForUpdates()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { tryCheck() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { tryCheck() }
    }

    private func bringSettingsWindowToFront() {
        DispatchQueue.main.async {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            if let settingsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings-window" || $0.title == "Tiny Clips Settings" }) {
                settingsWindow.makeKeyAndOrderFront(nil)
                settingsWindow.orderFrontRegardless()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            if let settingsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings-window" || $0.title == "Tiny Clips Settings" }) {
                settingsWindow.makeKeyAndOrderFront(nil)
                settingsWindow.orderFrontRegardless()
            }
        }
    }

    private func bringClipsManagerWindowToFront() {
        DispatchQueue.main.async {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            if let clipsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "clips-manager" || $0.title == "Clips Manager" }) {
                clipsWindow.makeKeyAndOrderFront(nil)
                clipsWindow.orderFrontRegardless()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            if let clipsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "clips-manager" || $0.title == "Clips Manager" }) {
                clipsWindow.makeKeyAndOrderFront(nil)
                clipsWindow.orderFrontRegardless()
            }
        }
    }

    // MARK: - Dynamic Shortcut Keys

    private var screenshotKey: KeyEquivalent {
        keyEquivalent(for: settings.screenshotHotKeyCode, fallback: "5")
    }

    private var screenshotModifiers: EventModifiers {
        HotKeyBinding(keyCode: settings.screenshotHotKeyCode, carbonModifiers: settings.screenshotHotKeyModifiers).swiftUIModifiers
    }

    private var videoKey: KeyEquivalent {
        keyEquivalent(for: settings.videoHotKeyCode, fallback: "6")
    }

    private var videoModifiers: EventModifiers {
        HotKeyBinding(keyCode: settings.videoHotKeyCode, carbonModifiers: settings.videoHotKeyModifiers).swiftUIModifiers
    }

    private var gifKey: KeyEquivalent {
        keyEquivalent(for: settings.gifHotKeyCode, fallback: "7")
    }

    private var gifModifiers: EventModifiers {
        HotKeyBinding(keyCode: settings.gifHotKeyCode, carbonModifiers: settings.gifHotKeyModifiers).swiftUIModifiers
    }

    private func keyEquivalent(for keyCode: Int, fallback: Character) -> KeyEquivalent {
        // Only use UCKeyTranslate result when it produces a single letter or digit —
        // this avoids passing multi-char strings (e.g. "Space", "Esc") or symbol
        // characters (e.g. "←") to SwiftUI's KeyEquivalent.
        guard let str = HotKeyBinding.keyCodeToDisplayString(keyCode),
              str.count == 1,
              let ch = str.lowercased().first,
              ch.isLetter || ch.isNumber else {
            return KeyEquivalent(fallback)
        }
        return KeyEquivalent(ch)
    }
}

private struct MenuBarLabelView: View {
    @ObservedObject var captureManager: CaptureManager

    var body: some View {
        Image(systemName: captureManager.isRecording ? "record.circle.fill" : "camera.viewfinder")
            .foregroundStyle(captureManager.isRecording ? .red : .primary)
    }
}

@MainActor
class CaptureManager: ObservableObject {
    @Published var isRecording = false {
        didSet {
            updateStopHotKeyRegistration()
        }
    }
    @Published var recordingMicrophoneEnabled = false
    @Published var activeMicrophoneName: String?
    @Published var microphoneLevel: Double = 0
    @Published var microphoneWarningMessage: String?

    private var videoRecorder: VideoRecorder?
    private var gifWriter: GifWriter?
    private var screenshotPickerPanel: CapturePickerPanel?
    private var screenshotPickerPosition: NSPoint?
    private var recordingPickerPanel: CapturePickerPanel?
    private var recordingPickerPosition: NSPoint?
    private var startPanel: StartRecordingPanel?
    private var stopPanel: StopRecordingPanel?
    private var regionIndicatorPanel: RegionIndicatorPanel?
    private var pendingRecordingRegion: CaptureRegion?
    private var pendingRecordingType: CaptureType?
    private var pendingRecordingCountdownEnabled: Bool = true
    private var pendingRecordingCountdownDuration: Int = 3
    private var activeRecordingRegion: CaptureRegion?
    private var recordPanelPosition: NSPoint?
    private var trimmerWindow: VideoTrimmerWindow?
    private var gifTrimmerWindow: GifTrimmerWindow?
    private var screenshotEditorWindow: ScreenshotEditorWindow?
    private var countdownWindow: CountdownWindow?
    private var onboardingWindow: OnboardingWizardWindow?
    private var guideWindow: GuideWindow?
    private var screenPickerWindow: ScreenPickerWindow?
    private let hotKeyManager = HotKeyManager()
    private var hotKeySettingsCancellable: AnyCancellable?

    init() {
        configureGlobalHotKeys()

        // Re-register capture hotkeys whenever shortcut settings change.
        hotKeySettingsCancellable = CaptureSettings.shared.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.configureGlobalHotKeys()
            }

        DispatchQueue.main.async { [weak self] in
            self?.showOnboardingIfNeeded()
        }
    }

    private func bringWindowToFront(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func configureGlobalHotKeys() {
        let settings = CaptureSettings.shared
        hotKeyManager.registerCaptureHotKeys(
            screenshotKeyCode: UInt32(settings.screenshotHotKeyCode),
            screenshotModifiers: UInt32(settings.screenshotHotKeyModifiers),
            onScreenshot: { [weak self] in
                guard let self, !self.isRecording else { return }
                self.takeScreenshot()
            },
            videoKeyCode: UInt32(settings.videoHotKeyCode),
            videoModifiers: UInt32(settings.videoHotKeyModifiers),
            onRecordVideo: { [weak self] in
                guard let self, !self.isRecording else { return }
                self.startVideoRecording()
            },
            gifKeyCode: UInt32(settings.gifHotKeyCode),
            gifModifiers: UInt32(settings.gifHotKeyModifiers),
            onRecordGif: { [weak self] in
                guard let self, !self.isRecording else { return }
                self.startGifRecording()
            }
        )

        updateStopHotKeyRegistration()
    }

    private func updateStopHotKeyRegistration() {
        if isRecording {
            hotKeyManager.registerStopHotKey { [weak self] in
                guard let self, self.isRecording else { return }
                self.stopRecording()
            }
        } else {
            hotKeyManager.unregisterStopHotKey()
        }
    }

    func takeScreenshot() {
        Task {
            await prepareForNewCaptureRequest()
            guard await PermissionManager.shared.checkPermission() else { return }
            let settings = CaptureSettings.shared
            if settings.shouldShowCapturePicker(for: .screenshot) {
                showScreenshotPicker()
            } else {
                await performScreenshotCapture(
                    mode: .region,
                    countdownEnabled: settings.screenshotCountdownEnabled,
                    countdownDuration: settings.screenshotCountdownDuration,
                    shouldReturnToPicker: false
                )
            }
        }
    }

    private func showScreenshotPicker() {
        if screenshotPickerPanel != nil {
            return
        }
        dismissRecordingPicker()
        let settings = CaptureSettings.shared
        let panel = CapturePickerPanel(
            captureType: .screenshot,
            countdownEnabled: settings.screenshotCountdownEnabled,
            countdownDuration: settings.screenshotCountdownDuration,
            onCapture: { [weak self] mode, countdownEnabled, countdownDuration in
                guard let self else { return }
                self.dismissScreenshotPicker()
                Task {
                    await self.performScreenshotCapture(
                        mode: mode,
                        countdownEnabled: countdownEnabled,
                        countdownDuration: countdownDuration,
                        shouldReturnToPicker: true
                    )
                }
            },
            onCancel: { [weak self] in
                self?.dismissScreenshotPicker()
            }
        )
        panel.show(at: screenshotPickerPosition)
        self.screenshotPickerPanel = panel
    }

    private func dismissScreenshotPicker() {
        if let panel = screenshotPickerPanel {
            screenshotPickerPosition = panel.frame.origin
        }
        screenshotPickerPanel?.dismiss()
        screenshotPickerPanel = nil
    }

    private func performScreenshotCapture(
        mode: CapturePickerMode,
        countdownEnabled: Bool,
        countdownDuration: Int,
        shouldReturnToPicker: Bool
    ) async {
        switch mode {
        case .region:
            guard let region = await RegionSelector.selectRegion() else {
                if shouldReturnToPicker {
                    showScreenshotPicker()
                }
                return
            }
            doScreenshotCapture(
                region: region,
                window: nil,
                countdownEnabled: countdownEnabled,
                countdownDuration: countdownDuration,
                shouldReturnToPickerAfterCapture: shouldReturnToPicker
            )

        case .screen:
            let needsPicker = NSScreen.screens.count > 1 && !CaptureSettings.shared.alwaysCaptureMainDisplay
            let screen: NSScreen?
            if needsPicker {
                screen = await pickScreen()
            } else {
                screen = screenUnderMouseCursor() ?? NSScreen.main
            }
            guard let screen, let region = CaptureRegion.fullScreen(for: screen) else {
                if shouldReturnToPicker {
                    showScreenshotPicker()
                }
                return
            }
            doScreenshotCapture(
                region: region,
                window: nil,
                countdownEnabled: countdownEnabled,
                countdownDuration: countdownDuration,
                shouldReturnToPickerAfterCapture: shouldReturnToPicker
            )

        case .window:
            guard let window = await WindowSelector.selectWindow() else {
                if shouldReturnToPicker {
                    showScreenshotPicker()
                }
                return
            }
            doScreenshotCapture(
                region: nil,
                window: window,
                countdownEnabled: countdownEnabled,
                countdownDuration: countdownDuration,
                shouldReturnToPickerAfterCapture: shouldReturnToPicker
            )
        }
    }

    private func doScreenshotCapture(
        region: CaptureRegion?,
        window: SCWindow?,
        countdownEnabled: Bool,
        countdownDuration: Int,
        shouldReturnToPickerAfterCapture: Bool
    ) {
        let doCapture = { [weak self] in
            guard let self else { return }
            self.dismissRegionIndicator()
            AccessibilityAnnouncementService.shared.announceCaptureStart(
                for: .screenshot,
                countdownCompleted: countdownEnabled
            )
            Task {
                do {
                    let settings = CaptureSettings.shared
                    let shouldSaveImmediately = !settings.showScreenshotEditor || settings.saveImmediatelyScreenshot
                    let outputURL: URL = shouldSaveImmediately
                        ? SaveService.shared.generateURL(for: .screenshot)
                        : self.temporaryURL(fileExtension: settings.imageFormat.rawValue)

                    let url: URL
                    if let window {
                        url = try await ScreenshotCapture.captureWindow(window, outputURL: outputURL)
                    } else if let region {
                        url = try await ScreenshotCapture.capture(region: region, outputURL: outputURL)
                    } else {
                        return
                    }

                    if settings.showScreenshotEditor {
                        if shouldSaveImmediately {
                            SaveService.shared.handleSavedFile(url: url, type: .screenshot)
                        }
                        self.showScreenshotEditor(for: url, deleteSourceOnCancel: !shouldSaveImmediately)
                    } else {
                        SaveService.shared.handleSavedFile(url: url, type: .screenshot)
                    }
                } catch {
                    SaveService.shared.showError("Screenshot failed: \(error.localizedDescription)")
                }
                if shouldReturnToPickerAfterCapture {
                    self.showScreenshotPicker()
                }
            }
        }
        if let region,
           countdownEnabled,
           CaptureSettings.shared.showRegionIndicator {
            let panel = RegionIndicatorPanel(region: region)
            panel.show()
            self.regionIndicatorPanel = panel
        }
        guard countdownEnabled else {
            doCapture()
            return
        }
        let window = CountdownWindow(duration: countdownDuration) {
            doCapture()
        }
        self.countdownWindow = window
        window.show()
    }

    func startVideoRecording() {
        Task {
            await prepareForNewCaptureRequest()
            guard await PermissionManager.shared.checkPermission() else { return }
            let settings = CaptureSettings.shared
            if settings.shouldShowCapturePicker(for: .video) {
                showRecordingPicker(for: .video)
            } else {
                await performRecordingSetup(
                    type: .video,
                    mode: .region,
                    countdownEnabled: settings.videoCountdownEnabled,
                    countdownDuration: settings.videoCountdownDuration,
                    shouldReturnToPicker: false
                )
            }
        }
    }

    private func beginVideoRecording(
        region: CaptureRegion,
        systemAudio: Bool,
        microphone: Bool,
        selectedMicrophoneID: String,
        countdownEnabled: Bool,
        countdownDuration: Int
    ) {
        let settings = CaptureSettings.shared

        let doRecord = { [weak self] in
            guard let self else { return }
            AccessibilityAnnouncementService.shared.announceCaptureStart(
                for: .video,
                countdownCompleted: countdownEnabled
            )
            Task {
                let shouldSaveImmediately = !settings.showTrimmer || settings.saveImmediatelyVideo
                let url = shouldSaveImmediately
                    ? SaveService.shared.generateURL(for: .video)
                    : self.temporaryURL(fileExtension: CaptureType.video.fileExtension)

                do {
                    let recorder = VideoRecorder()
                    recorder.onMicrophoneLevel = { [weak self] level in
                        DispatchQueue.main.async {
                            self?.microphoneLevel = level
                        }
                    }
                    recorder.onMicrophoneWarning = { [weak self] warning in
                        DispatchQueue.main.async {
                            self?.microphoneWarningMessage = warning
                        }
                    }
                    recorder.onMicrophoneDeviceName = { [weak self] name in
                        DispatchQueue.main.async {
                            self?.activeMicrophoneName = name.isEmpty ? nil : name
                        }
                    }
                    recorder.onMicrophoneError = { [weak self] message in
                        DispatchQueue.main.async {
                            self?.microphoneWarningMessage = message
                            SaveService.shared.showError("Microphone error: \(message)")
                        }
                    }
                    self.videoRecorder = recorder
                    self.activeRecordingRegion = region
                    self.isRecording = true
                    self.recordingMicrophoneEnabled = false
                    self.microphoneWarningMessage = nil
                    self.microphoneLevel = 0
                    self.activeMicrophoneName = nil

                    try await recorder.start(
                        region: region,
                        outputURL: url,
                        recordSystemAudio: systemAudio,
                        recordMicrophone: microphone,
                        selectedMicrophoneID: selectedMicrophoneID
                    )
                    self.recordingMicrophoneEnabled = recorder.isMicrophoneCaptureActive
                    self.showStopPanel()
                } catch {
                    self.resetRecordingAudioStatus()
                    self.isRecording = false
                    self.activeRecordingRegion = nil
                    self.dismissRegionIndicator()
                    SaveService.shared.showError("Video recording failed: \(error.localizedDescription)")
                }
            }
        }

        showCountdownThen(
            for: .video,
            countdownEnabled: countdownEnabled,
            countdownDuration: countdownDuration,
            action: doRecord
        )
    }

    func startGifRecording() {
        Task {
            await prepareForNewCaptureRequest()
            guard await PermissionManager.shared.checkPermission() else { return }
            let settings = CaptureSettings.shared
            if settings.shouldShowCapturePicker(for: .gif) {
                showRecordingPicker(for: .gif)
            } else {
                await performRecordingSetup(
                    type: .gif,
                    mode: .region,
                    countdownEnabled: settings.gifCountdownEnabled,
                    countdownDuration: settings.gifCountdownDuration,
                    shouldReturnToPicker: false
                )
            }
        }
    }

    private func beginGifRecording(region: CaptureRegion, countdownEnabled: Bool, countdownDuration: Int) {
        resetRecordingAudioStatus()
        let doRecord = { [weak self] in
            guard let self else { return }
            AccessibilityAnnouncementService.shared.announceCaptureStart(
                for: .gif,
                countdownCompleted: countdownEnabled
            )
            Task {
                do {
                    let writer = GifWriter()
                    self.gifWriter = writer
                    self.activeRecordingRegion = region
                    self.isRecording = true

                    try await writer.start(region: region)
                    self.showStopPanel()
                } catch {
                    self.isRecording = false
                    self.activeRecordingRegion = nil
                    self.dismissRegionIndicator()
                    SaveService.shared.showError("GIF recording failed: \(error.localizedDescription)")
                }
            }
        }

        showCountdownThen(
            for: .gif,
            countdownEnabled: countdownEnabled,
            countdownDuration: countdownDuration,
            action: doRecord
        )
    }

    func stopRecording() {
        Task {
            await stopRecordingFlow()
        }
    }

    private func stopRecordingFlow() async {
        let stoppedRecordingType: CaptureType?
        if videoRecorder != nil {
            stoppedRecordingType = .video
        } else if gifWriter != nil {
            stoppedRecordingType = .gif
        } else {
            stoppedRecordingType = nil
        }

        var savedVideoURL: URL?

        if let recorder = videoRecorder {
            do {
                savedVideoURL = try await recorder.stop()
            } catch {
                SaveService.shared.showError("Video save failed: \(error.localizedDescription)")
            }
            videoRecorder = nil
        }

        if let writer = gifWriter {
            let url = SaveService.shared.generateURL(for: .gif)
            do {
                let settings = CaptureSettings.shared
                let shouldSaveImmediately = !settings.showGifTrimmer || settings.saveImmediatelyGif

                if settings.showGifTrimmer {
                    let gifData = try await writer.stopAndReturnData()

                    if shouldSaveImmediately {
                        try GifWriter.writeGIF(
                            frames: gifData.frames,
                            frameDelay: gifData.frameDelay,
                            maxWidth: gifData.maxWidth,
                            to: url
                        )
                        SaveService.shared.handleSavedFile(url: url, type: .gif)
                    }

                    showGifTrimmer(gifData: gifData, outputURL: url)
                } else {
                    try await writer.stop(outputURL: url)
                    SaveService.shared.handleSavedFile(url: url, type: .gif)
                }
            } catch {
                SaveService.shared.showError("GIF save failed: \(error.localizedDescription)")
            }
            gifWriter = nil
        }

        isRecording = false
        activeRecordingRegion = nil
        dismissStopPanel()
        dismissRegionIndicator()
        resetRecordingAudioStatus()

        if let stoppedRecordingType {
            AccessibilityAnnouncementService.shared.announceRecordingStopped(for: stoppedRecordingType)
        }

        // Show editor windows AFTER all recording resources are released
        // and UI state is cleaned up, so AVPlayer doesn't contend with
        // AVAssetWriter for the same file.
        if let savedVideoURL {
            let settings = CaptureSettings.shared
            let shouldSaveImmediately = !settings.showTrimmer || settings.saveImmediatelyVideo

            if settings.showTrimmer {
                if shouldSaveImmediately {
                    SaveService.shared.handleSavedFile(url: savedVideoURL, type: .video)
                }

                showTrimmer(
                    for: savedVideoURL,
                    saveImmediately: shouldSaveImmediately
                )
            } else {
                SaveService.shared.handleSavedFile(url: savedVideoURL, type: .video)
            }
        }
    }

    private func prepareForNewCaptureRequest() async {
        dismissScreenshotPicker()
        dismissRecordingPicker()
        dismissStartPanel()
        countdownWindow?.cancel()
        countdownWindow = nil
        dismissRegionIndicator()

        pendingRecordingRegion = nil
        pendingRecordingType = nil

        if videoRecorder != nil || gifWriter != nil || isRecording {
            await stopRecordingFlow()
        } else {
            dismissStopPanel()
        }
    }

    private func showScreenshotEditor(for url: URL, deleteSourceOnCancel: Bool) {
        let window = ScreenshotEditorWindow(imageURL: url) { [weak self] resultURL in
            guard let self else { return }
            if let resultURL {
                SaveService.shared.handleSavedFile(url: resultURL, type: .screenshot)
            } else {
                if deleteSourceOnCancel {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            DispatchQueue.main.async {
                self.screenshotEditorWindow = nil
            }
        }
        self.screenshotEditorWindow = window
        DispatchQueue.main.async {
            self.bringWindowToFront(window)
        }
    }

    private func showTrimmer(for url: URL, saveImmediately: Bool) {
        let window = VideoTrimmerWindow(videoURL: url) { [weak self] resultURL in
            guard let self else { return }
            if let resultURL {
                if saveImmediately {
                    SaveService.shared.handleSavedFile(url: resultURL, type: .video)
                } else {
                    let finalURL = SaveService.shared.generateURL(for: .video)
                    try? FileManager.default.removeItem(at: finalURL)
                    do {
                        try FileManager.default.moveItem(at: resultURL, to: finalURL)
                        SaveService.shared.handleSavedFile(url: finalURL, type: .video)
                    } catch {
                        SaveService.shared.showError("Video save failed: \(error.localizedDescription)")
                    }
                }
            } else {
                if !saveImmediately {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            // Defer release so the window isn't deallocated mid-callback
            DispatchQueue.main.async {
                self.trimmerWindow = nil
            }
        }
        self.trimmerWindow = window
        // Defer showing to next run loop to avoid issues with menu tracking
        DispatchQueue.main.async {
            self.bringWindowToFront(window)
        }
    }

    private func showGifTrimmer(gifData: GifCaptureData, outputURL: URL) {
        let window = GifTrimmerWindow(gifData: gifData, outputURL: outputURL) { [weak self] resultURL in
            guard let self else { return }
            if let resultURL {
                SaveService.shared.handleSavedFile(url: resultURL, type: .gif)
            }
            DispatchQueue.main.async {
                self.gifTrimmerWindow = nil
            }
        }
        self.gifTrimmerWindow = window
        DispatchQueue.main.async {
            self.bringWindowToFront(window)
        }
    }

    private func showStartPanel() {
        let panel = StartRecordingPanel(
            onStart: { [weak self] systemAudio, mic, selectedMicrophoneID in
                guard
                    let self,
                    let region = self.pendingRecordingRegion,
                    let type = self.pendingRecordingType
                else { return }

                let countdownEnabled = self.pendingRecordingCountdownEnabled
                let countdownDuration = self.pendingRecordingCountdownDuration

                self.pendingRecordingRegion = nil
                self.pendingRecordingType = nil
                self.dismissStartPanel()

                switch type {
                case .video:
                    self.beginVideoRecording(
                        region: region,
                        systemAudio: systemAudio,
                        microphone: mic,
                        selectedMicrophoneID: selectedMicrophoneID,
                        countdownEnabled: countdownEnabled,
                        countdownDuration: countdownDuration
                    )
                case .gif:
                    self.beginGifRecording(
                        region: region,
                        countdownEnabled: countdownEnabled,
                        countdownDuration: countdownDuration
                    )
                case .screenshot:
                    break
                }
            },
            onCancel: { [weak self] in
                self?.pendingRecordingRegion = nil
                self?.pendingRecordingType = nil
                self?.dismissStartPanel()
                self?.dismissRegionIndicator()
            }
        )
        panel.show()
        self.startPanel = panel
    }

    private func dismissStartPanel() {
        // Save the panel position before dismissing
        if let panel = startPanel {
            recordPanelPosition = panel.frame.origin
        }
        startPanel?.dismiss()
        startPanel = nil
    }

    private func showStopPanel() {
        let panel = StopRecordingPanel(captureManager: self) { [weak self] in
            self?.stopRecording()
        }
        panel.show(at: recordPanelPosition)
        self.stopPanel = panel
    }

    private func dismissStopPanel() {
        stopPanel?.close()
        stopPanel = nil
        recordPanelPosition = nil
    }

    private func dismissRegionIndicator() {
        regionIndicatorPanel?.close()
        regionIndicatorPanel = nil
    }

    private func resetRecordingAudioStatus() {
        recordingMicrophoneEnabled = false
        activeMicrophoneName = nil
        microphoneLevel = 0
        microphoneWarningMessage = nil
    }

    private func showCountdownThen(
        for type: CaptureType,
        countdownEnabled: Bool? = nil,
        countdownDuration: Int? = nil,
        action: @escaping () -> Void
    ) {
        let settings = CaptureSettings.shared
        let defaultEnabled: Bool
        let defaultDuration: Int

        switch type {
        case .video:
            defaultEnabled = settings.videoCountdownEnabled
            defaultDuration = settings.videoCountdownDuration
        case .gif:
            defaultEnabled = settings.gifCountdownEnabled
            defaultDuration = settings.gifCountdownDuration
        case .screenshot:
            defaultEnabled = settings.screenshotCountdownEnabled
            defaultDuration = settings.screenshotCountdownDuration
        }

        let enabled = countdownEnabled ?? defaultEnabled
        let duration = countdownDuration ?? defaultDuration

        guard enabled else {
            action()
            return
        }
        let window = CountdownWindow(duration: duration) {
            action()
        }
        self.countdownWindow = window
        window.show()
    }

    private func showOnboardingIfNeeded() {
        let settings = CaptureSettings.shared
        guard !settings.hasCompletedOnboarding, onboardingWindow == nil else { return }

        let window = OnboardingWizardWindow { [weak self] completed in
            if completed {
                settings.hasCompletedOnboarding = true
            }
            DispatchQueue.main.async {
                self?.onboardingWindow = nil
            }
        }
        onboardingWindow = window

        DispatchQueue.main.async {
            self.bringWindowToFront(window)
        }
    }

    func showGuide() {
        if let guideWindow {
            DispatchQueue.main.async {
                self.bringWindowToFront(guideWindow)
            }
            return
        }

        let window = GuideWindow(onDismiss: { [weak self] in
            DispatchQueue.main.async {
                self?.guideWindow = nil
            }
        })

        self.guideWindow = window
        DispatchQueue.main.async {
            self.bringWindowToFront(window)
        }
    }

    private func showRecordingPicker(for type: CaptureType) {
        dismissScreenshotPicker()
        dismissRecordingPicker()

        let settings = CaptureSettings.shared
        let countdownEnabled: Bool
        let countdownDuration: Int

        switch type {
        case .video:
            countdownEnabled = settings.videoCountdownEnabled
            countdownDuration = settings.videoCountdownDuration
        case .gif:
            countdownEnabled = settings.gifCountdownEnabled
            countdownDuration = settings.gifCountdownDuration
        case .screenshot:
            countdownEnabled = settings.screenshotCountdownEnabled
            countdownDuration = settings.screenshotCountdownDuration
        }

        let panel = CapturePickerPanel(
            captureType: type,
            countdownEnabled: countdownEnabled,
            countdownDuration: countdownDuration,
            onCapture: { [weak self] mode, enabled, duration in
                guard let self else { return }
                self.dismissRecordingPicker()
                Task {
                    await self.performRecordingSetup(
                        type: type,
                        mode: mode,
                        countdownEnabled: enabled,
                        countdownDuration: duration,
                        shouldReturnToPicker: true
                    )
                }
            },
            onCancel: { [weak self] in
                self?.dismissRecordingPicker()
            }
        )
        panel.show(at: recordingPickerPosition)
        self.recordingPickerPanel = panel
    }

    private func dismissRecordingPicker() {
        if let panel = recordingPickerPanel {
            recordingPickerPosition = panel.frame.origin
        }
        recordingPickerPanel?.dismiss()
        recordingPickerPanel = nil
    }

    private func performRecordingSetup(
        type: CaptureType,
        mode: CapturePickerMode,
        countdownEnabled: Bool,
        countdownDuration: Int,
        shouldReturnToPicker: Bool
    ) async {
        guard let region = await chooseCaptureRegion(for: mode) else {
            if shouldReturnToPicker {
                showRecordingPicker(for: type)
            }
            return
        }

        pendingRecordingRegion = region
        pendingRecordingType = type
        pendingRecordingCountdownEnabled = countdownEnabled
        pendingRecordingCountdownDuration = countdownDuration

        dismissRegionIndicator()

        if mode == .region, CaptureSettings.shared.showRegionIndicator {
            let panel = RegionIndicatorPanel(region: region)
            panel.show()
            regionIndicatorPanel = panel
        }

        showStartPanel()
    }

    private func chooseCaptureRegion(for mode: CapturePickerMode) async -> CaptureRegion? {
        switch mode {
        case .region:
            return await RegionSelector.selectRegion()
        case .screen:
            let needsPicker = NSScreen.screens.count > 1 && !CaptureSettings.shared.alwaysCaptureMainDisplay
            let screen: NSScreen?
            if needsPicker {
                screen = await pickScreen()
            } else {
                screen = screenUnderMouseCursor() ?? NSScreen.main
            }
            guard let screen else { return nil }
            return CaptureRegion.fullScreen(for: screen)
        case .window:
            guard let window = await WindowSelector.selectWindow() else { return nil }
            return captureRegion(for: window)
        }
    }

    private func captureRegion(for window: SCWindow) -> CaptureRegion? {
        let windowRect = appKitRect(fromSCFrame: window.frame)
        let windowCenter = NSPoint(x: windowRect.midX, y: windowRect.midY)

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(windowCenter) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(windowRect) })
        else {
            return nil
        }

        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }

        let localX = windowRect.minX - screen.frame.minX
        let localY = screen.frame.maxY - windowRect.maxY

        return CaptureRegion(
            sourceRect: CGRect(x: localX, y: localY, width: windowRect.width, height: windowRect.height),
            displayID: displayID,
            scaleFactor: screen.backingScaleFactor
        )
    }

    private func appKitRect(fromSCFrame scFrame: CGRect) -> CGRect {
        let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: scFrame.origin.x,
            y: primaryScreenTop - scFrame.maxY,
            width: scFrame.width,
            height: scFrame.height
        )
    }

    private func pickScreen() async -> NSScreen? {
        let screen = await withCheckedContinuation { (continuation: CheckedContinuation<NSScreen?, Never>) in
            let picker = ScreenPickerWindow { screen in
                continuation.resume(returning: screen)
            }
            self.screenPickerWindow = picker
            picker.show()
        }
        DispatchQueue.main.async {
            self.screenPickerWindow = nil
        }
        return screen
    }

    private func screenUnderMouseCursor() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    }

    private func temporaryURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TinyClips-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }
}
