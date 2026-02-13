import AppKit
import SwiftUI
import ImageIO

// MARK: - GIF Data passed from GifWriter

struct GifCaptureData {
    let frames: [CGImage]
    let frameDelay: Double
    let maxWidth: CGFloat
}

// MARK: - Window

class GifTrimmerWindow: NSWindow, NSWindowDelegate {
    private var onComplete: ((URL?) -> Void)?
    private var didComplete = false

    convenience init(gifData: GifCaptureData, outputURL: URL, onComplete: @escaping (URL?) -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.onComplete = onComplete
        self.title = "Trim GIF"
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.center()

        let trimmerView = GifTrimmerView(gifData: gifData, outputURL: outputURL) { [weak self] resultURL in
            self?.completeWith(resultURL)
        }
        self.contentView = NSHostingView(rootView: trimmerView)
    }

    private func completeWith(_ url: URL?) {
        guard !didComplete, let callback = onComplete else { return }
        didComplete = true
        onComplete = nil
        callback(url)
        orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        completeWith(nil)
        return true
    }
}

// MARK: - Trimmer View

private struct GifTrimmerView: View {
    let gifData: GifCaptureData
    let outputURL: URL
    let onDone: (URL?) -> Void

    @StateObject private var viewModel: GifTrimmerViewModel

    init(gifData: GifCaptureData, outputURL: URL, onDone: @escaping (URL?) -> Void) {
        self.gifData = gifData
        self.outputURL = outputURL
        self.onDone = onDone
        _viewModel = StateObject(wrappedValue: GifTrimmerViewModel(gifData: gifData))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Frame preview
            if let currentImage = viewModel.currentFrameImage {
                Image(nsImage: currentImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(minWidth: 400, minHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding([.top, .horizontal])
            } else {
                Color.clear
                    .frame(minWidth: 400, minHeight: 260)
                    .padding([.top, .horizontal])
            }

            // Frame counter
            HStack {
                Text("Frame \(viewModel.currentFrameIndex + 1) of \(viewModel.totalFrames)")
                    .monospacedDigit()
                Spacer()
                Text("\(String(format: "%.1f", Double(viewModel.totalFrames) * gifData.frameDelay))s total")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 6)

            // Trim range slider
            GifTrimSlider(
                trimStart: $viewModel.trimStartFrame,
                trimEnd: $viewModel.trimEndFrame,
                currentFrame: viewModel.currentFrameIndex,
                totalFrames: viewModel.totalFrames,
                onSeek: { frame in viewModel.seekTo(frame: frame) }
            )
            .frame(height: 44)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Trim info
            HStack {
                Label("Frame \(viewModel.trimStartFrame + 1)", systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                let trimmedCount = viewModel.trimEndFrame - viewModel.trimStartFrame + 1
                Text("\(trimmedCount) frames (\(String(format: "%.1f", Double(trimmedCount) * gifData.frameDelay))s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Frame \(viewModel.trimEndFrame + 1)", systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)

            Divider()
                .padding(.top, 10)

            // Action buttons
            HStack {
                Button(action: { viewModel.togglePlayback() }) {
                    Label("Preview", systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }

                Spacer()

                Button("Cancel") {
                    onDone(nil)
                }
                .keyboardShortcut(.cancelAction)

                Button("Save All Frames") {
                    if let url = viewModel.exportGif(to: outputURL, trimmed: false) {
                        onDone(url)
                    }
                }

                Button("Save Trimmed") {
                    if let url = viewModel.exportGif(to: outputURL, trimmed: true) {
                        onDone(url)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 580, height: 460)
    }
}

// MARK: - GIF Trim Slider

private struct GifTrimSlider: View {
    @Binding var trimStart: Int
    @Binding var trimEnd: Int
    let currentFrame: Int
    let totalFrames: Int
    let onSeek: (Int) -> Void

    @State private var dragStartValue: Int = 0
    @State private var dragEndValue: Int = 0
    @State private var draggingStart = false
    @State private var draggingEnd = false

    private let handleWidth: CGFloat = 12
    private let trackHeight: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - handleWidth * 2)
            let startX = totalFrames > 1 ? CGFloat(trimStart) / CGFloat(totalFrames - 1) * usable : 0
            let endX = totalFrames > 1 ? CGFloat(trimEnd) / CGFloat(totalFrames - 1) * usable : usable
            let playheadX = totalFrames > 1 ? handleWidth + CGFloat(currentFrame) / CGFloat(totalFrames - 1) * usable : handleWidth

            ZStack(alignment: .leading) {
                // Background track with frame ticks
                RoundedRectangle(cornerRadius: 4)
                    .fill(.primary.opacity(0.1))
                    .frame(height: trackHeight)

                // Active region
                RoundedRectangle(cornerRadius: 2)
                    .fill(.orange.opacity(0.25))
                    .frame(width: max(0, endX - startX + handleWidth * 2), height: trackHeight)
                    .offset(x: startX)

                // Frame tick marks (sparse for readability)
                let tickInterval = max(1, totalFrames / 30)
                ForEach(Array(stride(from: 0, to: totalFrames, by: tickInterval)), id: \.self) { i in
                    let tickX = totalFrames > 1 ? handleWidth + CGFloat(i) / CGFloat(totalFrames - 1) * usable : handleWidth
                    Rectangle()
                        .fill(.primary.opacity(0.15))
                        .frame(width: 1, height: trackHeight * 0.4)
                        .offset(x: tickX)
                }

                // Start handle
                trimHandle(color: .orange)
                    .offset(x: startX)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !draggingStart {
                                    draggingStart = true
                                    dragStartValue = trimStart
                                }
                                let delta = value.translation.width / usable * CGFloat(max(1, totalFrames - 1))
                                let newStart = max(0, min(Int(CGFloat(dragStartValue) + delta), trimEnd))
                                trimStart = newStart
                                onSeek(newStart)
                            }
                            .onEnded { _ in draggingStart = false }
                    )

                // End handle
                trimHandle(color: .orange)
                    .offset(x: endX + handleWidth)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !draggingEnd {
                                    draggingEnd = true
                                    dragEndValue = trimEnd
                                }
                                let delta = value.translation.width / usable * CGFloat(max(1, totalFrames - 1))
                                let newEnd = max(trimStart, min(Int(CGFloat(dragEndValue) + delta), totalFrames - 1))
                                trimEnd = newEnd
                                onSeek(newEnd)
                            }
                            .onEnded { _ in draggingEnd = false }
                    )

                // Playhead
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: trackHeight + 8)
                    .offset(x: playheadX - 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func trimHandle(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: handleWidth, height: trackHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.4))
                    .frame(width: 3, height: 14)
            }
            .cursor(.resizeLeftRight)
    }
}

