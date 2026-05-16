import SwiftUI

// MARK: - Processing Indicator Window



final class ProcessingIndicatorWindow: NSPanel {
    private var hostingView: NSHostingView<ProcessingIndicatorView>!
    private var viewModel: ProcessingIndicatorViewModel

    convenience init(message: String = "Processing…", status: String? = nil, progress: Double? = nil) {
        let viewModel = ProcessingIndicatorViewModel(message: message, status: status, progress: progress)
        self.init(viewModel: viewModel)
    }

    init(viewModel: ProcessingIndicatorViewModel) {
        self.viewModel = viewModel
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
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
        let hostingView = NSHostingView(rootView: ProcessingIndicatorView(viewModel: viewModel))
        contentView = hostingView
        self.hostingView = hostingView
    }

    func updateStatus(_ status: String?) {
        viewModel.status = status
    }

    func updateProgress(_ progress: Double?) {
        viewModel.progress = progress
    }

    func updateMessage(_ message: String) {
        viewModel.message = message
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

        alphaValue = 0
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        orderFrontRegardless()
        displayIfNeeded()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }
}


// MARK: - Processing Indicator ViewModel

@MainActor
final class ProcessingIndicatorViewModel: ObservableObject {
    @Published var message: String
    @Published var status: String?
    @Published var progress: Double?

    init(message: String, status: String? = nil, progress: Double? = nil) {
        self.message = message
        self.status = status
        self.progress = progress
    }
}

// MARK: - Processing Indicator View

private struct ProcessingIndicatorView: View {
    @ObservedObject var viewModel: ProcessingIndicatorViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let progress = viewModel.progress {
                    ProgressView(value: progress)
                        .controlSize(.regular)
                        .tint(colorScheme == .dark ? .white : .blue)
                        .frame(width: 22)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(colorScheme == .dark ? .white : .blue)
                        .frame(width: 22)
                }

                Text(viewModel.message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
            }
            if let status = viewModel.status, !status.isEmpty {
                Text(status)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
            }
            if let progress = viewModel.progress {
                HStack(spacing: 6) {
                    ProgressView(value: progress)
                        .tint(colorScheme == .dark ? .white : .blue)
                        .frame(height: 6)
                        .scaleEffect(x: 1, y: 1.2, anchor: .center)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.top, 2)
                .padding(.leading, 32)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.93))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
                }
        }
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.status == nil ? viewModel.message : "\(viewModel.message), \(viewModel.status!)")
    }
}
