import SwiftUI
import Foundation

struct MouseClicksSettingsSection: View {
    @ObservedObject var settings: CaptureSettings
    let isPro: Bool

    var body: some View {
#if APPSTORE
        if isPro {
            mouseClicksControls
        } else {
            ProSubscriptionView()
        }
#else
        mouseClicksControls
#endif
    }

    @ViewBuilder
    private var mouseClicksControls: some View {
        Section {
            Text("Tune the saved click pulse for recordings. GIF can mirror Video settings when desired. Adding click effects will add more processing time at the end of recording.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Video") {
            MouseClickOverlayControls(
                color: videoMouseClickColorBinding,
                size: Binding(
                    get: { settings.videoMouseClickSize },
                    set: { settings.videoMouseClickSize = $0 }
                ),
                strokeWidth: Binding(
                    get: { settings.videoMouseClickStrokeWidth },
                    set: { settings.videoMouseClickStrokeWidth = $0 }
                ),
                opacity: Binding(
                    get: { settings.videoMouseClickOpacity },
                    set: { settings.videoMouseClickOpacity = $0 }
                ),
                duration: Binding(
                    get: { settings.videoMouseClickDuration },
                    set: { settings.videoMouseClickDuration = $0 }
                )
            )
        }

        Section("Behavior") {
            Toggle("Use Video click settings for GIF", isOn: $settings.gifMouseClicksUseVideoSettings)
                .help("When enabled, GIF click visuals mirror Video settings.")
        }

        Section("GIF") {
            if settings.gifMouseClicksUseVideoSettings {
                Text("GIF click visuals mirror Video settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                MouseClickOverlayControls(
                    color: gifMouseClickColorBinding,
                    size: Binding(
                        get: { settings.gifMouseClickSize },
                        set: { settings.gifMouseClickSize = $0 }
                    ),
                    strokeWidth: Binding(
                        get: { settings.gifMouseClickStrokeWidth },
                        set: { settings.gifMouseClickStrokeWidth = $0 }
                    ),
                    opacity: Binding(
                        get: { settings.gifMouseClickOpacity },
                        set: { settings.gifMouseClickOpacity = $0 }
                    ),
                    duration: Binding(
                        get: { settings.gifMouseClickDuration },
                        set: { settings.gifMouseClickDuration = $0 }
                    )
                )
            }
        }
    }

    private var videoMouseClickColorBinding: Binding<NSColor> {
        Binding(
            get: { settings.videoMouseClickColor },
            set: { settings.videoMouseClickColor = $0 }
        )
    }

    private var gifMouseClickColorBinding: Binding<NSColor> {
        Binding(
            get: { settings.gifMouseClickColor },
            set: { settings.gifMouseClickColor = $0 }
        )
    }
}

struct KeyboardOverlaySettingsSection: View {
    @ObservedObject var settings: CaptureSettings
    let isPro: Bool

    var body: some View {
#if APPSTORE
        if isPro {
            keyboardOverlayControls
        } else {
            ProSubscriptionView()
        }
#else
        keyboardOverlayControls
#endif
    }

    @ViewBuilder
    private var keyboardOverlayControls: some View {
        Section("Keyboard Overlay") {
            Text("Customize keyboard key overlays for recordings. Overlay settings can be shared from Video to GIF when desired.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Use Video keyboard settings for GIF", isOn: $settings.gifKeyboardOverlayUseVideoSettings)
                .help("When enabled, GIF keyboard overlays mirror Video settings.")
                .accessibilityHint("Uses the same keyboard overlay customization for GIF and Video.")
        }

        Section("Video") {
            keyboardOverlayEditors(
                color: videoKeyboardColorBinding,
                size: Binding(
                    get: { settings.videoKeyboardOverlaySize },
                    set: { settings.videoKeyboardOverlaySize = $0 }
                ),
                duration: Binding(
                    get: { settings.videoKeyboardOverlayDuration },
                    set: { settings.videoKeyboardOverlayDuration = $0 }
                ),
                displayModeRaw: $settings.videoKeyboardOverlayDisplayModeRaw,
                customKeys: $settings.videoKeyboardOverlayCustomKeys,
                positionRaw: $settings.videoKeyboardOverlayPositionRaw,
                animationRaw: $settings.videoKeyboardOverlayAnimationStyleRaw,
                shapeRaw: $settings.videoKeyboardOverlayShapeStyleRaw,
                soundEffects: $settings.videoKeyboardOverlaySoundEffects
            )
        }

        Section("GIF") {
            if settings.gifKeyboardOverlayUseVideoSettings {
                Text("GIF keyboard overlays mirror Video settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                keyboardOverlayEditors(
                    color: gifKeyboardColorBinding,
                    size: Binding(
                        get: { settings.gifKeyboardOverlaySize },
                        set: { settings.gifKeyboardOverlaySize = $0 }
                    ),
                    duration: Binding(
                        get: { settings.gifKeyboardOverlayDuration },
                        set: { settings.gifKeyboardOverlayDuration = $0 }
                    ),
                    displayModeRaw: $settings.gifKeyboardOverlayDisplayModeRaw,
                    customKeys: $settings.gifKeyboardOverlayCustomKeys,
                    positionRaw: $settings.gifKeyboardOverlayPositionRaw,
                    animationRaw: $settings.gifKeyboardOverlayAnimationStyleRaw,
                    shapeRaw: $settings.gifKeyboardOverlayShapeStyleRaw,
                    soundEffects: $settings.gifKeyboardOverlaySoundEffects
                )
            }
        }
    }

