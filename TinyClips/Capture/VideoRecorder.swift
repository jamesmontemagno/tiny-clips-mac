import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo
import AudioToolbox
import CoreAudio

struct MicrophoneDeviceOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct OutputAudioDeviceOption: Identifiable, Hashable {
    let id: String
    let name: String
}

enum MicrophoneDeviceCatalog {
    private static func audioDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }

    static func availableOptions() -> [MicrophoneDeviceOption] {
        audioDevices()
            .map { MicrophoneDeviceOption(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func device(for uniqueID: String) -> AVCaptureDevice? {
        guard !uniqueID.isEmpty else { return nil }
        return audioDevices().first(where: { $0.uniqueID == uniqueID })
    }
}

enum OutputAudioDeviceCatalog {
    private static func hardwareDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(0), count: count)
        let status = devices.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return kAudioHardwareBadObjectError }
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, baseAddress)
        }
        guard status == noErr else { return [] }
        return devices
    }

    private static func copyStringProperty(_ selector: AudioObjectPropertySelector, of deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfStr = Unmanaged<CFString>.passUnretained("" as CFString)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfStr) == noErr else {
            return nil
        }
        return cfStr.takeUnretainedValue() as String
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        copyStringProperty(kAudioDevicePropertyDeviceUID, of: deviceID)
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        copyStringProperty(kAudioObjectPropertyName, of: deviceID)
    }

    private static func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return false
        }
        let bufferListPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListPointer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer) == noErr else {
            return false
        }
        let bufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    static func availableOptions() -> [OutputAudioDeviceOption] {
        hardwareDevices()
            .filter(hasOutputStreams)
            .compactMap { deviceID in
                guard let uid = deviceUID(for: deviceID),
                      let name = deviceName(for: deviceID) else {
                    return nil
                }
                return OutputAudioDeviceOption(id: uid, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceUID(for: deviceID)
    }

    static func resolvedUID(from selectedUID: String) -> String {
        let options = availableOptions()
        if !selectedUID.isEmpty, options.contains(where: { $0.id == selectedUID }) {
            return selectedUID
        }
        return defaultOutputDeviceUID() ?? ""
    }
}

class VideoRecorder: NSObject, @unchecked Sendable {
    private let microphoneSignalThreshold = 0.01
    private let microphoneSignalTimeoutSeconds: TimeInterval = 2
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var microphoneSession: AVCaptureSession?
    private var microphoneOutputDelegate: MicrophoneOutputDelegate?
    private var microphoneObservers: [NSObjectProtocol] = []
    private var outputDeviceCapture: OutputDeviceCapture?
    private var lastMicSignalAt = CACurrentMediaTime()
    private var lastOutputAudioSignalAt = CACurrentMediaTime()
    private var lastWrittenAudioEndTime = CMTime.invalid
    private var hasStartedWriting = false
    private var recordSystemAudio = false
    private var recordMicrophone = false
    private var useOutputDeviceTap = false
    private var outputURL: URL?
    private let writingQueue = DispatchQueue(label: "com.tinyclips.video-writing")
    private let microphoneQueue = DispatchQueue(label: "com.tinyclips.microphone-capture")
    var onMicrophoneLevel: ((Double) -> Void)?
    var onMicrophoneWarning: ((String?) -> Void)?
    var onMicrophoneDeviceName: ((String) -> Void)?
    var onMicrophoneError: ((String) -> Void)?
    var onOutputAudioDeviceName: ((String) -> Void)?
    var onOutputAudioLevel: ((Double) -> Void)?
    var onOutputAudioWarning: ((String?) -> Void)?

    var isOutputAudioActive: Bool {
        recordSystemAudio
    }

    var isMicrophoneCaptureActive: Bool {
        microphoneSession != nil && recordMicrophone
    }

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

        let selectedOutputUID = settings.selectedOutputAudioDeviceUID
        self.useOutputDeviceTap = recordSystemAudio && !selectedOutputUID.isEmpty

        if recordSystemAudio {
            let devices = OutputAudioDeviceCatalog.availableOptions()
            let resolvedUID: String
            if !selectedOutputUID.isEmpty, devices.contains(where: { $0.id == selectedOutputUID }) {
                resolvedUID = selectedOutputUID
            } else {
                resolvedUID = OutputAudioDeviceCatalog.defaultOutputDeviceUID() ?? ""
            }
            onOutputAudioDeviceName?(devices.first(where: { $0.id == resolvedUID })?.name ?? "System Default")

            if !useOutputDeviceTap {
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 48000
                config.channelCount = 2
            }
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

        do {
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writingQueue)
            if recordSystemAudio && !useOutputDeviceTap {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writingQueue)
            }
            try await stream.startCapture()
            self.stream = stream

            if useOutputDeviceTap {
                let resolvedUID = OutputAudioDeviceCatalog.resolvedUID(from: selectedOutputUID)
                let capture = OutputDeviceCapture()
                capture.onSampleBuffer = { [weak self] sampleBuffer in
                    self?.handleOutputAudioSampleBuffer(sampleBuffer)
                }
                try capture.start(deviceUID: resolvedUID)
                self.outputDeviceCapture = capture
            }

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
        } catch {
            await resetAfterFailedStart(removeOutputFile: true)
            throw error
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
        if level > microphoneSignalThreshold {
            lastMicSignalAt = now
            onMicrophoneWarning?(nil)
        } else if now - lastMicSignalAt > microphoneSignalTimeoutSeconds {
            onMicrophoneWarning?("No microphone input detected or microphone may be muted.")
        }

        writingQueue.async { [weak self] in
            guard let self, self.hasStartedWriting, let micAudioInput = self.micAudioInput, micAudioInput.isReadyForMoreMediaData else { return }
            micAudioInput.append(sampleBuffer)
        }
    }

    private func handleOutputAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid else { return }

        let level = rmsLevel(from: sampleBuffer)
        onOutputAudioLevel?(level)

        let now = CACurrentMediaTime()
        if level > microphoneSignalThreshold {
            lastOutputAudioSignalAt = now
            onOutputAudioWarning?(nil)
        } else if now - lastOutputAudioSignalAt > microphoneSignalTimeoutSeconds {
            onOutputAudioWarning?("No output audio signal detected.")
        }

        writingQueue.async { [weak self] in
            guard let self, self.hasStartedWriting, let systemAudioInput = self.systemAudioInput, systemAudioInput.isReadyForMoreMediaData else { return }
            let pts = sampleBuffer.presentationTimeStamp
            if self.lastWrittenAudioEndTime.isValid, pts < self.lastWrittenAudioEndTime { return }
            systemAudioInput.append(sampleBuffer)
            let dur = sampleBuffer.duration
            self.lastWrittenAudioEndTime = dur.isValid ? CMTimeAdd(pts, dur) : pts
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
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return 0 }

        let buffer = audioBufferList.mBuffers
        guard let data = buffer.mData, buffer.mDataByteSize > 0 else { return 0 }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let bytesPerSample = Int(asbd.mBitsPerChannel / 8)
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        guard bytesPerSample > 0 else { return 0 }
        let sampleCount = Int(buffer.mDataByteSize) / (bytesPerSample * channels)
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

        let interruptedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.onMicrophoneError?("Microphone input was interrupted.")
        }
        microphoneObservers.append(interruptedObserver)

        let interruptionEndedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.onMicrophoneWarning?(nil)
        }
        microphoneObservers.append(interruptionEndedObserver)
    }

    func stop() async throws -> URL {
        // Stop auxiliary capture first
        stopOutputDeviceCapture()
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

    private func stopOutputDeviceCapture() {
        outputDeviceCapture?.stop()
        outputDeviceCapture = nil
    }

    private func resetAfterFailedStart(removeOutputFile: Bool) async {
        stopOutputDeviceCapture()
        stopMicrophoneCapture()
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        writer?.cancelWriting()
        writer = nil
        videoInput = nil
        systemAudioInput = nil
        micAudioInput = nil
        hasStartedWriting = false
        recordSystemAudio = false
        recordMicrophone = false
        useOutputDeviceTap = false
        lastWrittenAudioEndTime = .invalid
        onMicrophoneWarning?(nil)
        onMicrophoneLevel?(0)
        onMicrophoneDeviceName?("")
        onOutputAudioDeviceName?("")
        onOutputAudioLevel?(0)
        onOutputAudioWarning?(nil)
        if removeOutputFile, let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        outputURL = nil
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
            // Meter output audio level for the stop panel indicator
            let level = rmsLevel(from: sampleBuffer)
            onOutputAudioLevel?(level)
            let now = CACurrentMediaTime()
            if level > microphoneSignalThreshold {
                lastOutputAudioSignalAt = now
                onOutputAudioWarning?(nil)
            } else if now - lastOutputAudioSignalAt > microphoneSignalTimeoutSeconds {
                onOutputAudioWarning?("No output audio signal detected.")
            }

            guard hasStartedWriting, let systemAudioInput, systemAudioInput.isReadyForMoreMediaData else { return }
            let pts = sampleBuffer.presentationTimeStamp
            if lastWrittenAudioEndTime.isValid, pts < lastWrittenAudioEndTime { return }
            systemAudioInput.append(sampleBuffer)
            let dur = sampleBuffer.duration
            lastWrittenAudioEndTime = dur.isValid ? CMTimeAdd(pts, dur) : pts

        case .microphone:
            break

        @unknown default:
            break
        }
    }
}

