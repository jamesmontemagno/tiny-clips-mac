import AppKit
import SwiftUI
import AVFoundation
import AVKit
import ImageIO

class VideoTrimmerWindow: NSWindow, NSWindowDelegate {
    private var onComplete: ((URL?) -> Void)?
    private var didComplete = false

    convenience init(videoURL: URL, onComplete: @escaping (URL?) -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.onComplete = onComplete
        self.title = "Trim Video"
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.minSize = NSSize(width: 560, height: 420)
        self.center()

        let trimmerView = VideoTrimmerView(videoURL: videoURL) { [weak self] resultURL in
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

private struct VideoTrimmerView: View {
    let videoURL: URL
    let onDone: (URL?) -> Void

    @StateObject private var viewModel: TrimmerViewModel
    @State private var keyMonitor: Any?

    init(videoURL: URL, onDone: @escaping (URL?) -> Void) {
        self.videoURL = videoURL
        self.onDone = onDone
        _viewModel = StateObject(wrappedValue: TrimmerViewModel(url: videoURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video preview
            PlayerView(player: viewModel.player)
                .frame(minWidth: 400, minHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding([.top, .horizontal])
                .task { await viewModel.loadDuration() }

            // Current time display
            HStack {
                Text(formatTime(viewModel.currentTime))
                    .monospacedDigit()

                if viewModel.totalFrameCount > 1 {
                    Text("Frame \(viewModel.currentFrameNumber) of \(viewModel.totalFrameCount)")
                        .monospacedDigit()
                }

                Spacer()
                Text(formatTime(viewModel.duration))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 6)

            // Trim range control
            TrimRangeSlider(
                trimStart: $viewModel.trimStart,
                trimEnd: $viewModel.trimEnd,
                currentTime: viewModel.currentTime,
                duration: viewModel.duration,
                onSeek: { time in viewModel.seek(to: time) }
            )
            .frame(height: 44)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .accessibilityLabel("Trim range")
            .accessibilityHint("Adjust the start and end handles to choose the segment to save.")

            // Trim time labels
            HStack {
                Label(formatTime(viewModel.trimStart), systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                Text("Duration: \(formatTime(viewModel.trimmedOutputDuration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(formatTime(viewModel.trimEnd), systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)

            HStack(spacing: 12) {
                let maxStart = max(0, viewModel.trimEnd - 0.1)
                let minEnd = min(viewModel.duration, viewModel.trimStart + 0.1)

                Stepper(
                    value: Binding(
                        get: { viewModel.trimStart },
                        set: { newValue in
                            viewModel.trimStart = min(max(0, newValue), maxStart)
                            viewModel.seek(to: viewModel.trimStart)
                        }
                    ),
                    in: 0...maxStart,
                    step: 0.1
                ) {
                    Text("Start: \(formatTime(viewModel.trimStart))")
                        .monospacedDigit()
                }

                Stepper(
                    value: Binding(
                        get: { viewModel.trimEnd },
                        set: { newValue in
                            let clamped = min(max(minEnd, newValue), viewModel.duration)
                            viewModel.trimEnd = clamped
                            viewModel.seek(to: min(viewModel.currentTime, clamped))
                        }
                    ),
                    in: minEnd...max(minEnd, viewModel.duration),
                    step: 0.1
                ) {
                    Text("End: \(formatTime(viewModel.trimEnd))")
                        .monospacedDigit()
                }

                Text("Speed")
                    .foregroundStyle(.secondary)
                Picker("", selection: $viewModel.speed) {
                    ForEach(TrimmerViewModel.speedOptions, id: \.self) { speed in
                        Text(TrimmerViewModel.speedLabel(for: speed)).tag(speed)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 120)
                .help("Changing speed affects export playback rate. Audio is only kept at 1x.")

                if viewModel.speed != 1.0 {
                    Text("Audio will be removed on export")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 20)
            .padding(.top, 6)

            HStack(spacing: 10) {
                Button(action: { viewModel.stepFrame(by: -1) }) {
                    Label("Previous Frame", systemImage: "chevron.left")
                }
                .help("Move to the previous frame (Left Arrow).")

                Button(action: { viewModel.stepFrame(by: 1) }) {
                    Label("Next Frame", systemImage: "chevron.right")
                }
                .help("Move to the next frame (Right Arrow).")

                Spacer()

                Button(action: { viewModel.exportCurrentFrame() }) {
                    Label("Save Current Frame", systemImage: "photo")
                }
                .help("Export the current frame using your screenshot save settings.")
                .disabled(viewModel.duration <= 0)
            }
            .font(.caption)
            .padding(.horizontal, 20)
            .padding(.top, 4)

            Divider()
                .padding(.top, 10)

            // Playback & action buttons
            HStack {
                Button(action: { viewModel.previewTrimmed() }) {
                    Label("Preview", systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }

                Spacer()

                Button("Cancel") {
                    viewModel.cleanup()
                    onDone(nil)
                }
                .keyboardShortcut(.cancelAction)

                Button("Save Without Trimming") {
                    viewModel.cleanup()
                    onDone(videoURL)
                }

                Button("Save Trimmed") {
                    viewModel.cleanup()
                    viewModel.exportTrimmed { resultURL in
                        onDone(resultURL)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isExporting)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: viewModel.speed) { _, _ in
            viewModel.applySpeedChange()
        }
        .disabled(viewModel.isExporting)
        .overlay {
            if viewModel.isExporting {
                ProgressOverlayView(title: "Saving…")
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window?.title == "Trim Video" else { return event }
            let relevantModifiers = event.modifierFlags.intersection([.command, .option, .control])
            guard relevantModifiers.isEmpty else { return event }

            switch event.keyCode {
            case 123:
                viewModel.stepFrame(by: -1)
                return nil
            case 124:
                viewModel.stepFrame(by: 1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

// MARK: - Trim Range Slider

private struct TrimRangeSlider: View {
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var dragStartValue: Double = 0
    @State private var dragEndValue: Double = 0
    @State private var draggingStart = false
    @State private var draggingEnd = false

    private let handleWidth: CGFloat = 12
    private let trackHeight: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - handleWidth * 2)
            let startX = duration > 0 ? (trimStart / duration) * usable : 0
            let endX = duration > 0 ? (trimEnd / duration) * usable : usable
            let playheadX = duration > 0 ? handleWidth + (currentTime / duration) * usable : handleWidth

            ZStack(alignment: .leading) {
                // Dimmed regions (trimmed out)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.primary.opacity(0.1))
                    .frame(height: trackHeight)

                // Active region
                RoundedRectangle(cornerRadius: 2)
                    .fill(.orange.opacity(0.25))
                    .frame(width: max(0, endX - startX + handleWidth * 2), height: trackHeight)
                    .offset(x: startX)

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
                                let delta = value.translation.width / usable * duration
                                let newStart = max(0, min(dragStartValue + delta, trimEnd - 0.1))
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
                                let delta = value.translation.width / usable * duration
                                let newEnd = max(trimStart + 0.1, min(dragEndValue + delta, duration))
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

@MainActor
private class TrimmerViewModel: ObservableObject {
    static let speedOptions: [Double] = [0.5, 0.75, 1.0, 1.1, 1.25, 1.5, 2.0]

    static func speedLabel(for value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))x"
        }
        return String(format: "%.1fx", value)
    }

    let player: AVPlayer
    let asset: AVAsset
    let sourceURL: URL

    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    @Published var isPlaying = false
    @Published var isExporting = false
    @Published var speed: Double = 1.0
    @Published private(set) var frameStepDuration: Double = 1.0 / 30.0

    func applySpeedChange() {
        player.isMuted = speed != 1.0
        if isPlaying {
            player.rate = Float(speed)
        }
    }

    var trimmedOutputDuration: Double {
        max(0, (trimEnd - trimStart) / speed)
    }

    var totalFrameCount: Int {
        guard duration > 0, frameStepDuration > 0 else { return 0 }
        return max(1, Int((duration / frameStepDuration).rounded(.down)) + 1)
    }

    var currentFrameNumber: Int {
        guard totalFrameCount > 0 else { return 1 }
        let currentIndex = Int((max(0, currentTime) / frameStepDuration).rounded())
        return min(totalFrameCount, max(1, currentIndex + 1))
    }

    private var timeObserver: Any?

    init(url: URL) {
        self.sourceURL = url
        let asset = AVURLAsset(url: url)
        self.asset = asset
        let item = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: item)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds
                if self.isPlaying && time.seconds >= self.trimEnd {
                    self.player.pause()
                    self.isPlaying = false
                }
            }
        }
    }

    deinit {
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
        }
    }

    @MainActor
    func loadDuration() async {
        guard duration == 0 else { return }
        if let dur = try? await asset.load(.duration) {
            self.duration = dur.seconds
            self.trimEnd = dur.seconds
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let minFrameDuration = try? await track.load(.minFrameDuration),
               minFrameDuration.isValid,
               minFrameDuration.seconds > 0 {
                frameStepDuration = minFrameDuration.seconds
            } else if let nominalFrameRate = try? await track.load(.nominalFrameRate),
                      nominalFrameRate > 0 {
                frameStepDuration = 1.0 / Double(nominalFrameRate)
            }
        }
    }

    func cleanup() {
        player.pause()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    func seek(to time: Double) {
        let clamped = min(max(0, time), duration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stepFrame(by offset: Int) {
        guard duration > 0, frameStepDuration > 0 else { return }
        player.pause()
        isPlaying = false

        let currentIndex = Int((max(0, currentTime) / frameStepDuration).rounded())
        let targetIndex = max(0, min(currentIndex + offset, max(0, totalFrameCount - 1)))
        seek(to: Double(targetIndex) * frameStepDuration)
    }

    func previewTrimmed() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            seek(to: trimStart)
            player.isMuted = speed != 1.0
            player.playImmediately(atRate: Float(speed))
            isPlaying = true
        }
    }

    func exportCurrentFrame() {
        guard duration > 0 else { return }
        isExporting = true
        player.pause()
        isPlaying = false

        let outputURL = SaveService.shared.generateURL(for: .screenshot)
        let requestedTime = CMTime(seconds: currentTime, preferredTimescale: 600)

        Task {
            do {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero

                var actualTime = CMTime.zero
                let image = try generator.copyCGImage(at: requestedTime, actualTime: &actualTime)
                try Self.saveImage(image, to: outputURL)

                await MainActor.run {
                    self.currentTime = actualTime.seconds
                    self.isExporting = false
                    SaveService.shared.handleSavedFile(url: outputURL, type: .screenshot)
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    SaveService.shared.showError("Could not save the current frame: \(error.localizedDescription)")
                }
            }
        }
    }

    func exportTrimmed(completion: @escaping (URL?) -> Void) {
        isExporting = true

        let trimmedURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + " (trimmed).mp4")

        // Clean up any existing file at the destination
        try? FileManager.default.removeItem(at: trimmedURL)

        let startTime = CMTime(seconds: trimStart, preferredTimescale: 600)
        let endTime = CMTime(seconds: trimEnd, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTime, end: endTime)

        Task {
            do {
                let composition = AVMutableComposition()
                guard let track = try await asset.loadTracks(withMediaType: .video).first,
                      let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    self.isExporting = false
                    completion(nil)
                    return
                }
                try compositionTrack.insertTimeRange(timeRange, of: track, at: .zero)
                let preferredTransform = try await track.load(.preferredTransform)
                compositionTrack.preferredTransform = preferredTransform

                let targetDuration = CMTimeMultiplyByFloat64(timeRange.duration, multiplier: 1.0 / speed)
                compositionTrack.scaleTimeRange(
                    CMTimeRange(start: .zero, duration: timeRange.duration),
                    toDuration: targetDuration
                )

                // Copy audio only at 1x speed
                if speed == 1.0,
                   let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
                   let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try? compositionAudio.insertTimeRange(timeRange, of: audioTrack, at: .zero)
                }

                guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                    self.isExporting = false
                    completion(nil)
                    return
                }
                session.outputURL = trimmedURL
                session.outputFileType = .mp4

                try await session.export(to: trimmedURL, as: .mp4)
                try? FileManager.default.removeItem(at: self.sourceURL)
                self.isExporting = false
                completion(trimmedURL)
            } catch {
                self.isExporting = false
                completion(nil)
            }
        }
    }

    private static func saveImage(_ image: CGImage, to outputURL: URL) throws {
        let settings = CaptureSettings.shared
        let imageType = settings.imageFormat.utType
        var destinationProperties: [CFString: Any] = [:]
        if settings.imageFormat == .jpeg {
            destinationProperties[kCGImageDestinationLossyCompressionQuality] = settings.jpegQuality
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            imageType.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.saveFailed
        }

        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.saveFailed
        }
    }
}

// MARK: - Player View (AVPlayerView wrapper)

private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
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

private struct ProgressOverlayView: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
