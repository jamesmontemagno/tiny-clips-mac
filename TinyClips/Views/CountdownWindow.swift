import AppKit
import SwiftUI

class CountdownWindow: NSPanel {
    private var completion: (() -> Void)?
    private var countdownTimer: Timer?
    private var remaining: Int

    init(duration: Int, completion: @escaping () -> Void) {
        self.remaining = duration
        self.completion = completion
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
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

        updateDisplay()
    }

    func show() {
        if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        orderFront(nil)
        startCountdown()
    }

    private func startCountdown() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.remaining -= 1
            if self.remaining <= 0 {
                timer.invalidate()
                self.orderOut(nil)
                self.completion?()
                self.completion = nil
            } else {
                self.updateDisplay()
            }
        }
    }

    private func updateDisplay() {
        let hostingView = NSHostingView(rootView: CountdownView(remaining: remaining))
        hostingView.frame = NSRect(x: 0, y: 0, width: 120, height: 120)
        self.contentView = hostingView
    }

    func cancel() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        completion = nil
        orderOut(nil)
    }
}

private struct CountdownView: View {
    let remaining: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.75))
                .frame(width: 100, height: 100)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.3), lineWidth: 2)
                }

            Text("\(remaining)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(width: 120, height: 120)
    }
}
