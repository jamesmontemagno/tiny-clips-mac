import AppKit
import SwiftUI

class StartRecordingPanel: NSPanel {
    private var onStart: ((Bool, String, Bool, String) -> Void)?
    private var onCancel: (() -> Void)?

    convenience init(onStart: @escaping (Bool, String, Bool, String) -> Void, onCancel: @escaping () -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.onStart = onStart
        self.onCancel = onCancel
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true

        let settings = CaptureSettings.shared
        let hostingView = NSHostingView(rootView: StartRecordingView(
            systemAudio: settings.recordAudio,
            microphone: settings.recordMicrophone,
            selectedOutputAudioDeviceUID: settings.selectedOutputAudioDeviceUID,
            selectedMicrophoneID: settings.selectedMicrophoneID,
            onStart: { [weak self] systemAudio, outputDeviceUID, mic in
                self?.onStart?(systemAudio, outputDeviceUID, mic.enabled, mic.deviceID)
                self?.onStart = nil
                self?.onCancel = nil
            },
            onCancel: { [weak self] in
                self?.onCancel?()
                self?.onStart = nil
                self?.onCancel = nil
            }
        ))
        let fittingSize = hostingView.fittingSize
        self.setContentSize(fittingSize)
        self.contentView = hostingView
    }

    func show(at position: NSPoint? = nil) {
        if let position {
            setFrameOrigin(position)
        } else if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.maxY - frame.height - 60
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        orderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
    }
}

private struct StartRecordingView: View {
    struct MicrophoneState {
        let enabled: Bool
        let deviceID: String
    }

    @State var systemAudio: Bool
    @State var microphone: Bool
    @State var selectedOutputAudioDeviceUID: String
    @State var selectedMicrophoneID: String
    @State private var outputDevices: [OutputAudioDeviceOption] = []
    private let microphones = MicrophoneDeviceCatalog.availableOptions()
    let onStart: (Bool, String, MicrophoneState) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // System audio toggle
            Button {
                systemAudio.toggle()
            } label: {
                Image(systemName: systemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(systemAudio ? .white : .white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .background(systemAudio ? .blue : .white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(systemAudio ? "Output audio: ON" : "Output audio: OFF")
            .accessibilityLabel("Output audio")
            .accessibilityValue(systemAudio ? "On" : "Off")
            .accessibilityHint("Toggles recording output audio.")

            if systemAudio {
                Picker("Output", selection: $selectedOutputAudioDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(outputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                .help("Choose output audio device for recording.")
                .accessibilityLabel("Output audio device")
                .accessibilityHint("Selects which output device to record from.")
            }

            // Microphone toggle
            Button {
                microphone.toggle()
            } label: {
                Image(systemName: microphone ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(microphone ? .white : .white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .background(microphone ? .blue : .white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(microphone ? "Microphone: ON" : "Microphone: OFF")
            .accessibilityLabel("Microphone")
            .accessibilityValue(microphone ? "On" : "Off")
            .accessibilityHint("Toggles microphone recording.")

            if microphone {
                Picker("Mic", selection: $selectedMicrophoneID) {
                    Text("System Default").tag("")
                    ForEach(microphones) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                .help("Choose microphone input device.")
            }

            Divider()
                .frame(height: 20)
                .overlay(.white.opacity(0.2))

            // Start button
            Button {
                onStart(systemAudio, selectedOutputAudioDeviceUID, .init(enabled: microphone, deviceID: selectedMicrophoneID))
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("Record")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.red.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Starts recording with the selected audio options.")

            // Cancel button
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Cancel")
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cancel recording setup")
            .accessibilityHint("Closes this panel without recording.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize()
        .onAppear {
            outputDevices = OutputAudioDeviceCatalog.availableOptions()
            guard !selectedOutputAudioDeviceUID.isEmpty else { return }
            if !outputDevices.contains(where: { $0.id == selectedOutputAudioDeviceUID }) {
                selectedOutputAudioDeviceUID = ""
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.8))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                }
        }
    }
}
