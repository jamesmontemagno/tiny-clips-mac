import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case screenshot = "Screenshot"
    case video = "Video"
    case gif = "GIF"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .screenshot: return "camera"
        case .video: return "video"
        case .gif: return "photo.on.rectangle"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = CaptureSettings.shared
    @ObservedObject private var sparkleController = SparkleController.shared
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
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
        }

    }

    // MARK: - Screenshot

    @ViewBuilder
    private var screenshotSection: some View {
        Section {
            Toggle("Open editor after capture", isOn: $settings.showScreenshotEditor)

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
        }

        Section("Countdown") {
            Toggle("Countdown before recording", isOn: $settings.videoCountdownEnabled)
            if settings.videoCountdownEnabled {
                HStack {
                    Text("Duration:")
                    Slider(
                        value: Binding(
                            get: { Double(settings.videoCountdownDuration) },
                            set: { settings.videoCountdownDuration = Int($0) }
                        ),
                        in: 1...10,
                        step: 1
                    )
                    Text("\(settings.videoCountdownDuration)s")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
            }
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
        }

        Section("Countdown") {
            Toggle("Countdown before recording", isOn: $settings.gifCountdownEnabled)
            if settings.gifCountdownEnabled {
                HStack {
                    Text("Duration:")
                    Slider(
                        value: Binding(
                            get: { Double(settings.gifCountdownDuration) },
                            set: { settings.gifCountdownDuration = Int($0) }
                        ),
                        in: 1...10,
                        step: 1
                    )
                    Text("\(settings.gifCountdownDuration)s")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
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
}
