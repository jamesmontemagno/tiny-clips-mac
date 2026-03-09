import AppKit
import SwiftUI

class StopRecordingPanel: NSPanel {
    convenience init(captureManager: CaptureManager, onStop: @escaping () -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView: StopRecordingView(captureManager: captureManager, onStop: onStop))
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
}

private struct StopRecordingView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var captureManager: CaptureManager
    let onStop: () -> Void
    @State private var elapsed: TimeInterval = 0
    @State private var startDate = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)

            Text(formattedTime)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .font(.system(size: 13, weight: .medium))
                .accessibilityLabel("Elapsed recording time")
                .accessibilityValue(formattedTime)

            if captureManager.recordingMicrophoneEnabled {
                RecordingStatusIcon(
                    systemName: "mic.fill",
                    tint: captureManager.microphoneWarningMessage == nil ? .green : .yellow,
                    accessibilityLabel: "Microphone recording",
                    accessibilityValue: captureManager.microphoneWarningMessage ?? (captureManager.activeMicrophoneName ?? "Active")
                )
                .help(captureManager.microphoneWarningMessage ?? captureManager.activeMicrophoneName ?? "Microphone is being recorded.")
            }

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .background(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(".", modifiers: .command)
            .accessibilityLabel("Stop recording")
            .accessibilityHint("Stops the current recording.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
                }
        }
        .onReceive(timer) { _ in
            elapsed = Date().timeIntervalSince(startDate)
        }
    }

    private var formattedTime: String {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct RecordingStatusIcon: View {
    let systemName: String
    let tint: Color
    let accessibilityLabel: String
    let accessibilityValue: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
    }
}
