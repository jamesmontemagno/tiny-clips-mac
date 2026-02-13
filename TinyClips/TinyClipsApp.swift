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
            if sparkleController.canCheckForUpdates {
                Button("Check for Updates\u{2026}") {
                    sparkleController.checkForUpdates()
                }
            }
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
class CaptureManager: ObservableObject {
    @Published var isRecording = false

    private var videoRecorder: VideoRecorder?
    private var gifWriter: GifWriter?
    private var stopPanel: StopRecordingPanel?
    private var trimmerWindow: VideoTrimmerWindow?

    func takeScreenshot() {
        Task {
            guard PermissionManager.shared.checkPermission() else { return }
            guard let region = await RegionSelector.selectRegion() else { return }

            do {
                let url = try await ScreenshotCapture.capture(region: region)
                SaveService.shared.handleSavedFile(url: url, type: .screenshot)
            } catch {
                SaveService.shared.showError("Screenshot failed: \(error.localizedDescription)")
            }
        }
    }

    func startVideoRecording() {
        Task {
            guard PermissionManager.shared.checkPermission() else { return }
            guard let region = await RegionSelector.selectRegion() else { return }

            let url = SaveService.shared.generateURL(for: .video)

            do {
                let recorder = VideoRecorder()
                self.videoRecorder = recorder
                self.isRecording = true

                try await recorder.start(region: region, outputURL: url)
                showStopPanel()
            } catch {
                self.isRecording = false
                SaveService.shared.showError("Video recording failed: \(error.localizedDescription)")
            }
        }
    }

    func startGifRecording() {
        Task {
            guard PermissionManager.shared.checkPermission() else { return }
            guard let region = await RegionSelector.selectRegion() else { return }

            do {
                let writer = GifWriter()
                self.gifWriter = writer
                self.isRecording = true

                try await writer.start(region: region)
                showStopPanel()
            } catch {
                self.isRecording = false
                SaveService.shared.showError("GIF recording failed: \(error.localizedDescription)")
            }
        }
    }

    func stopRecording() {
        Task {
            if let recorder = videoRecorder {
                do {
                    let url = try await recorder.stop()
                    if CaptureSettings.shared.showTrimmer {
                        showTrimmer(for: url)
                    } else {
                        SaveService.shared.handleSavedFile(url: url, type: .video)
                    }
                } catch {
                    SaveService.shared.showError("Video save failed: \(error.localizedDescription)")
                }
                videoRecorder = nil
            }

            if let writer = gifWriter {
                let url = SaveService.shared.generateURL(for: .gif)
                do {
                    try await writer.stop(outputURL: url)
                    SaveService.shared.handleSavedFile(url: url, type: .gif)
                } catch {
                    SaveService.shared.showError("GIF save failed: \(error.localizedDescription)")
                }
                gifWriter = nil
            }

            isRecording = false
            dismissStopPanel()
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
}
