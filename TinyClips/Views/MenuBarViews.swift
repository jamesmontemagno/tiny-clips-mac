import SwiftUI
#if APPSTORE
import StoreKit
#endif

// MARK: - Menu Bar Content

struct MenuBarContentView: View {
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

// MARK: - Menu Bar Label

struct MenuBarLabelView: View {
    @ObservedObject var captureManager: CaptureManager

    var body: some View {
        Image(systemName: captureManager.isRecording ? "record.circle.fill" : "camera.viewfinder")
            .foregroundStyle(captureManager.isRecording ? .red : .primary)
    }
}
