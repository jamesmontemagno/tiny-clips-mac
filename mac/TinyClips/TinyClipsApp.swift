import SwiftUI

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

        ScreenshotEditorScene()
    }
}
