import SwiftUI
import AppKit
import AVFoundation
import Combine

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case screenshot = "Screenshot"
    case video = "Video"
    case gif = "GIF"
    case mouseClicks = "Mouse Clicks"
    case keyboardOverlay = "Keyboard Overlay"
    case shortcuts = "Shortcuts"
    case pro = "Pro"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .screenshot: return "camera"
        case .video: return "video"
        case .gif: return "photo.on.rectangle"
        case .mouseClicks: return "cursorarrow.rays"
        case .keyboardOverlay: return "keyboard"
        case .shortcuts: return "command"
        case .pro: return "star"
        case .about: return "info.circle"
        }
    }

    static var displayCases: [SettingsTab] {
#if APPSTORE
        return allCases
#else
        return allCases.filter { $0 != .pro }
#endif
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = CaptureSettings.shared
    @ObservedObject private var sparkleController = SparkleController.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared
#if APPSTORE
    @ObservedObject private var storeService = StoreService.shared
#endif
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: SettingsTab? = .general
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State private var showDisableDockWarning = false
    @State private var availableMicrophones: [MicrophoneDeviceOption] = []

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            List(SettingsTab.displayCases, id: \.self, selection: $selectedTab) { tab in
#if APPSTORE
                if (tab == .mouseClicks || tab == .keyboardOverlay) && !storeService.isPro {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .badge("PRO")
                        .tag(tab as SettingsTab?)
                } else {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab as SettingsTab?)
                }
#else
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab as SettingsTab?)
#endif
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Form {
                switch selectedTab ?? .general {
                case .general:
                    GeneralSettingsSection(
                        settings: settings,
                        launchAtLogin: launchAtLogin,
                        chooseSaveDirectory: chooseSaveDirectory,
                        resetSaveDirectory: resetSaveDirectory,
                        resetAllSettings: resetAllSettings,
                        showInDockBinding: showInDockBinding
                    )
                case .screenshot:
                    ScreenshotSettingsSection(settings: settings)
                case .video:
                    VideoSettingsSection(
                        settings: settings,
                        availableMicrophones: availableMicrophones,
                        isPro: isAppStorePro,
                        selectedTab: $selectedTab
                    )
                case .gif:
                    GifSettingsSection(
                        settings: settings,
                        isPro: isAppStorePro,
                        selectedTab: $selectedTab,
                        gifMouseClickToggleBinding: gifMouseClickToggleBinding,
                        gifKeyboardOverlayToggleBinding: gifKeyboardOverlayToggleBinding
                    )
                case .mouseClicks:
                    MouseClicksSettingsSection(
                        settings: settings,
                        isPro: isAppStorePro
                    )
                case .keyboardOverlay:
                    KeyboardOverlaySettingsSection(
                        settings: settings,
                        isPro: isAppStorePro
                    )
                case .shortcuts:
                    ShortcutsSettingsSection(settings: settings)
                case .pro:
#if APPSTORE
                    ProSettingsSection()
#endif
                case .about:
                    AboutSettingsSection(
                        sparkleController: sparkleController,
                        reportIssueURL: reportIssueURL,
                        appVersion: appVersion,
                        appBuild: appBuild
                    )
                }
            }
            .formStyle(.grouped)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 460)
        .alert("Hide Dock icon?", isPresented: $showDisableDockWarning) {
            Button("Cancel", role: .cancel) {}
                .help("Keep TinyClips visible in the Dock.")
            Button("Hide Dock Icon", role: .destructive) {
                settings.showInDock = false
                applyDockVisibility(false)
                reopenSettingsWindow()
            }
            .help("Hide TinyClips from the Dock.")
        } message: {
            Text("TinyClips may briefly close the Settings window when switching out of Dock mode.")
        }
        .onAppear(perform: refreshMicrophones)
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            refreshMicrophones()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            refreshMicrophones()
        }
    }

    // MARK: - Helpers

    private func chooseSaveDirectory() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
#if APPSTORE
            panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
#endif
            guard panel.runModal() == .OK, let url = panel.url else { return }
#if APPSTORE
            do {
                let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                settings.saveDirectoryBookmark = bookmark
                settings.saveDirectoryDisplayPath = url.path
            } catch {
                SaveService.shared.showError("Could not save folder permission: \(error.localizedDescription)")
            }
#else
            settings.saveDirectory = url.path
#endif
        }
    }

#if APPSTORE
    private func resetSaveDirectory() {
        settings.saveDirectoryBookmark = Data()
        settings.saveDirectoryDisplayPath = ""
    }
#else
    private func resetSaveDirectory() {}
#endif

    private func resetAllSettings() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Reset all settings?"
            alert.informativeText = "This will restore TinyClips settings to defaults, including onboarding state."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Reset")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            settings.resetToDefaults()
            sparkleController.resetPreferencesToDefaults()
            applyDockVisibility(settings.showInDock)
        }
    }

    private func applyDockVisibility(_ showInDock: Bool) {
        NSApplication.shared.setActivationPolicy(showInDock ? .regular : .accessory)
        if showInDock {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        }
    }

    private var showInDockBinding: Binding<Bool> {
        Binding(
            get: { settings.showInDock },
            set: { isEnabled in
                if isEnabled {
                    settings.showInDock = true
                    applyDockVisibility(true)
                } else {
                    showDisableDockWarning = true
                }
            }
        )
    }

    private func reopenSettingsWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            openWindow(id: "settings-window")
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    private var distributionChannel: String {
#if APPSTORE
        return "Mac App Store"
#else
        return "Direct Download"
#endif
    }

    private var reportIssueURL: URL {
        var components = URLComponents(string: "https://github.com/jamesmontemagno/tiny-clips-mac/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "title", value: "[Bug]: "),
            URLQueryItem(name: "version", value: appVersion),
            URLQueryItem(name: "build", value: appBuild),
            URLQueryItem(name: "distribution", value: distributionChannel),
            URLQueryItem(name: "macos", value: ProcessInfo.processInfo.operatingSystemVersionString)
        ]
        return components.url!
    }

    private func refreshMicrophones() {
        availableMicrophones = MicrophoneDeviceCatalog.availableOptions()
        guard !settings.selectedMicrophoneID.isEmpty else { return }
        if availableMicrophones.contains(where: { $0.id == settings.selectedMicrophoneID }) {
            return
        }
        settings.selectedMicrophoneID = ""
    }

    private var gifMouseClickToggleBinding: Binding<Bool> {
        Binding(
            get: { settings.shouldShowMouseClickVisuals(for: .gif) },
            set: { settings.setShowMouseClickVisuals($0, for: .gif) }
        )
    }

    private var gifKeyboardOverlayToggleBinding: Binding<Bool> {
        Binding(
            get: { settings.shouldShowKeyboardOverlay(for: .gif) },
            set: { settings.setShowKeyboardOverlay($0, for: .gif) }
        )
    }

    private var isAppStorePro: Bool {
#if APPSTORE
        return storeService.isPro
#else
        return true
#endif
    }
}
