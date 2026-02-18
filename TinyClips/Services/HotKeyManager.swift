import AppKit
import Carbon.HIToolbox

// MARK: - HotKeyManager

/// Registers system-wide keyboard shortcuts via Carbon `RegisterEventHotKey`.
/// Actions are always dispatched on the main thread.
final class HotKeyManager {
    private static let hotKeySignature: OSType = 0x54434C50 // 'TCLP'

    // MARK: - Types

    private enum HotKeyID: UInt32 {
        case screenshot = 1
        case recordVideo = 2
        case recordGif = 3
        case stopRecording = 4
    }

    private struct RegisteredHotKey {
        let reference: EventHotKeyRef
        let action: () -> Void
    }

    // MARK: - Properties

    private var eventHandlerRef: EventHandlerRef?
    private var registeredHotKeys: [UInt32: RegisteredHotKey] = [:]

    // MARK: - Lifecycle

    init() {
        installEventHandlerIfNeeded()
    }

    deinit {
        unregisterAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    // MARK: - Public

    func registerCaptureHotKeys(
        onScreenshot: @escaping () -> Void,
        onRecordVideo: @escaping () -> Void,
        onRecordGif: @escaping () -> Void
    ) {
        register(
            id: .screenshot,
            keyCode: 23, // kVK_ANSI_5
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            action: onScreenshot
        )

        register(
            id: .recordVideo,
            keyCode: 22, // kVK_ANSI_6
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            action: onRecordVideo
        )

        register(
            id: .recordGif,
            keyCode: 26, // kVK_ANSI_7
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            action: onRecordGif
        )
    }

    func registerStopHotKey(onStopRecording: @escaping () -> Void) {
        register(
            id: .stopRecording,
            keyCode: 47, // kVK_ANSI_Period
            modifiers: UInt32(cmdKey),
            action: onStopRecording
        )
    }

    func unregisterStopHotKey() {
        unregister(id: .stopRecording)
    }

    func unregisterAll() {
        let hotKeyRefs = registeredHotKeys.values.map(\.reference)
        registeredHotKeys.removeAll()

        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    // MARK: - Registration

    private func register(id: HotKeyID, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        unregister(id: id)

        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id.rawValue)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else { return }

        registeredHotKeys[id.rawValue] = RegisteredHotKey(reference: hotKeyRef, action: action)
    }

    private func unregister(id: HotKeyID) {
        guard let registeredHotKey = registeredHotKeys.removeValue(forKey: id.rawValue) else { return }
        UnregisterEventHotKey(registeredHotKey.reference)
    }

    // MARK: - Carbon Event Handler

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleHotKeyEvent,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
    }

    private func handleHotKey(id: UInt32) {
        let action = registeredHotKeys[id]?.action
        // Ensure main-actor isolation for callers (future-proofs for Swift 6)
        DispatchQueue.main.async { action?() }
    }

    private static let handleHotKeyEvent: EventHandlerUPP = { _, eventRef, userData in
        guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == hotKeySignature else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handleHotKey(id: hotKeyID.id)
        return noErr
    }
}
