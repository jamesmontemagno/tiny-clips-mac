import SwiftUI

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
