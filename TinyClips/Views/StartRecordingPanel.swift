import AppKit
import SwiftUI

class StartRecordingPanel: NSPanel {
    private var onStart: ((Bool, Bool) -> Void)?
    private var onCancel: (() -> Void)?

    convenience init(onStart: @escaping (Bool, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 44),
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
            onStart: { [weak self] systemAudio, mic in
                self?.onStart?(systemAudio, mic)
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

    func show() {
        if let screen = NSScreen.main {
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
    @State var systemAudio: Bool
    @State var microphone: Bool
    let onStart: (Bool, Bool) -> Void
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
            .help(systemAudio ? "System audio: ON" : "System audio: OFF")

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

            Divider()
                .frame(height: 20)
                .overlay(.white.opacity(0.2))

            // Start button
            Button {
                onStart(systemAudio, microphone)
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize()
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
