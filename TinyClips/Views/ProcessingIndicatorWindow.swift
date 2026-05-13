import SwiftUI

// MARK: - Processing Indicator Window

final class ProcessingIndicatorWindow: NSPanel {
    convenience init(message: String = "Processing…") {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        contentView = NSHostingView(rootView: ProcessingIndicatorView(message: message))
    }

    func show() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }) ?? NSScreen.main ?? NSScreen.screens.first

        if let screen = targetScreen {
            // Toast-style: bottom-center above the Dock
            setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - frame.width / 2,
                y: screen.visibleFrame.minY + 32
            ))
        }

        collectionBehavior.insert(.moveToActiveSpace)
        alphaValue = 0
        NSApp.activate()
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }
}

// MARK: - Processing Indicator View

private struct ProcessingIndicatorView: View {
    let message: String
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
                .tint(.white)

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background {
            Capsule(style: .continuous)
                .fill(Color(white: 0.1, opacity: 0.92))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
        .scaleEffect(appeared ? 1 : 0.88)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
