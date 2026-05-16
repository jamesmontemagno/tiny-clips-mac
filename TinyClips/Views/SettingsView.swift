import SwiftUI
import AppKit
import AVFoundation
import Combine

// MARK: - Binding Helpers

private extension Binding where Value == Int {
    var doubleValue: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = Int($0) }
        )
    }
}

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case screenshot = "Screenshot"
    case video = "Video"
    case gif = "GIF"
    case mouseClicks = "Mouse Clicks"
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
                if tab == .mouseClicks && !storeService.isPro {
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
                        sparkleController: sparkleController,
                        openWindow: openWindow,
                        showDisableDockWarning: $showDisableDockWarning,
                        chooseSaveDirectory: chooseSaveDirectory,
                        resetAllSettings: resetAllSettings,
                        showInDockBinding: showInDockBinding
                    )
                case .screenshot:
                    ScreenshotSettingsSection(settings: settings)
                case .video:
                    VideoSettingsSection(
                        settings: settings,
#if APPSTORE
                        storeService: storeService,
#else
                        storeService: nil,
#endif
                        selectedTab: $selectedTab
                    )
                case .gif:
                    GifSettingsSection(
                        settings: settings,
#if APPSTORE
                        storeService: storeService,
#else
                        storeService: nil,
#endif
                        selectedTab: $selectedTab,
                        gifMouseClickToggleBinding: gifMouseClickToggleBinding
                    )
                case .mouseClicks:
                    MouseClicksSettingsSection(
                        settings: settings,
#if APPSTORE
                        storeService: storeService
#else
                        storeService: nil
#endif
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
                        appBuild: appBuild,
                        distributionChannel: distributionChannel
                    )
                }
            }
            .formStyle(.grouped)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 460)
        .alert("Hide Dock icon?", isPresented: $showDisableDockWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Hide Dock Icon", role: .destructive) {
                settings.showInDock = false
                applyDockVisibility(false)
                reopenSettingsWindow()
            }
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
    }

    // MARK: - General

    @ViewBuilder
    private var generalSection: some View {
        Section("Output") {
#if APPSTORE
            VStack(alignment: .leading, spacing: 6) {
                Text("Default locations: Screenshots/GIFs → Pictures/TinyClips, Videos → Movies/TinyClips")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(settings.saveDirectoryDisplayPath.isEmpty ? "Using default folders" : settings.saveDirectoryDisplayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Browse…") {
                        chooseSaveDirectory()
                    }

                    if settings.hasCustomSaveDirectory {
                        Button("Reset") {
                            resetSaveDirectory()
                        }
                    }
                }
            }
#else
            HStack {
                TextField("Save to", text: $settings.saveDirectory)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") {
                    chooseSaveDirectory()
                }
            // Section views are now in separate files under Views/Settings/
                carbonModifiers: $settings.videoHotKeyModifiers,
                defaultBinding: .defaultVideo
            )
            .accessibilityLabel("Record Video keyboard shortcut")

            ShortcutRecorderField(
                label: "Record GIF",
                keyCode: $settings.gifHotKeyCode,
                carbonModifiers: $settings.gifHotKeyModifiers,
                defaultBinding: .defaultGif
            )
            .accessibilityLabel("Record GIF keyboard shortcut")
        }

        Section("Fixed Shortcuts") {
            Text("The following shortcuts are fixed and cannot be changed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            fixedShortcutRow(label: "Stop Recording", keys: "⌘.")
            fixedShortcutRow(label: "Settings", keys: "⌘,")
            fixedShortcutRow(label: "Quit", keys: "⌘Q")
        }
    }

    private func fixedShortcutRow(label: String, keys: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pro

    @ViewBuilder
    private var proSection: some View {
#if APPSTORE
        ProSettingsSection()
#endif
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(14)
                    }
                    Text("TinyClips")
                        .font(.headline)
                    Text("v\(appVersion) (\(appBuild))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }

        Section {
            Link("GitHub Repository", destination: URL(string: "https://github.com/jamesmontemagno/tiny-clips-mac")!)
                .accessibilityHint("Opens the TinyClips GitHub repository in your browser.")
            Link("Report an Issue", destination: reportIssueURL)
                .accessibilityHint("Opens the issue reporter in your browser.")
            if let privacyURL = URL(string: "https://tinyclips.app/privacy.html") {
                Link("Privacy Policy", destination: privacyURL)
                    .accessibilityHint("Opens Privacy Policy in your browser.")
            }
            if let termsURL = URL(string: "https://tinyclips.app/terms.html") {
                Link("Terms of Use", destination: termsURL)
                    .accessibilityHint("Opens Terms of Use in your browser.")
            }
        }

#if !APPSTORE
        Section {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { sparkleController.automaticallyChecksForUpdates },
                set: { sparkleController.automaticallyChecksForUpdates = $0 }
            ))
            .help("When enabled, TinyClips periodically checks for updates and Sparkle presents the standard update alert when one is available.")

            Button("Check for Updates\u{2026}") {
                sparkleController.checkForUpdates()
            }
            .help("Manually check for updates now.")
        }
#endif
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

    private var videoMouseClickColorBinding: Binding<NSColor> {
        Binding(
            get: { settings.videoMouseClickColor },
            set: { settings.videoMouseClickColor = $0 }
        )
    }

    private var gifMouseClickColorBinding: Binding<NSColor> {
        Binding(
            get: { settings.gifMouseClickColor },
            set: { settings.gifMouseClickColor = $0 }
        )
    }

    private var gifMouseClickToggleBinding: Binding<Bool> {
        Binding(
            get: { settings.shouldShowMouseClickVisuals(for: .gif) },
            set: { settings.setShowMouseClickVisuals($0, for: .gif) }
        )
    }
}

// MARK: - Pro Settings Section (APPSTORE only)

#if APPSTORE

