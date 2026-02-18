import AppKit
import SwiftUI

class ScreenPickerWindow: NSPanel {
    private var didComplete = false
    private var onComplete: ((NSScreen?) -> Void)?
    private var eventMonitor: Any?
    private var capturedScreens: [NSScreen] = []

    convenience init(onComplete: @escaping (NSScreen?) -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.onComplete = onComplete
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let screens = NSScreen.screens
        self.capturedScreens = screens
        let screenInfos = Self.buildScreenInfos(screens: screens, maxSize: CGSize(width: 480, height: 260))

        let hostingView = NSHostingView(rootView: ScreenPickerView(
            screens: screenInfos,
            onSelect: { [weak self] index in
                guard let self, index < self.capturedScreens.count else { return }
                let screen = self.capturedScreens[index]
                self.finish(with: screen)
            },
            onCancel: { [weak self] in
                self?.finish(with: nil)
            }
        ))
        let fittingSize = hostingView.fittingSize
        self.setContentSize(fittingSize)
        self.contentView = hostingView
    }

    func show() {
        if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.finish(with: nil)
                return nil
            }
            return event
        }
    }

    private func finish(with screen: NSScreen?) {
        guard !didComplete else { return }
        didComplete = true
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        orderOut(nil)
        onComplete?(screen)
        onComplete = nil
    }

    // MARK: - Build Screen Layout

    private static func buildScreenInfos(screens: [NSScreen], maxSize: CGSize) -> [ScreenInfo] {
        guard !screens.isEmpty else { return [] }

        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for screen in screens {
            minX = min(minX, screen.frame.minX)
            minY = min(minY, screen.frame.minY)
            maxX = max(maxX, screen.frame.maxX)
            maxY = max(maxY, screen.frame.maxY)
        }

        let totalWidth = maxX - minX
        let totalHeight = maxY - minY
        let gap: CGFloat = 4
        let gapCountX = CGFloat(screens.count - 1) // approximate gap allocation
        let scale = min((maxSize.width - gapCountX * gap) / totalWidth, maxSize.height / totalHeight)

        return screens.enumerated().map { index, screen in
            // Flip Y for SwiftUI (top-left origin)
            let scaledFrame = CGRect(
                x: (screen.frame.minX - minX) * scale,
                y: (maxY - screen.frame.maxY) * scale,
                width: screen.frame.width * scale - gap,
                height: screen.frame.height * scale - gap
            )

            return ScreenInfo(
                index: index,
                displayNumber: index + 1,
                resolution: "\(Int(screen.frame.width))×\(Int(screen.frame.height))",
                scaledFrame: scaledFrame,
                isMain: screen == NSScreen.main
            )
        }
    }
}

// MARK: - Screen Info

private struct ScreenInfo: Identifiable {
    let index: Int
    let displayNumber: Int
    let resolution: String
    let scaledFrame: CGRect
    let isMain: Bool

    var id: Int { index }
}

// MARK: - Screen Picker View

private struct ScreenPickerView: View {
    let screens: [ScreenInfo]
    let onSelect: (Int) -> Void
    let onCancel: () -> Void
    @State private var hoveredIndex: Int?

    private var arrangementSize: CGSize {
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for screen in screens {
            maxX = max(maxX, screen.scaledFrame.maxX)
            maxY = max(maxY, screen.scaledFrame.maxY)
        }
        return CGSize(width: maxX, height: maxY)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Display")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            ZStack(alignment: .topLeading) {
                // Invisible spacer to force ZStack to the full arrangement size
                Color.clear
                    .frame(width: arrangementSize.width, height: arrangementSize.height)

                ForEach(screens) { screen in
                    ScreenCard(info: screen, isHovered: hoveredIndex == screen.index)
                        .frame(width: screen.scaledFrame.width, height: screen.scaledFrame.height)
                        .offset(x: screen.scaledFrame.minX, y: screen.scaledFrame.minY)
                        .onHover { hovering in
                            hoveredIndex = hovering ? screen.index : nil
                        }
                        .onTapGesture {
                            onSelect(screen.index)
                        }
                }
            }

            Text("Click a display · Esc to cancel")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(24)
        .fixedSize()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.85))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Screen Card

private struct ScreenCard: View {
    let info: ScreenInfo
    let isHovered: Bool

    var body: some View {
        ZStack {
            Color.gray.opacity(0.2)

            VStack(spacing: 2) {
                Spacer()
                HStack(spacing: 4) {
                    Text("Display \(info.displayNumber)")
                        .font(.system(size: 11, weight: .semibold))
                    if info.isMain {
                        Text("Main")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(info.resolution)
                    .font(.system(size: 10))
                    .opacity(0.7)
            }
            .padding(.bottom, 6)
            .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isHovered ? Color.accentColor : .white.opacity(0.3),
                    lineWidth: isHovered ? 2 : 1
                )
        }
    }
}
