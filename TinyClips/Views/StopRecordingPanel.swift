import AppKit
import SwiftUI

class StopRecordingPanel: NSPanel {
    convenience init(onStop: @escaping () -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
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

        let hostingView = NSHostingView(rootView: StopRecordingView(onStop: onStop))
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
}

private struct StopRecordingView: View {
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
                .foregroundStyle(.white)
                .font(.system(size: 13, weight: .medium))

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .background(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.8))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
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
