import SwiftUI

struct ShortcutsSettingsSection: View {
    @ObservedObject var settings: CaptureSettings

    var body: some View {
        Section("Global Keyboard Shortcuts") {
            Text("These shortcuts work system-wide, even when the menu is closed. At least one modifier key (⌃ ⌥ ⇧ ⌘) is required.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ShortcutRecorderField(
                // Configure for screenshot shortcut
            )
            .accessibilityLabel("Screenshot keyboard shortcut")

            ShortcutRecorderField(
                // Configure for video shortcut
            )
            .accessibilityLabel("Record Video keyboard shortcut")

            ShortcutRecorderField(
                // Configure for GIF shortcut
            )
            .accessibilityLabel("Record GIF keyboard shortcut")
        }

        Section("Fixed Shortcuts") {
            Text("The following shortcuts are fixed and cannot be changed.")
                .font(.caption2)
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
                .foregroundStyle(.secondary)
        }
    }
}
