import SwiftUI

struct GifSettingsSection: View {
    @ObservedObject var settings: CaptureSettings
    let isPro: Bool
    let selectedTab: Binding<SettingsTab?>
    let gifMouseClickToggleBinding: Binding<Bool>
    let gifKeyboardOverlayToggleBinding: Binding<Bool>

    var body: some View {
        Section("Capture Settings") {
            Toggle("Show capture picker before recording", isOn: $settings.showGifCapturePicker)
                .help("When disabled, GIF recording goes straight to region selection.")

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
            VStack(alignment: .leading, spacing: 6) {
                if isPro {
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
                    Toggle(
                        settings.gifKeyboardOverlayUseVideoSettings
                            ? "Show keyboard keys in recording (mirrors Video)"
                            : "Show keyboard keys in recording",
                        isOn: gifKeyboardOverlayToggleBinding
                    )
                    .help(
                        settings.gifKeyboardOverlayUseVideoSettings
                            ? "Uses the Video keyboard overlay on/off setting for GIF recordings."
                            : "Shows pressed keys in a subtle overlay in saved GIF recordings."
                    )
                    .accessibilityHint(
                        settings.gifKeyboardOverlayUseVideoSettings
                            ? "When enabled, GIF recordings use the same keyboard overlay visibility setting as Video recordings."
                            : "When enabled, pressed keys are shown in saved GIF recordings."
                    )
                    .onChange(of: gifKeyboardOverlayToggleBinding.wrappedValue) { _, isEnabled in
                        guard isEnabled else { return }
                        requestKeyboardOverlayPermissionIfNeeded()
                    }
                    Button("Customize keyboard overlay…") {
                        selectedTab.wrappedValue = .keyboardOverlay
                    }
                    .buttonStyle(.link)
                } else {
#if APPSTORE
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
                    Toggle(isOn: .constant(false)) {
                        HStack(spacing: 8) {
                            Text(settings.gifKeyboardOverlayUseVideoSettings
                                ? "Show keyboard keys in recording (mirrors Video)"
                                : "Show keyboard keys in recording")
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(true)
                    .help("Requires TinyClips Pro.")
                    Button("Unlock with Pro…") {
                        selectedTab.wrappedValue = .keyboardOverlay
                    }
                    .buttonStyle(.link)
#endif
                }
            }
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

    private func requestKeyboardOverlayPermissionIfNeeded() {
#if !APPSTORE
        let permissionManager = PermissionManager.shared
        if permissionManager.hasInputMonitoringPermission() {
            return
        }

        let granted = permissionManager.requestInputMonitoringPermission()
        if !granted {
            SaveService.shared.showError(
                "Keyboard overlay needs Input Monitoring to capture letters and numbers across apps. Enable TinyClips in System Settings > Privacy & Security > Input Monitoring, then relaunch the app."
            )
        }
#endif
    }
}
