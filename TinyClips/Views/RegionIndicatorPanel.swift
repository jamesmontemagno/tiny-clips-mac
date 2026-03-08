import AppKit
import SwiftUI

class RegionIndicatorPanel: NSPanel {
    convenience init(region: CaptureRegion) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = true
        
        // Position the panel to match the capture region
        positionForRegion(region)
        
        let hostingView = NSHostingView(rootView: RegionIndicatorView(region: region))
        self.contentView = hostingView
    }
    
    private func positionForRegion(_ region: CaptureRegion) {
        // Find the screen that matches the region's display ID
        guard let screen = NSScreen.screens.first(where: {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == region.displayID
        }) else { return }
        
        // Convert from display-local coordinates (Y-down from top-left)
        // to screen coordinates (Y-up from bottom-left)
        let screenX = screen.frame.minX + region.sourceRect.minX
        let screenY = screen.frame.maxY - region.sourceRect.maxY
        
        let panelFrame = NSRect(
            x: screenX,
            y: screenY,
            width: region.sourceRect.width,
            height: region.sourceRect.height
        )
        
        setFrame(panelFrame, display: true)
    }
    
    func show() {
        orderFront(nil)
    }
}

private struct RegionIndicatorView: View {
    let region: CaptureRegion

    private var pointSizeText: String {
        "\(Int(region.sourceRect.width.rounded())) × \(Int(region.sourceRect.height.rounded())) pt"
    }

    private var pixelSizeText: String {
        let pixelWidth = Int((region.sourceRect.width * region.scaleFactor).rounded())
        let pixelHeight = Int((region.sourceRect.height * region.scaleFactor).rounded())
        return "\(pixelWidth) × \(pixelHeight) px"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(.red, lineWidth: 2)
                .background {
                    Rectangle()
                        .fill(.red.opacity(0.05))
                }

            Text("\(pointSizeText) • \(pixelSizeText)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.75), in: Capsule())
                .padding(8)
        }
    }
}
