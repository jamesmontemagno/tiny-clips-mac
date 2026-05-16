import SwiftUI

struct GifSettingsSection: View {
    @ObservedObject var settings: CaptureSettings
    @ObservedObject var storeService: StoreService?
    let selectedTab: Binding<SettingsTab?>
    let gifMouseClickToggleBinding: Binding<Bool>

    var body: some View {
        Section("Capture Settings") {
            Toggle("Show capture picker before recording", isOn: $settings.showGifCapturePicker)
            HStack {
                // Add GIF frame rate controls here
            }
            .help("Choose the frame rate for GIF recording.")
            HStack {
                // Add GIF output width controls here
            }
            .help("Limit GIF output width to reduce file size.")
            Toggle("Show capture region during recording", isOn: $settings.showRegionIndicator)
                .help("Show a visible border around the selected capture area while recording.")
            VStack(alignment: .leading, spacing: 6) {
#if APPSTORE
                if let storeService, storeService.isPro {
                    Toggle(
                        settings.gifMouseClicksUseVideoSettings
                            ? "Show mouse clicks in recording (mirrors Video)"
                            : "Show mouse clicks in recording",
                        isOn: gifMouseClickToggleBinding
                    )
                    .help(
                        settings.gifMouseClicksUseVideoSettings
                            ? "Uses the Video mouse click on/off setting for GIF recordings."
                            : "Adds a subtle pulse at click positions in saved GIF recordings."
                    )
                    .accessibilityHint(
                        settings.gifMouseClicksUseVideoSettings
                            ? "When enabled, GIF recordings use the same mouse click visibility setting as Video recordings."
                            : "When enabled, mouse clicks are shown as a pulse effect in saved GIF recordings."
                    )
                    Button("Customize mouse click effect…") {
                        selectedTab.wrappedValue = .mouseClicks
                    }
                    .buttonStyle(.link)
                } else {
                    Toggle(isOn: .constant(false)) {
                        HStack(spacing: 8) {
                            Text(settings.gifMouseClicksUseVideoSettings
                                ? "Show mouse clicks in recording (mirrors Video)"
                                : "Show mouse clicks in recording")
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(true)
                    .help("Requires TinyClips Pro.")
                    Button("Unlock with Pro…") {
                        selectedTab.wrappedValue = .mouseClicks
                    }
                    .buttonStyle(.link)
                }
#else
                Toggle(
                    settings.gifMouseClicksUseVideoSettings
                        ? "Show mouse clicks in recording (mirrors Video)"
                        : "Show mouse clicks in recording",
                    isOn: gifMouseClickToggleBinding
                )
                .help(
                    settings.gifMouseClicksUseVideoSettings
                        ? "Uses the Video mouse click on/off setting for GIF recordings."
                        : "Adds a subtle pulse at click positions in saved GIF recordings."
                )
                .accessibilityHint(
                    settings.gifMouseClicksUseVideoSettings
                        ? "When enabled, GIF recordings use the same mouse click visibility setting as Video recordings."
                        : "When enabled, mouse clicks are shown as a pulse effect in saved GIF recordings."
                )
                Button("Customize mouse click effect…") {
                    selectedTab.wrappedValue = .mouseClicks
                }
                .buttonStyle(.link)
#endif
            }
        }

        Section("After Capture") {
            Toggle("Open trimmer after recording", isOn: $settings.showGifTrimmer)
                .help("Open the trimmer when recording ends so you can trim before saving.")
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
                    // Add countdown duration picker/slider here if needed
                }
                .help("Set the countdown duration in seconds.")
            }
        }
    }
}