    @ViewBuilder
    private func keyboardOverlayEditors(
        color: Binding<NSColor>,
        size: Binding<Double>,
        duration: Binding<Double>,
        displayModeRaw: Binding<String>,
        customKeys: Binding<String>,
        positionRaw: Binding<String>,
        animationRaw: Binding<String>,
        shapeRaw: Binding<String>,
        soundEffects: Binding<Bool>
    ) -> some View {
        ColorPicker("Overlay color", selection: color, supportsOpacity: false)
            .help("Choose keyboard overlay background color.")
            .accessibilityHint("Sets the keyboard overlay color.")
        HStack {
            Text("Text size")
            Slider(value: size, in: 14...38, step: 1)
            Text("\(Int(size.wrappedValue))")
                .frame(width: 28, alignment: .trailing)
                .monospacedDigit()
        }
        .help("Adjust keyboard overlay text size.")

        HStack {
            Text("Display duration")
            Slider(value: duration, in: 0.25...2.0, step: 0.05)
            Text("\(String(format: "%.2fs", duration.wrappedValue))")
                .frame(width: 54, alignment: .trailing)
                .monospacedDigit()
        }
        .help("How long each key overlay remains visible.")

        Picker("Display mode", selection: displayModeRaw) {
            ForEach(KeyboardOverlayDisplayMode.allCases, id: \.rawValue) { mode in
                Text(mode.label).tag(mode.rawValue)
            }
        }
        .help("Show all keys, hide modifier-only keys, or use a custom key subset.")

        if KeyboardOverlayDisplayMode(rawValue: displayModeRaw.wrappedValue) == .customSubset {
            TextField("Custom keys (comma-separated, e.g. A, B, 4, SPACE)", text: customKeys)
                .textFieldStyle(.roundedBorder)
                .help("Enter keys to show. Use comma-separated key labels such as A, B, 4, SPACE.")
                .accessibilityLabel("Custom keyboard overlay keys")
                .accessibilityHint("Provide a comma-separated list of keys to visualize.")
        }

        Picker("Position", selection: positionRaw) {
            ForEach(KeyboardOverlayPosition.allCases, id: \.rawValue) { position in
                Text(position.label).tag(position.rawValue)
            }
        }
        .help("Choose where key overlays appear in recordings.")

        Picker("Animation style", selection: animationRaw) {
            ForEach(KeyboardOverlayAnimationStyle.allCases, id: \.rawValue) { style in
                Text(style.label).tag(style.rawValue)
            }
        }
        .help("Choose how key overlays animate in/out.")

        Picker("Overlay shape", selection: shapeRaw) {
            ForEach(KeyboardOverlayShapeStyle.allCases, id: \.rawValue) { shape in
                Text(shape.label).tag(shape.rawValue)
            }
        }
        .help("Choose the key overlay background shape.")

        Toggle("Play key sound effects", isOn: soundEffects)
            .help("Optional: play a subtle click sound when keys are shown in overlays.")

        KeyboardOverlayPreview(
            color: color.wrappedValue,
            size: CGFloat(size.wrappedValue),
            shape: KeyboardOverlayShapeStyle(rawValue: shapeRaw.wrappedValue) ?? .roundedRect
        )
        .accessibilityLabel("Keyboard overlay preview")
        .accessibilityHint("Preview of the current keyboard overlay appearance.")
    }

    private var videoKeyboardColorBinding: Binding<NSColor> {
        Binding(
            get: { settings.videoKeyboardOverlayColor },
            set: { settings.videoKeyboardOverlayColor = $0 }
        )
    }

    private var gifKeyboardColorBinding: Binding<NSColor> {
        Binding(
            get: { settings.gifKeyboardOverlayColor },
            set: { settings.gifKeyboardOverlayColor = $0 }
        )
    }
}

private struct KeyboardOverlayPreview: View {
    let color: NSColor
    let size: CGFloat
    let shape: KeyboardOverlayShapeStyle

    var body: some View {
        let textColor = color.isLightColor ? Color.black.opacity(0.9) : Color.white
        let bg = Color(color)

        HStack(spacing: 0) {
            Text("⌘ + ⇧ + 4")
                .font(.system(size: max(12, size * 0.65), weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
                .padding(.horizontal, max(10, size * 0.45))
                .padding(.vertical, max(6, size * 0.28))
                .background {
                    switch shape {
                    case .roundedRect:
                        RoundedRectangle(cornerRadius: 10).fill(bg.opacity(0.84))
                    case .capsule:
                        Capsule().fill(bg.opacity(0.84))
                    case .minimal:
                        RoundedRectangle(cornerRadius: 6).fill(bg.opacity(0.6))
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private extension NSColor {
    var isLightColor: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        let luminance = (0.2126 * rgb.redComponent) + (0.7152 * rgb.greenComponent) + (0.0722 * rgb.blueComponent)
        return luminance > 0.63
    }
}