// MARK: - ViewModel

private class GifTrimmerViewModel: ObservableObject {
    let gifData: GifCaptureData

    @Published var currentFrameIndex: Int = 0
    @Published var trimStartFrame: Int = 0
    @Published var trimEndFrame: Int = 0
    @Published var isPlaying = false

    var totalFrames: Int { gifData.frames.count }

    var currentFrameImage: NSImage? {
        guard currentFrameIndex >= 0, currentFrameIndex < gifData.frames.count else { return nil }
        let cg = gifData.frames[currentFrameIndex]
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private var playbackTimer: Timer?

    init(gifData: GifCaptureData) {
        self.gifData = gifData
        self.trimEndFrame = max(0, gifData.frames.count - 1)
    }

    func seekTo(frame: Int) {
        currentFrameIndex = max(0, min(frame, totalFrames - 1))
    }

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        isPlaying = true
        currentFrameIndex = trimStartFrame
        playbackTimer = Timer.scheduledTimer(withTimeInterval: gifData.frameDelay, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.currentFrameIndex >= self.trimEndFrame {
                    self.currentFrameIndex = self.trimStartFrame
                } else {
                    self.currentFrameIndex += 1
                }
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func exportGif(to url: URL, trimmed: Bool) -> URL? {
        stopPlayback()

        let frames: [CGImage]
        if trimmed {
            let start = max(0, trimStartFrame)
            let end = min(gifData.frames.count - 1, trimEndFrame)
            frames = Array(gifData.frames[start...end])
        } else {
            frames = gifData.frames
        }

        guard !frames.isEmpty else { return nil }

        // Downscale if needed
        let processedFrames: [CGImage]
        if CGFloat(frames[0].width) > gifData.maxWidth {
            let scale = gifData.maxWidth / CGFloat(frames[0].width)
            let newWidth = Int(gifData.maxWidth)
            let newHeight = Int(CGFloat(frames[0].height) * scale)
            let size = CGSize(width: newWidth, height: newHeight)
            processedFrames = frames.compactMap { downscale($0, to: size) }
        } else {
            processedFrames = frames
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "com.compuserve.gif" as CFString,
            processedFrames.count,
            nil
        ) else { return nil }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount: 0,
            ],
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        for frame in processedFrames {
            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime: gifData.frameDelay,
                ],
            ]
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }

    private func downscale(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}

// MARK: - Cursor modifier

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}
