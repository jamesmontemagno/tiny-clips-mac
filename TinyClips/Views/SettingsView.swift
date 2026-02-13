import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = CaptureSettings.shared
    @ObservedObject private var sparkleController = SparkleController.shared

    var body: some View {
        Form {
            Section("Output") {
                HStack {
                    TextField("Save to", text: $settings.saveDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse…") {
                        chooseSaveDirectory()
                    }
                }
                Toggle("Copy to clipboard", isOn: $settings.copyToClipboard)
                Toggle("Show in Finder after save", isOn: $settings.showInFinder)
            }

            Section("GIF") {
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
            }

            Section("Video") {
                Picker("Frame rate:", selection: $settings.videoFrameRate) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                Toggle("Open trimmer after recording", isOn: $settings.showTrimmer)
            }

            if sparkleController.canCheckForUpdates {
                Section("Updates") {
                    Button("Check for Updates\u{2026}") {
                        sparkleController.checkForUpdates()
                    }
                }
            }

            Section("About") {
                HStack {
                    Text("TinyClips")
                    Spacer()
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .foregroundStyle(.secondary)
                }
                Link("GitHub Repository", destination: URL(string: "https://github.com/jamesmontemagno/tiny-clips-mac")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/jamesmontemagno/tiny-clips-mac/issues/new")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 400)
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url.path
        }
    }
}
