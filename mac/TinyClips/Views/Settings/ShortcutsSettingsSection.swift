import SwiftUI

struct ShortcutsSettingsSection: View {
    @ObservedObject var settings: CaptureSettings

    var body: some View {
        Section("Global Keyboard Shortcuts") {
            Text("These shortcuts work system-wide, even when the menu is closed. At least one modifier key (⌃ ⌥ ⇧ ⌘) is required.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ShortcutRecorderField(
                label: "Screenshot",
                keyCode: $settings.screenshotHotKeyCode,
                carbonModifiers: $settings.screenshotHotKeyModifiers,
                defaultBinding: .defaultScreenshot
            )
            .accessibilityLabel("Screenshot keyboard shortcut")

            ShortcutRecorderField(
                label: "Record Video",
                keyCode: $settings.videoHotKeyCode,
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
}