// MARK: - Output Device Capture via Core Audio Tap

private func outputDeviceInputCallback(
    _ inRefCon: UnsafeMutableRawPointer,
    _ ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
    _ inBusNumber: UInt32,
    _ inNumberFrames: UInt32,
    _ ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let capture = Unmanaged<OutputDeviceCapture>.fromOpaque(inRefCon).takeUnretainedValue()
    capture.renderAndDeliver(
        actionFlags: ioActionFlags,
        timeStamp: inTimeStamp,
        busNumber: inBusNumber,
        numFrames: inNumberFrames
    )
    return noErr
}

private final class OutputDeviceCapture: @unchecked Sendable {
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioDeviceID = kAudioObjectUnknown
    fileprivate var audioUnit: AudioComponentInstance?
    private var formatDescription: CMAudioFormatDescription?

    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func start(deviceUID: String) throws {
        // 1. Create a process tap that captures all output audio on the device
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.deviceUID = deviceUID
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .unmuted
        tapDesc.name = "TinyClips Output Tap"

        var tapObjectID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &tapObjectID)
        guard tapStatus == noErr else { throw CaptureError.outputAudioStartFailed }
        self.tapID = tapObjectID

        // 2. Create an aggregate device that reads from the tap
        let tapUUID = tapDesc.uuid.uuidString
        let aggDesc: NSDictionary = [
            kAudioAggregateDeviceUIDKey: "com.tinyclips.tap-\(UUID().uuidString)",
            kAudioAggregateDeviceNameKey: "TinyClips Output Capture",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID]
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]

        var aggDeviceID: AudioDeviceID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc, &aggDeviceID)
        guard aggStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapObjectID)
            tapID = kAudioObjectUnknown
            throw CaptureError.outputAudioStartFailed
        }
        self.aggregateDeviceID = aggDeviceID

        // 3. Create AUHAL audio unit for input capture from the aggregate device
        var componentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDesc) else {
            throw CaptureError.outputAudioStartFailed
        }

        var unit: AudioComponentInstance?
        guard AudioComponentInstanceNew(component, &unit) == noErr, let unit else {
            throw CaptureError.outputAudioStartFailed
        }

        // Enable input on bus 1, disable output on bus 0
        var enableIO: UInt32 = 1
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, 1,
                             &enableIO, UInt32(MemoryLayout<UInt32>.size))

        var disableIO: UInt32 = 0
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, 0,
                             &disableIO, UInt32(MemoryLayout<UInt32>.size))

        // Point the AUHAL at the aggregate device
        var devID = aggDeviceID
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0,
                             &devID, UInt32(MemoryLayout<AudioDeviceID>.size))

        // Set desired client format: interleaved Float32, 48 kHz, stereo
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output, 1,
                             &clientFormat,
                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        // Build CMAudioFormatDescription for CMSampleBuffer creation
        var fmtDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &clientFormat,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &fmtDesc
        )
        self.formatDescription = fmtDesc

        // Install input callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: outputDeviceInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback,
                             kAudioUnitScope_Global, 0,
                             &callbackStruct,
                             UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        // Initialize and start
        guard AudioUnitInitialize(unit) == noErr else {
            AudioComponentInstanceDispose(unit)
            throw CaptureError.outputAudioStartFailed
        }

        self.audioUnit = unit

        guard AudioOutputUnitStart(unit) == noErr else {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            self.audioUnit = nil
            throw CaptureError.outputAudioStartFailed
        }
    }

    func stop() {
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        formatDescription = nil
    }

    // Called from the Core Audio I/O thread via the C callback
    fileprivate func renderAndDeliver(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        numFrames: UInt32
    ) {
        guard let unit = audioUnit, let formatDescription else { return }

        let bytesPerFrame: UInt32 = 8 // 2 channels × 4 bytes (Float32)
        let bufferByteSize = numFrames * bytesPerFrame
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(bufferByteSize), alignment: 4)

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: bufferByteSize,
                mData: data
            )
        )

        let renderStatus = AudioUnitRender(unit, actionFlags, timeStamp, busNumber, numFrames, &bufferList)
        guard renderStatus == noErr else {
            data.deallocate()
            return
        }

        // Build a CMSampleBuffer from the rendered audio
        let pts = CMClockMakeHostTimeFromSystemUnits(timeStamp.pointee.mHostTime)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48000),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(numFrames),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard createStatus == noErr, let sampleBuffer else {
            data.deallocate()
            return
        }

        // Copy audio data into the sample buffer's block buffer
        let setDataStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: &bufferList
        )

        data.deallocate()

        guard setDataStatus == noErr else { return }
        onSampleBuffer?(sampleBuffer)
    }
}
