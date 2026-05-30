import AppKit
import SwiftUI

class StartRecordingPanel: NSPanel {
    private var onStart: ((Bool, Bool, String, Bool, Int) -> Void)?
    private var onCancel: (() -> Void)?

    convenience init(captureType: CaptureType, onStart: @escaping (Bool, Bool, String, Bool, Int) -> Void, onCancel: @escaping () -> Void) {
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
        let availableMicrophones = MicrophoneDeviceCatalog.availableOptions()
        let resolvedMicrophoneID: String = {
            let saved = settings.selectedMicrophoneID
            guard !saved.isEmpty, availableMicrophones.contains(where: { $0.id == saved }) else {
                if !saved.isEmpty {
                    settings.selectedMicrophoneID = ""
                }
                return ""
            }
            return saved
        }()
        let allowsMouseClickToggle: Bool
    #if APPSTORE
        allowsMouseClickToggle = StoreService.shared.isPro
        let defaultMouseClicksEnabled = allowsMouseClickToggle
            ? settings.shouldShowMouseClickVisuals(for: captureType)
            : false
    #else
        allowsMouseClickToggle = true
        let defaultMouseClicksEnabled = settings.shouldShowMouseClickVisuals(for: captureType)
    #endif
        let hostingView = NSHostingView(rootView: StartRecordingView(
            captureType: captureType,
            systemAudio: settings.recordAudio,
            microphone: settings.recordMicrophone,
            selectedMicrophoneID: resolvedMicrophoneID,
            availableMicrophones: availableMicrophones,
            mouseClicksEnabled: defaultMouseClicksEnabled,
            selectedVideoTimeLimitMinutes: settings.videoRecordingTimeLimitMinutes,
            allowsMouseClickToggle: allowsMouseClickToggle,
            onStart: { [weak self] systemAudio, mic, mouseClicksEnabled, videoTimeLimitMinutes in
                CaptureSettings.shared.videoRecordingTimeLimitMinutes = videoTimeLimitMinutes
                self?.onStart?(systemAudio, mic.enabled, mic.deviceID, mouseClicksEnabled, videoTimeLimitMinutes)
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
    @Environment(\.colorScheme) private var colorScheme
    private let clickLightURL = URL(string: "https://github.com/aurorascharff/ClickLight")!

    struct MicrophoneState {
        let enabled: Bool
        let deviceID: String
    }

    let captureType: CaptureType
    @State var systemAudio: Bool
    @State var microphone: Bool
    @State var selectedMicrophoneID: String
    let availableMicrophones: [MicrophoneDeviceOption]
    @State var mouseClicksEnabled: Bool
    @State var selectedVideoTimeLimitMinutes: Int
    let allowsMouseClickToggle: Bool
    let onStart: (Bool, MicrophoneState, Bool, Int) -> Void
    let onCancel: () -> Void

    private var videoTimeLimitLabel: String {
        selectedVideoTimeLimitMinutes == 0 ? "Unlimited" : "\(selectedVideoTimeLimitMinutes)m"
    }

    var body: some View {
        HStack(spacing: 8) {
            if captureType != .gif {
                // System audio toggle
                Button {
                    systemAudio.toggle()
                } label: {
                    Image(systemName: systemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(systemAudio ? .white : .primary.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(systemAudio ? .blue : .primary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(systemAudio ? "Output audio: ON" : "Output audio: OFF")
                .accessibilityLabel("Output audio")
                .accessibilityValue(systemAudio ? "On" : "Off")
                .accessibilityHint("Toggles recording output audio.")

                // Microphone toggle
                Button {
                    microphone.toggle()
                } label: {
                    Image(systemName: microphone ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(microphone ? .white : .primary.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(microphone ? .blue : .primary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(microphone ? "Microphone: ON" : "Microphone: OFF")
                .accessibilityLabel("Microphone")
                .accessibilityValue(microphone ? "On" : "Off")
                .accessibilityHint("Toggles microphone recording.")
            }

            if allowsMouseClickToggle {
                // Mouse click visuals toggle (Pro only)
                Button {
                    mouseClicksEnabled.toggle()
                } label: {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 13))
                        .foregroundStyle(mouseClicksEnabled ? .white : .primary.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(mouseClicksEnabled ? .blue : .primary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(mouseClicksEnabled ? "Mouse clicks in recording: ON" : "Mouse clicks in recording: OFF")
                .accessibilityLabel("Mouse click visuals")
                .accessibilityValue(mouseClicksEnabled ? "On" : "Off")
                .accessibilityHint("Toggles mouse click visuals for this recording.")

                Link("ClickLight", destination: clickLightURL)
                    .font(.system(size: 12, weight: .medium))
                    .help("For the best click event animations, install ClickLight.")
            }

            if microphone && captureType != .gif {
                Picker("Mic", selection: $selectedMicrophoneID) {
                    Text("System Default").tag("")
                    ForEach(availableMicrophones) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                .help("Choose microphone input device.")
            }

            if captureType == .video {
                Menu {
                    Button("Unlimited") {
                        selectedVideoTimeLimitMinutes = 0
                    }
                    Divider()
                    ForEach([1, 3, 5, 10, 15, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) minute\(minutes == 1 ? "" : "s")") {
                            selectedVideoTimeLimitMinutes = minutes
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 11))
                        Text(videoTimeLimitLabel)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Auto-stop recording time limit")
                .accessibilityLabel("Recording time limit")
                .accessibilityValue(videoTimeLimitLabel)
                .accessibilityHint("Choose when recording should automatically stop.")
            }

            Divider()
                .frame(height: 20)
                .overlay(.primary.opacity(0.2))

            // Start button
            Button {
                onStart(systemAudio, .init(enabled: microphone, deviceID: selectedMicrophoneID), mouseClicksEnabled, selectedVideoTimeLimitMinutes)
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
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(.primary.opacity(0.1))
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
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
                }
        }
    }
}
