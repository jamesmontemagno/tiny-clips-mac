import SwiftUI

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

    var body: some View {
        if !captureManager.isRecording {
            Button("Screenshot") {
                captureManager.takeScreenshot()
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])

            Button("Record Video") {
                captureManager.startVideoRecording()
            }
            .keyboardShortcut("6", modifiers: [.command, .shift])

            Button("Record GIF") {
                captureManager.startGifRecording()
            }
            .keyboardShortcut("7", modifiers: [.command, .shift])

            Divider()
        } else {
            Button("Stop Recording") {
                captureManager.stopRecording()
            }
            .keyboardShortcut(".", modifiers: .command)

            Divider()
        }
        Button("Check for Updates\u{2026}") {
            sparkleController.checkForUpdates()
        }
        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

@MainActor
class CaptureManager: ObservableObject {
    @Published var isRecording = false

    private var videoRecorder: VideoRecorder?
    private var gifWriter: GifWriter?
    private var startPanel: StartRecordingPanel?
    private var stopPanel: StopRecordingPanel?
    private var pendingVideoRegion: CaptureRegion?
    private var trimmerWindow: VideoTrimmerWindow?
    private var gifTrimmerWindow: GifTrimmerWindow?
    private var screenshotEditorWindow: ScreenshotEditorWindow?
    private var countdownWindow: CountdownWindow?

    func takeScreenshot() {
        Task {
            guard PermissionManager.shared.checkPermission() else { return }
            guard let region = await RegionSelector.selectRegion() else { return }

            do {
                let url = try await ScreenshotCapture.capture(region: region)
                if CaptureSettings.shared.showScreenshotEditor {
                    showScreenshotEditor(for: url)
                } else {
                    SaveService.shared.handleSavedFile(url: url, type: .screenshot)
                }
            } catch {
                SaveService.shared.showError("Screenshot failed: \(error.localizedDescription)")
            }
        }
    }

    func startVideoRecording() {
        Task {
            guard PermissionManager.shared.checkPermission() else { return }
            guard let region = await RegionSelector.selectRegion() else { return }

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
                let url = SaveService.shared.generateURL(for: .video)

                do {
                    let recorder = VideoRecorder()
                    self.videoRecorder = recorder
                    self.isRecording = true

                    try await recorder.start(region: region, outputURL: url)
                    self.showStopPanel()
                } catch {
                    self.isRecording = false
                    SaveService.shared.showError("Video recording failed: \(error.localizedDescription)")
                }
            }
        }

        showCountdownThen(for: .video, action: doRecord)
    }

    func startGifRecording() {
        Task {
            guard PermissionManager.shared.checkPermission() else { return }
            guard let region = await RegionSelector.selectRegion() else { return }

            let doRecord = { [weak self] in
                guard let self else { return }
                Task {
                    do {
                        let writer = GifWriter()
                        self.gifWriter = writer
                        self.isRecording = true

                        try await writer.start(region: region)
                        self.showStopPanel()
                    } catch {
                        self.isRecording = false
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
                    if CaptureSettings.shared.showGifTrimmer {
                        let gifData = try await writer.stopAndReturnData()
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
            dismissStopPanel()

            // Show editor windows AFTER all recording resources are released
            // and UI state is cleaned up, so AVPlayer doesn't contend with
            // AVAssetWriter for the same file.
            if let savedVideoURL {
                if CaptureSettings.shared.showTrimmer {
                    showTrimmer(for: savedVideoURL)
                } else {
                    SaveService.shared.handleSavedFile(url: savedVideoURL, type: .video)
                }
            }
        }
    }

    private func showScreenshotEditor(for url: URL) {
        let window = ScreenshotEditorWindow(imageURL: url) { [weak self] resultURL in
            guard let self else { return }
            if let resultURL {
                SaveService.shared.handleSavedFile(url: resultURL, type: .screenshot)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            DispatchQueue.main.async {
                self.screenshotEditorWindow = nil
            }
        }
        self.screenshotEditorWindow = window
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    private func showTrimmer(for url: URL) {
        let window = VideoTrimmerWindow(videoURL: url) { [weak self] resultURL in
            guard let self else { return }
            if let resultURL {
                SaveService.shared.handleSavedFile(url: resultURL, type: .video)
            } else {
                // User cancelled — clean up the raw file
                try? FileManager.default.removeItem(at: url)
            }
            // Defer release so the window isn't deallocated mid-callback
            DispatchQueue.main.async {
                self.trimmerWindow = nil
            }
        }
        self.trimmerWindow = window
        // Defer showing to next run loop to avoid issues with menu tracking
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
        startPanel?.dismiss()
        startPanel = nil
    }

    private func showStopPanel() {
        let panel = StopRecordingPanel { [weak self] in
            self?.stopRecording()
        }
        panel.show()
        self.stopPanel = panel
    }

    private func dismissStopPanel() {
        stopPanel?.close()
        stopPanel = nil
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
        default:
            action()
            return
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
}
