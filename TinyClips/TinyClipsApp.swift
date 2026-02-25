import SwiftUI
import ScreenCaptureKit

@main
struct TinyClipsApp: App {
    @StateObject private var captureManager = CaptureManager()
    @ObservedObject private var sparkleController = SparkleController.shared

    init() {
        _ = SparkleController.shared
    }

    var body: some Scene {
        MenuBarExtra("TinyClips", systemImage: captureManager.isRecording ? "record.circle.fill" : "camera.viewfinder") {
            MenuBarContentView(captureManager: captureManager, sparkleController: sparkleController)
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Menu Bar Content

private struct MenuBarContentView: View {
    @ObservedObject var captureManager: CaptureManager
    @ObservedObject var sparkleController: SparkleController
    @Environment(\.openSettings) private var openSettings
    @State private var isOptionPressed = false
    @State private var pollingTimer: Timer?

    var body: some View {
        if !captureManager.isRecording {
            Button("Screenshot…") {
                captureManager.takeScreenshot()
            }
            .keyboardShortcut("5", modifiers: [.control, .option, .command])

            Button(recordVideoTitle) {
                captureManager.startVideoRecording(useFullScreen: isOptionPressed)
            }
            .keyboardShortcut("6", modifiers: [.control, .option, .command])

            Button(recordGifTitle) {
                captureManager.startGifRecording(useFullScreen: isOptionPressed)
            }
            .keyboardShortcut("7", modifiers: [.control, .option, .command])

            Divider()
        } else {
            Button("Stop Recording") {
                captureManager.stopRecording()
            }
            .keyboardShortcut(".", modifiers: .command)

            Divider()
        }
#if !APPSTORE
        Button("Check for Updates\u{2026}") {
            sparkleController.checkForUpdates()
        }
#endif
        Button("Guide…") {
            captureManager.showGuide()
        }

        Button("Settings…") {
            openSettings()
            DispatchQueue.main.async {
                NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

                if let settingsWindow = NSApp.windows.first(where: {
                    $0.isVisible && $0.title.localizedCaseInsensitiveContains("settings")
                }) {
                    settingsWindow.collectionBehavior.insert(.moveToActiveSpace)
                    settingsWindow.makeKeyAndOrderFront(nil)
                    settingsWindow.orderFrontRegardless()
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

                if let settingsWindow = NSApp.windows.first(where: {
                    $0.isVisible && $0.title.localizedCaseInsensitiveContains("settings")
                }) {
                    settingsWindow.collectionBehavior.insert(.moveToActiveSpace)
                    settingsWindow.makeKeyAndOrderFront(nil)
                    settingsWindow.orderFrontRegardless()
                }
            }
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
        .onAppear {
            updateModifierState()
            let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
                DispatchQueue.main.async {
                    updateModifierState()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollingTimer = timer
        }
        .onDisappear {
            pollingTimer?.invalidate()
            pollingTimer = nil
        }
    }

    private var recordVideoTitle: String {
        isOptionPressed ? "Record Video (Full Screen)" : "Record Video"
    }

    private var recordGifTitle: String {
        isOptionPressed ? "Record GIF (Full Screen)" : "Record GIF"
    }

    private func updateModifierState() {
        let hasOption = NSEvent.modifierFlags.contains(.option)
        if hasOption != isOptionPressed {
            isOptionPressed = hasOption
        }
    }
}

@MainActor
class CaptureManager: ObservableObject {
    @Published var isRecording = false {
        didSet {
            updateStopHotKeyRegistration()
        }
    }

    private var videoRecorder: VideoRecorder?
    private var gifWriter: GifWriter?
    private var screenshotPickerPanel: ScreenshotPickerPanel?
    private var screenshotPickerPosition: NSPoint?
    private var startPanel: StartRecordingPanel?
    private var stopPanel: StopRecordingPanel?
    private var regionIndicatorPanel: RegionIndicatorPanel?
    private var pendingVideoRegion: CaptureRegion?
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

    init() {
        configureGlobalHotKeys()

        DispatchQueue.main.async { [weak self] in
            self?.showOnboardingIfNeeded()
        }
    }

    private func bringWindowToFront(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)

        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func configureGlobalHotKeys() {
        hotKeyManager.registerCaptureHotKeys(
            onScreenshot: { [weak self] in
                guard let self, !self.isRecording else { return }
                self.takeScreenshot()
            },
            onRecordVideo: { [weak self] in
                guard let self, !self.isRecording else { return }
                self.startVideoRecording()
            },
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

    func takeScreenshot(useFullScreen: Bool = false) {
        Task {
            guard await PermissionManager.shared.checkPermission() else { return }
            showScreenshotPicker()
        }
    }

    private func showScreenshotPicker() {
        guard screenshotPickerPanel == nil else { return }
        let panel = ScreenshotPickerPanel(
            onCapture: { [weak self] mode in
                guard let self else { return }
                self.dismissScreenshotPicker()
                Task {
                    await self.performScreenshotCapture(mode: mode)
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

    private func performScreenshotCapture(mode: ScreenshotMode) async {
        switch mode {
        case .region:
            guard let region = await RegionSelector.selectRegion() else {
                showScreenshotPicker()
                return
            }
            doScreenshotCapture(region: region, window: nil)

        case .screen:
            let needsPicker = NSScreen.screens.count > 1 && !CaptureSettings.shared.alwaysCaptureMainDisplay
            let screen: NSScreen?
            if needsPicker {
                screen = await pickScreen()
            } else {
                screen = screenUnderMouseCursor() ?? NSScreen.main
            }
            guard let screen, let region = CaptureRegion.fullScreen(for: screen) else {
                showScreenshotPicker()
                return
            }
            doScreenshotCapture(region: region, window: nil)

        case .window:
            guard let window = await WindowSelector.selectWindow() else {
                showScreenshotPicker()
                return
            }
            doScreenshotCapture(region: nil, window: window)
        }
    }

    private func doScreenshotCapture(region: CaptureRegion?, window: SCWindow?) {
        let doCapture = { [weak self] in
            guard let self else { return }
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
                self.showScreenshotPicker()
            }
        }
        showCountdownThen(for: .screenshot, action: doCapture)
    }

    func startVideoRecording(useFullScreen: Bool = false) {
        Task {
            guard await PermissionManager.shared.checkPermission() else { return }
            guard let region = await chooseCaptureRegion(useFullScreen: useFullScreen) else { return }

            self.pendingVideoRegion = region
            showStartPanel()
        }
    }

    private func beginVideoRecording(region: CaptureRegion, systemAudio: Bool, microphone: Bool) {
        let settings = CaptureSettings.shared
        settings.recordAudio = systemAudio
        settings.recordMicrophone = microphone

        let doRecord = { [weak self] in
            guard let self else { return }
            Task {
                let shouldSaveImmediately = !settings.showTrimmer || settings.saveImmediatelyVideo
                let url = shouldSaveImmediately
                    ? SaveService.shared.generateURL(for: .video)
                    : self.temporaryURL(fileExtension: CaptureType.video.fileExtension)

                do {
                    let recorder = VideoRecorder()
                    self.videoRecorder = recorder
                    self.activeRecordingRegion = region
                    self.isRecording = true

                    try await recorder.start(region: region, outputURL: url)
                    self.showStopPanel()
                    self.showRegionIndicator()
                } catch {
                    self.isRecording = false
                    self.activeRecordingRegion = nil
                    SaveService.shared.showError("Video recording failed: \(error.localizedDescription)")
                }
            }
        }

        showCountdownThen(for: .video, action: doRecord)
    }

    func startGifRecording(useFullScreen: Bool = false) {
        Task {
            guard await PermissionManager.shared.checkPermission() else { return }
            guard let region = await chooseCaptureRegion(useFullScreen: useFullScreen) else { return }

            let doRecord = { [weak self] in
                guard let self else { return }
                Task {
                    do {
                        let writer = GifWriter()
                        self.gifWriter = writer
                        self.activeRecordingRegion = region
                        self.isRecording = true

                        try await writer.start(region: region)
                        self.showStopPanel()
                        self.showRegionIndicator()
                    } catch {
                        self.isRecording = false
                        self.activeRecordingRegion = nil
                        SaveService.shared.showError("GIF recording failed: \(error.localizedDescription)")
                    }
                }
            }

            showCountdownThen(for: .gif, action: doRecord)
        }
    }

    func stopRecording() {
        Task {

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
            onStart: { [weak self] systemAudio, mic in
                guard let self, let region = self.pendingVideoRegion else { return }
                self.pendingVideoRegion = nil
                self.dismissStartPanel()
                self.beginVideoRecording(region: region, systemAudio: systemAudio, microphone: mic)
            },
            onCancel: { [weak self] in
                self?.pendingVideoRegion = nil
                self?.dismissStartPanel()
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
        let panel = StopRecordingPanel { [weak self] in
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

    private func showRegionIndicator() {
        guard CaptureSettings.shared.showRegionIndicator,
              let region = activeRecordingRegion else { return }
        
        let panel = RegionIndicatorPanel(region: region)
        panel.show()
        self.regionIndicatorPanel = panel
    }
    
    private func dismissRegionIndicator() {
        regionIndicatorPanel?.close()
        regionIndicatorPanel = nil
    }

    private func showCountdownThen(for type: CaptureType, action: @escaping () -> Void) {
        let settings = CaptureSettings.shared
        let enabled: Bool
        let duration: Int

        switch type {
        case .video:
            enabled = settings.videoCountdownEnabled
            duration = settings.videoCountdownDuration
        case .gif:
            enabled = settings.gifCountdownEnabled
            duration = settings.gifCountdownDuration
        case .screenshot:
            enabled = settings.screenshotCountdownEnabled
            duration = settings.screenshotCountdownDuration
        }

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

    private func chooseCaptureRegion(useFullScreen: Bool) async -> CaptureRegion? {
        if useFullScreen {
            let needsPicker = NSScreen.screens.count > 1 && !CaptureSettings.shared.alwaysCaptureMainDisplay
            let screen: NSScreen?
            if needsPicker {
                screen = await pickScreen()
            } else {
                screen = screenUnderMouseCursor() ?? NSScreen.main
            }
            guard let screen else { return nil }
            return CaptureRegion.fullScreen(for: screen)
        }

        // For region selection, show overlays on all screens —
        // the user drags on whichever screen they want.
        return await RegionSelector.selectRegion()
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
