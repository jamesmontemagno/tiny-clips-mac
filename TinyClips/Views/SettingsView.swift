import SwiftUI

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
    case pro = "Pro"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .screenshot: return "camera"
        case .video: return "video"
        case .gif: return "photo.on.rectangle"
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
    @State private var selectedTab: SettingsTab? = .general
    @State private var splitVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            List(SettingsTab.displayCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab as SettingsTab?)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Form {
                switch selectedTab ?? .general {
                case .general:
                    generalSection
                case .screenshot:
                    screenshotSection
                case .video:
                    videoSection
                case .gif:
                    gifSection
                case .pro:
                    proSection
                case .about:
                    aboutSection
                }
            }
            .formStyle(.grouped)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 720, height: 460)
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
            }
#endif
            VStack(alignment: .leading, spacing: 6) {
                TextField("File name template", text: $settings.fileNameTemplate)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Classic") {
                        settings.fileNameTemplate = "TinyClips {date} at {time}"
                    }
                    .buttonStyle(.link)

                    Button("Type + Date") {
                        settings.fileNameTemplate = "{type} {date} at {time}"
                    }
                    .buttonStyle(.link)

                    Button("Date First") {
                        settings.fileNameTemplate = "{date} {time} {type}"
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)

                Text("Tokens: {app}, {type}, {date}, {time}, {datetime}")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Preview: \(SaveService.shared.namingPreview(for: .screenshot))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Toggle("Show in Finder after save", isOn: $settings.showInFinder)
            Toggle("Show notification after save", isOn: $settings.showSaveNotifications)
        }

        Section("Advanced") {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            Toggle("Always capture main display", isOn: $settings.alwaysCaptureMainDisplay)
                .help("Skip the display picker when multiple monitors are connected")
            Toggle("Include TinyClips in captures", isOn: $settings.includeTinyClipsInCapture)
                .help("For developer/demo use. When enabled, TinyClips windows can appear in screenshots, recordings, and window selection.")
            Button("Reset All Settings to Defaults…") {
                resetAllSettings()
            }
        }

    }

    // MARK: - Screenshot

    @ViewBuilder
    private var screenshotSection: some View {
        Section("Capture Settings") {
            Picker("Default format:", selection: $settings.screenshotFormat) {
                ForEach(ImageFormat.allCases, id: \.rawValue) { format in
                    Text(format.label).tag(format.rawValue)
                }
            }
            .help("Choose the default file format for screenshots.")

            if settings.imageFormat == .jpeg {
                HStack {
                    Text("JPEG quality:")
                    Slider(value: $settings.jpegQuality, in: 0.1...1.0, step: 0.05)
                    Text("\(Int(settings.jpegQuality * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .help("Adjust JPEG compression quality. Higher values keep more detail but create larger files.")
            }

            Picker("Default scale:", selection: $settings.screenshotScale) {
                Text("100%").tag(100)
                Text("75%").tag(75)
                Text("50%").tag(50)
                Text("25%").tag(25)
            }
            .help("Resize the saved screenshot relative to captured pixels.")
        }

        Section("After Capture") {
            Toggle("Open editor after capture", isOn: $settings.showScreenshotEditor)
                .help("Open the screenshot editor after capture so you can annotate or crop.")
                .onChange(of: settings.showScreenshotEditor) { _, isEnabled in
                    if !isEnabled {
                        settings.saveImmediatelyScreenshot = true
                    }
                }

            Toggle("Save immediately", isOn: $settings.saveImmediatelyScreenshot)
                .help("Save immediately instead of waiting for actions in the editor.")
                .disabled(!settings.showScreenshotEditor)

            Toggle("Copy to clipboard", isOn: $settings.copyScreenshotToClipboard)
                .help("Copy saved screenshots to the clipboard as an image.")
        }

        Section("Countdown") {
            Toggle("Countdown before screenshot", isOn: $settings.screenshotCountdownEnabled)
                .help("Wait before capturing so you can prepare the screen.")
            if settings.screenshotCountdownEnabled {
                HStack {
                    Text("Duration:")
                    Slider(
                        value: $settings.screenshotCountdownDuration.doubleValue,
                        in: 1...10,
                        step: 1
                    )
                    Text("\(settings.screenshotCountdownDuration)s")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
                .help("Set the countdown duration in seconds.")
            }
        }
    }

    // MARK: - Video

    @ViewBuilder
    private var videoSection: some View {
        Section("Capture Settings") {
            Picker("Frame rate:", selection: $settings.videoFrameRate) {
                Text("24 fps").tag(24)
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
            .help("Choose the target frame rate for video recordings.")

            Toggle("Record system audio", isOn: $settings.recordAudio)
                .help("Include system audio in the recording.")
            Toggle("Record microphone", isOn: $settings.recordMicrophone)
                .help("Include microphone input in the recording.")
            Toggle("Show capture region during recording", isOn: $settings.showRegionIndicator)
                .help("Show a visible border around the selected capture area while recording.")
        }

        Section("After Capture") {
            Toggle("Open trimmer after recording", isOn: $settings.showTrimmer)
                .help("Open the trimmer when recording ends so you can trim before saving.")
                .onChange(of: settings.showTrimmer) { _, isEnabled in
                    if !isEnabled {
                        settings.saveImmediatelyVideo = true
                    }
                }
            Toggle("Save immediately", isOn: $settings.saveImmediatelyVideo)
                .help("Save immediately instead of waiting for actions in the trimmer.")
                .disabled(!settings.showTrimmer)
            Toggle("Copy to clipboard", isOn: $settings.copyVideoToClipboard)
                .help("Copy saved videos to the clipboard as a file URL.")
        }

        Section("Countdown") {
            Toggle("Countdown before recording", isOn: $settings.videoCountdownEnabled)
                .help("Wait before recording starts so you can prepare the screen.")
            if settings.videoCountdownEnabled {
                HStack {
                    Text("Duration:")
                    Slider(
                        value: $settings.videoCountdownDuration.doubleValue,
                        in: 1...10,
                        step: 1
                    )
                    Text("\(settings.videoCountdownDuration)s")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
                .help("Set the countdown duration in seconds.")
            }
        }
    }

    // MARK: - GIF

    @ViewBuilder
    private var gifSection: some View {
        Section("Capture Settings") {
            HStack {
                Text("Frame rate:")
                Slider(value: $settings.gifFrameRate, in: 5...30, step: 1)
                Text("\(Int(settings.gifFrameRate)) fps")
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
            .help("Choose the frame rate for GIF recording.")
            HStack {
                Text("Max width:")
                Slider(
                    value: Binding(
                        get: { Double(settings.gifMaxWidth) },
                        set: { settings.gifMaxWidth = Int($0) }
                    ),
                    in: 320...1920,
                    step: 40
                )
                Text("\(settings.gifMaxWidth)px")
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
            .help("Limit GIF output width to reduce file size.")
            Toggle("Show capture region during recording", isOn: $settings.showRegionIndicator)
                .help("Show a visible border around the selected capture area while recording.")
        }

        Section("After Capture") {
            Toggle("Open trimmer after recording", isOn: $settings.showGifTrimmer)
                .help("Open the trimmer when recording ends so you can trim before saving.")
                .onChange(of: settings.showGifTrimmer) { _, isEnabled in
                    if !isEnabled {
                        settings.saveImmediatelyGif = true
                    }
                }
            Toggle("Save immediately", isOn: $settings.saveImmediatelyGif)
                .help("Save immediately instead of waiting for actions in the trimmer.")
                .disabled(!settings.showGifTrimmer)
            Toggle("Copy to clipboard", isOn: $settings.copyGifToClipboard)
                .help("Copy saved GIFs to the clipboard as a file URL.")
        }

        Section("Countdown") {
            Toggle("Countdown before recording", isOn: $settings.gifCountdownEnabled)
                .help("Wait before recording starts so you can prepare the screen.")
            if settings.gifCountdownEnabled {
                HStack {
                    Text("Duration:")
                    Slider(
                        value: $settings.gifCountdownDuration.doubleValue,
                        in: 1...10,
                        step: 1
                    )
                    Text("\(settings.gifCountdownDuration)s")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
                .help("Set the countdown duration in seconds.")
            }
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
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }

        Section {
            Link("GitHub Repository", destination: URL(string: "https://github.com/jamesmontemagno/tiny-clips-mac")!)
            Link("Report an Issue", destination: URL(string: "https://github.com/jamesmontemagno/tiny-clips-mac/issues/new")!)
        }

#if !APPSTORE
        Section {
            Button("Check for Updates\u{2026}") {
                sparkleController.checkForUpdates()
            }
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
        }
    }
}

// MARK: - Pro Settings Section (APPSTORE only)

#if APPSTORE
private struct ProSettingsSection: View {
    @ObservedObject private var storeService = StoreService.shared

    var body: some View {
        if storeService.isPro {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TinyClips Pro")
                            .font(.headline)
                        if let plan = storeService.activeProPlan {
                            Text("Plan: \(plan.label) — thank you for your support!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Active — thank you for your support!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Label("Active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }

        } else {
            ProSubscriptionView()
        }
    }
}
#endif
