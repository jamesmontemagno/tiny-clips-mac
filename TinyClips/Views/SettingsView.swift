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
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.displayCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Form {
                switch selectedTab {
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
        .frame(width: 420, height: 340)
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
            Toggle("Copy to clipboard", isOn: $settings.copyToClipboard)
            Toggle("Show in Finder after save", isOn: $settings.showInFinder)
            Toggle("Show notification after save", isOn: $settings.showSaveNotifications)
        }

        Section("Advanced") {
            Toggle("Always capture main display", isOn: $settings.alwaysCaptureMainDisplay)
                .help("Skip the display picker when multiple monitors are connected")
            Button("Reset All Settings to Defaults…") {
                resetAllSettings()
            }
        }

    }

    // MARK: - Screenshot

    @ViewBuilder
    private var screenshotSection: some View {
        Section {
            Toggle("Open editor after capture", isOn: $settings.showScreenshotEditor)
                .onChange(of: settings.showScreenshotEditor) { _, isEnabled in
                    if !isEnabled {
                        settings.saveImmediatelyScreenshot = true
                    }
                }

            Toggle("Save immediately", isOn: $settings.saveImmediatelyScreenshot)
                .disabled(!settings.showScreenshotEditor)

            Picker("Default format:", selection: $settings.screenshotFormat) {
                ForEach(ImageFormat.allCases, id: \.rawValue) { format in
                    Text(format.label).tag(format.rawValue)
                }
            }

            if settings.imageFormat == .jpeg {
                HStack {
                    Text("JPEG quality:")
                    Slider(value: $settings.jpegQuality, in: 0.1...1.0, step: 0.05)
                    Text("\(Int(settings.jpegQuality * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Picker("Default scale:", selection: $settings.screenshotScale) {
                Text("100%").tag(100)
                Text("75%").tag(75)
                Text("50%").tag(50)
                Text("25%").tag(25)
            }
        }
    }

    // MARK: - Video

    @ViewBuilder
    private var videoSection: some View {
        Section {
            Picker("Frame rate:", selection: $settings.videoFrameRate) {
                Text("24 fps").tag(24)
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
            Toggle("Record system audio", isOn: $settings.recordAudio)
            Toggle("Record microphone", isOn: $settings.recordMicrophone)
            Toggle("Open trimmer after recording", isOn: $settings.showTrimmer)
                .onChange(of: settings.showTrimmer) { _, isEnabled in
                    if !isEnabled {
                        settings.saveImmediatelyVideo = true
                    }
                }
            Toggle("Save immediately", isOn: $settings.saveImmediatelyVideo)
                .disabled(!settings.showTrimmer)
        }

        Section("Countdown") {
            Toggle("Countdown before recording", isOn: $settings.videoCountdownEnabled)
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
            }
        }
        
        Section("Display") {
            Toggle("Show capture region during recording", isOn: $settings.showRegionIndicator)
        }
    }

    // MARK: - GIF

    @ViewBuilder
    private var gifSection: some View {
        Section {
            HStack {
                Text("Frame rate:")
                Slider(value: $settings.gifFrameRate, in: 5...30, step: 1)
                Text("\(Int(settings.gifFrameRate)) fps")
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
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
            Toggle("Open trimmer after recording", isOn: $settings.showGifTrimmer)
                .onChange(of: settings.showGifTrimmer) { _, isEnabled in
                    if !isEnabled {
                        settings.saveImmediatelyGif = true
                    }
                }
            Toggle("Save immediately", isOn: $settings.saveImmediatelyGif)
                .disabled(!settings.showGifTrimmer)
        }

        Section("Countdown") {
            Toggle("Countdown before recording", isOn: $settings.gifCountdownEnabled)
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
            }
        }
        
        Section("Display") {
            Toggle("Show capture region during recording", isOn: $settings.showRegionIndicator)
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
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TinyClips Pro")
                        .font(.headline)
                    Text(storeService.isPro
                         ? "You have Pro — thank you for your support!"
                         : "Unlock Clips Manager and more.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if storeService.isPro {
                    Label("Active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }
        }

        if !storeService.isPro {
            Section {
                if let product = storeService.proProduct {
                    Button("Upgrade to Pro — \(product.displayPrice)") {
                        Task { await storeService.purchase() }
                    }
                    .disabled(storeService.isPurchasing)
                } else if storeService.isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                } else {
                    Button("Upgrade to Pro") {}
                        .disabled(true)
                }

                Button("Restore Purchase") {
                    Task { await storeService.restore() }
                }
                .disabled(storeService.isPurchasing)

                if let error = storeService.purchaseError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }

        Section("Pro Features") {
            Label("Clips Manager — browse screenshots, videos & GIFs", systemImage: "photo.stack")
            Label("Grid and list views with thumbnail previews", systemImage: "square.grid.2x2")
            Label("Sort, filter, copy, share, and delete clips", systemImage: "arrow.up.arrow.down")
        }
        .foregroundStyle(storeService.isPro ? .primary : .secondary)
    }
}
#endif
