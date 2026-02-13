import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo

class VideoRecorder: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var audioEngine: AVAudioEngine?
    private var hasStartedWriting = false
    private var recordSystemAudio = false
    private var recordMicrophone = false
    private var outputURL: URL?
    private let writingQueue = DispatchQueue(label: "com.tinyclips.video-writing")

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

        let pixelWidth = Int(region.sourceRect.width * region.scaleFactor)
        let pixelHeight = Int(region.sourceRect.height * region.scaleFactor)

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
                try startMicCapture()
            } else {
                self.recordMicrophone = false
                self.micAudioInput = nil
            }
        }
    }

    private func startMicCapture() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Convert mic to 48kHz mono for AAC encoding
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        ) else { return }

        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self, let micInput = self.micAudioInput, self.hasStartedWriting else { return }

            // Convert to target format
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 48000.0 / inputFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            converter?.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            guard error == nil else { return }

            // Create CMSampleBuffer from the converted PCM buffer
            guard let sampleBuffer = self.createSampleBuffer(from: convertedBuffer, presentationTime: time) else { return }

            self.writingQueue.async {
                if micInput.isReadyForMoreMediaData {
                    micInput.append(sampleBuffer)
                }
            }
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
    }

    private func createSampleBuffer(from buffer: AVAudioPCMBuffer, presentationTime: AVAudioTime) -> CMSampleBuffer? {
        guard let formatDesc = buffer.format.formatDescription as CMFormatDescription? else { return nil }

        let frameCount = CMItemCount(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate

        // Use host time to align with SCStream's clock (both based on mach_absolute_time)
        let hostSeconds: Double
        if presentationTime.isHostTimeValid {
            hostSeconds = AVAudioTime.seconds(forHostTime: presentationTime.hostTime)
        } else {
            hostSeconds = CACurrentMediaTime()
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: CMTime(seconds: hostSeconds, preferredTimescale: CMTimeScale(sampleRate)),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        guard let audioBufferList = buffer.audioBufferList.pointee.mBuffers.mData else { return nil }

        let dataSize = Int(buffer.audioBufferList.pointee.mBuffers.mDataByteSize)
        let data = Data(bytes: audioBufferList, count: dataSize)

        let blockBuffer: CMBlockBuffer?
        var block: CMBlockBuffer?
        data.withUnsafeBytes { rawPtr in
            guard let baseAddress = rawPtr.baseAddress else { return }
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: dataSize,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: dataSize,
                flags: 0,
                blockBufferOut: &block
            )
            if let block {
                CMBlockBufferReplaceDataBytes(
                    with: baseAddress,
                    blockBuffer: block,
                    offsetIntoDestination: 0,
                    dataLength: dataSize
                )
            }
        }
        blockBuffer = block

        guard let blockBuffer else { return nil }

        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }

    func stop() async throws -> URL {
        // Stop mic capture first
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        try await stream?.stopCapture()
        stream = nil

        guard let writer, let videoInput, let outputURL else {
            throw CaptureError.saveFailed
        }

        guard hasStartedWriting else {
            throw CaptureError.noFrames
        }

        let systemAudioInput = self.systemAudioInput
        let micAudioInput = self.micAudioInput

        return try await withCheckedThrowingContinuation { continuation in
            writingQueue.async {
                videoInput.markAsFinished()
                systemAudioInput?.markAsFinished()
                micAudioInput?.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: outputURL)
                    } else {
                        continuation.resume(throwing: writer.error ?? CaptureError.saveFailed)
                    }
                }
            }
        }
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

        @unknown default:
            break
        }
    }
}
