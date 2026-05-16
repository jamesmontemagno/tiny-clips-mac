import SwiftUI

struct ScreenshotSettingsSection: View {
    @ObservedObject var settings: CaptureSettings

    var body: some View {
        Section("Capture Settings") {
            Toggle("Show capture picker before screenshot", isOn: $settings.showScreenshotCapturePicker)
                .help("When disabled, screenshots go straight to region selection.")

            Picker("Default format:", selection: $settings.screenshotFormat) {
                ForEach(ImageFormat.allCases, id: \.rawValue) { format in
                    Text(format.rawValue.capitalized).tag(format)
                }
            }
            .help("Choose the default file format for screenshots.")

            if settings.imageFormat == .jpeg {
                HStack {
                    // Add JPEG quality slider or picker here if needed
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
            Toggle("Save immediately", isOn: $settings.saveImmediatelyScreenshot)
                .help("Save immediately instead of waiting for actions in the editor.")
            Toggle("Copy to clipboard", isOn: $settings.copyScreenshotToClipboard)
        }

        Section("Countdown") {
            Toggle("Countdown before screenshot", isOn: $settings.screenshotCountdownEnabled)
                .help("Wait before capturing so you can prepare the screen.")
            if settings.screenshotCountdownEnabled {
                HStack {
                    // Add countdown duration picker/slider here if needed
                }
                .help("Set the countdown duration in seconds.")
            }
        }
    }
}
