import AppKit
import SwiftUI
import AVFoundation
import AVKit

class VideoTrimmerWindow: NSWindow, NSWindowDelegate {
    private var onComplete: ((URL?) -> Void)?
    private var didComplete = false

    convenience init(videoURL: URL, onComplete: @escaping (URL?) -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.onComplete = onComplete
        self.title = "Trim Video"
        self.isReleasedWhenClosed = false
        self.delegate = self
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

            // Trim time labels
            HStack {
                Label(formatTime(viewModel.trimStart), systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                Text("Duration: \(formatTime(viewModel.trimEnd - viewModel.trimStart))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(formatTime(viewModel.trimEnd), systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)

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
        .frame(width: 580, height: 460)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
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
    let player: AVPlayer
    let asset: AVAsset
    let sourceURL: URL

    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    @Published var isPlaying = false
    @Published var isExporting = false

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
        if let dur = try? await asset.load(.duration) {
            self.duration = dur.seconds
            self.trimEnd = dur.seconds
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
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func previewTrimmed() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            seek(to: trimStart)
            player.play()
            isPlaying = true
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

                // Also copy audio if present
                if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
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
