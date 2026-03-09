import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo
import AudioToolbox

struct MicrophoneDeviceOption: Identifiable, Hashable {
    let id: String
    let name: String
}

enum MicrophoneDeviceCatalog {
    static func availableOptions() -> [MicrophoneDeviceOption] {
        AVCaptureDevice.devices(for: .audio)
            .map { MicrophoneDeviceOption(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func device(for uniqueID: String) -> AVCaptureDevice? {
        guard !uniqueID.isEmpty else { return nil }
        return AVCaptureDevice.devices(for: .audio).first(where: { $0.uniqueID == uniqueID })
    }
}

class VideoRecorder: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var microphoneSession: AVCaptureSession?
    private var microphoneOutputDelegate: MicrophoneOutputDelegate?
    private var microphoneObservers: [NSObjectProtocol] = []
    private var lastMicSignalAt = CACurrentMediaTime()
    private var hasStartedWriting = false
    private var recordSystemAudio = false
    private var recordMicrophone = false
    private var outputURL: URL?
    private let writingQueue = DispatchQueue(label: "com.tinyclips.video-writing")
    private let microphoneQueue = DispatchQueue(label: "com.tinyclips.microphone-capture")
    var onMicrophoneLevel: ((Double) -> Void)?
    var onMicrophoneWarning: ((String?) -> Void)?
    var onMicrophoneDeviceName: ((String) -> Void)?
    var onMicrophoneError: ((String) -> Void)?

    func start(region: CaptureRegion, outputURL: URL) async throws {
        let filter = try await region.makeFilter()
        let config = region.makeStreamConfig()

        let settings = CaptureSettings.shared
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.videoFrameRate))
        config.showsCursor = true
        config.queueDepth = 8
        config.pixelFormat = kCVPixelFormatType_32BGRA

        self.recordSystemAudio = settings.recordAudio
        self.recordMicrophone = settings.recordMicrophone

        if recordSystemAudio {
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }

        self.outputURL = outputURL

        let pixelWidth = region.pixelWidth
        let pixelHeight = region.pixelHeight

        let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
        ])
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)

        if recordSystemAudio {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000,
            ])
            audioInput.expectsMediaDataInRealTime = true
            writer.add(audioInput)
            self.systemAudioInput = audioInput
        }

        if recordMicrophone {
            let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000,
            ])
            micInput.expectsMediaDataInRealTime = true
            writer.add(micInput)
            self.micAudioInput = micInput
        }

        self.writer = writer
        self.videoInput = videoInput
        self.hasStartedWriting = false

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writingQueue)
        if recordSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writingQueue)
        }
        try await stream.startCapture()
        self.stream = stream

        if recordMicrophone {
            let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
            if micGranted {
                try startMicCapture(selectedMicrophoneID: settings.selectedMicrophoneID)
            } else {
                self.recordMicrophone = false
                self.micAudioInput = nil
                onMicrophoneError?("Microphone permission was denied.")
            }
        }
    }

    private func startMicCapture(selectedMicrophoneID: String) throws {
        let device: AVCaptureDevice
        if let selected = MicrophoneDeviceCatalog.device(for: selectedMicrophoneID) {
            device = selected
        } else if selectedMicrophoneID.isEmpty, let `default` = AVCaptureDevice.default(for: .audio) {
            device = `default`
        } else {
            throw CaptureError.microphoneUnavailable
        }

        onMicrophoneDeviceName?(device.localizedName)
        lastMicSignalAt = CACurrentMediaTime()

        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CaptureError.microphoneConnectionFailed
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        let delegate = MicrophoneOutputDelegate { [weak self] sampleBuffer in
            self?.handleMicrophoneSampleBuffer(sampleBuffer)
        }
        output.setSampleBufferDelegate(delegate, queue: microphoneQueue)
        guard session.canAddOutput(output) else {
            throw CaptureError.microphoneReadFailed
        }
        session.addOutput(output)

        microphoneOutputDelegate = delegate
        microphoneSession = session
        observeMicrophoneSession(session)
        microphoneQueue.async {
            session.startRunning()
        }
    }

    private func handleMicrophoneSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid else { return }

        let level = rmsLevel(from: sampleBuffer)
        onMicrophoneLevel?(level)

        let now = CACurrentMediaTime()
        if level > 0.01 {
            lastMicSignalAt = now
            onMicrophoneWarning?(nil)
        } else if now - lastMicSignalAt > 2 {
            onMicrophoneWarning?("No microphone input detected or microphone may be muted.")
        }

        writingQueue.async { [weak self] in
            guard let self, self.hasStartedWriting, let micAudioInput = self.micAudioInput, micAudioInput.isReadyForMoreMediaData else { return }
            micAudioInput.append(sampleBuffer)
        }
    }

    private func rmsLevel(from sampleBuffer: CMSampleBuffer) -> Double {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return 0
        }

        let asbd = asbdPointer.pointee
        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        )
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferStructureAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return 0 }

        let buffer = audioBufferList.mBuffers
        guard let data = buffer.mData, buffer.mDataByteSize > 0 else { return 0 }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let bytesPerSample = Int(asbd.mBitsPerChannel / 8)
        guard bytesPerSample > 0 else { return 0 }
        let sampleCount = Int(buffer.mDataByteSize) / bytesPerSample
        guard sampleCount > 0 else { return 0 }

        var sumSquares = 0.0
        if isFloat {
            let floatSamples = data.bindMemory(to: Float.self, capacity: sampleCount)
            for index in 0..<sampleCount {
                let value = Double(floatSamples[index])
                sumSquares += value * value
            }
        } else {
            let intSamples = data.bindMemory(to: Int16.self, capacity: sampleCount)
            for index in 0..<sampleCount {
                let value = Double(intSamples[index]) / Double(Int16.max)
                sumSquares += value * value
            }
        }

        return min(1, sqrt(sumSquares / Double(sampleCount)))
    }

    private func observeMicrophoneSession(_ session: AVCaptureSession) {
        let runtimeObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let error = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                ?? "Microphone became unavailable."
            self?.onMicrophoneError?(error)
        }
        microphoneObservers.append(runtimeObserver)
    }

    func stop() async throws -> URL {
        // Stop mic capture first
        stopMicrophoneCapture()

        try await stream?.stopCapture()
        stream = nil

        guard let writer, let videoInput, let outputURL else {
            throw CaptureError.saveFailed
        }

        guard hasStartedWriting else {
            throw CaptureError.noFrames
        }

        nonisolated(unsafe) let capturedVideoInput = videoInput
        nonisolated(unsafe) let capturedSystemAudioInput = self.systemAudioInput
        nonisolated(unsafe) let capturedMicAudioInput = self.micAudioInput
        nonisolated(unsafe) let capturedWriter = writer

        return try await withCheckedThrowingContinuation { continuation in
            writingQueue.async {
                capturedVideoInput.markAsFinished()
                capturedSystemAudioInput?.markAsFinished()
                capturedMicAudioInput?.markAsFinished()
                capturedWriter.finishWriting {
                    if capturedWriter.status == .completed {
                        continuation.resume(returning: outputURL)
                    } else {
                        continuation.resume(throwing: capturedWriter.error ?? CaptureError.saveFailed)
                    }
                }
            }
        }
    }

    private func stopMicrophoneCapture() {
        if let session = microphoneSession {
            if session.isRunning {
                session.stopRunning()
            }
        }
        for observer in microphoneObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        microphoneObservers.removeAll()
        microphoneOutputDelegate = nil
        microphoneSession = nil
    }
}

private final class MicrophoneOutputDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let onSampleBuffer: (CMSampleBuffer) -> Void

    init(onSampleBuffer: @escaping (CMSampleBuffer) -> Void) {
        self.onSampleBuffer = onSampleBuffer
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onSampleBuffer(sampleBuffer)
    }
}

extension VideoRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        guard let writer else { return }

        switch type {
        case .screen:
            // Only process frames with actual content
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusValue = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusValue),
                  status == .complete else {
                return
            }

            guard let videoInput else { return }

            if !hasStartedWriting {
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                hasStartedWriting = true
            }

            if videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }

        case .audio:
            guard hasStartedWriting, let systemAudioInput, systemAudioInput.isReadyForMoreMediaData else { return }
            systemAudioInput.append(sampleBuffer)

        case .microphone:
            break

        @unknown default:
            break
        }
    }
}
