import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - ShortcutRecorderField

/// A SwiftUI row control that displays a keyboard shortcut and lets the user
/// record a new one by clicking "Record" and pressing any key combo.
struct ShortcutRecorderField: View {
    let label: String
    @Binding var keyCode: Int
    @Binding var carbonModifiers: Int
    let defaultBinding: HotKeyBinding

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    private var current: HotKeyBinding {
        HotKeyBinding(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    private var isCustom: Bool {
        current != defaultBinding
    }

    var body: some View {
        HStack {
            Text(label)

            Spacer()

            if isRecording {
                Text("Press shortcut…")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 110, alignment: .center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Waiting for shortcut input")

                Button("Cancel") {
                    stopRecording()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Cancels recording and keeps the current shortcut.")
            } else {
                Text(current.displayString)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 80, alignment: .center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Current shortcut: \(current.displayString)")

                Button("Record") {
                    startRecording()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Click to record a new keyboard shortcut.")

                if isCustom {
                    Button("Reset") {
                        keyCode = defaultBinding.keyCode
                        carbonModifiers = defaultBinding.carbonModifiers
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Resets this shortcut to its default value.")
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true

        // NOTE: ShortcutRecorderField is a struct (value type) — [self] captures a copy of the
        // view state, which is safe here. The monitor is always removed in stopRecording() which
        // is called both from the closure and from .onDisappear.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let code = Int(event.keyCode)

            // Escape cancels recording
            if code == kVK_Escape {
                stopRecording()
                return nil
            }

            // Ignore presses that are purely modifier keys (Command, Shift, Option, Control,
            // CapsLock, Function, and their right-hand counterparts: keyCodes 54–63).
            let modifierOnlyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            guard !modifierOnlyCodes.contains(code) else { return event }

            // Require at least one non-empty modifier combination
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !flags.isEmpty else {
                NSSound.beep()
                return nil
            }

            // Commit new shortcut
            keyCode = code
            carbonModifiers = HotKeyBinding.carbonModifiers(from: flags)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
