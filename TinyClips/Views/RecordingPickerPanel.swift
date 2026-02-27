import AppKit
import SwiftUI

// MARK: - Recording Mode

enum RecordingCaptureMode {
    case region
    case screen
    case window
}


// MARK: - Panel

class RecordingPickerPanel: NSPanel {
    private var onCapture: ((RecordingCaptureMode, Bool, Int) -> Void)?
    private var onCancel: (() -> Void)?

    convenience init(
        countdownEnabled: Bool,
        countdownDuration: Int,
        onCapture: @escaping (RecordingCaptureMode, Bool, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.onCapture = onCapture
        self.onCancel = onCancel
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView: RecordingPickerView(
            countdownEnabled: countdownEnabled,
            countdownDuration: countdownDuration,
            onCapture: { [weak self] mode, enabled, duration in
                self?.onCapture?(mode, enabled, duration)
                self?.onCapture = nil
                self?.onCancel = nil
            },
            onCancel: { [weak self] in
                self?.onCancel?()
                self?.onCapture = nil
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

// MARK: - View

private struct RecordingPickerView: View {
    @State private var countdownEnabled: Bool
    @State private var countdownDuration: Int

    let onCapture: (RecordingCaptureMode, Bool, Int) -> Void
    let onCancel: () -> Void

    init(
        countdownEnabled: Bool,
        countdownDuration: Int,
        onCapture: @escaping (RecordingCaptureMode, Bool, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _countdownEnabled = State(initialValue: countdownEnabled)
        _countdownDuration = State(initialValue: countdownDuration)
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    private var timerLabel: String {
        countdownEnabled ? "\(countdownDuration)s" : "Off"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { onCapture(.region, countdownEnabled, countdownDuration) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "viewfinder.rectangular")
                        .font(.system(size: 12))
                    Text("Region")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.blue.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Select a region to record")

            Button { onCapture(.screen, countdownEnabled, countdownDuration) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "display")
                        .font(.system(size: 12))
                    Text("Screen")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Record a full screen")

            Button { onCapture(.window, countdownEnabled, countdownDuration) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 12))
                    Text("Window")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Record a window")

            Divider()
                .frame(height: 20)
                .overlay(.white.opacity(0.2))

            Menu {
                Button("Off") {
                    countdownEnabled = false
                }
                Divider()
                ForEach([1, 2, 3, 5, 10], id: \.self) { seconds in
                    Button("\(seconds)s") {
                        countdownEnabled = true
                        countdownDuration = seconds
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 11))
                    Text(timerLabel)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Countdown timer before recording")

            Button { onCancel() } label: {
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