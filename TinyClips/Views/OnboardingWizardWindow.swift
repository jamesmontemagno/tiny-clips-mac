import AppKit
import SwiftUI

@MainActor
class OnboardingWizardWindow: NSWindow, NSWindowDelegate {
    private var onComplete: ((Bool) -> Void)?
    private var didComplete = false

    convenience init(onComplete: @escaping (Bool) -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.onComplete = onComplete
        self.delegate = self
        self.isReleasedWhenClosed = false
        self.title = "Welcome to Tiny Clips"
        self.center()

        let hostingView = NSHostingView(rootView: OnboardingWizardView(
            onFinish: { [weak self] in
                self?.finish(completed: true)
            },
            onSkip: { [weak self] in
                self?.finish(completed: true)
            }
        ))
        self.contentView = hostingView
    }

    func windowWillClose(_ notification: Notification) {
        guard !didComplete else { return }
        didComplete = true
        onComplete?(false)
        onComplete = nil
    }

    private func finish(completed: Bool) {
        guard !didComplete else { return }
        didComplete = true
        onComplete?(completed)
        onComplete = nil
        close()
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case screen
    case optional
    case settings

    var title: String {
        switch self {
        case .welcome:
            return "Get started quickly"
        case .screen:
            return "Allow Screen Recording"
        case .optional:
            return "Optional Permissions"
        case .settings:
            return "Common Capture Settings"
        }
    }
}

private struct OnboardingWizardView: View {
    @ObservedObject private var settings = CaptureSettings.shared
    @State private var step: OnboardingStep = .welcome
    @State private var screenGranted = false
    @State private var microphoneGranted = false
    @State private var notificationsGranted = false
    @State private var showSkipConfirmation = false

    let onFinish: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title)
                .font(.headline)

            Group {
                switch step {
                case .welcome:
                    welcomeContent
                case .screen:
                    screenPermissionContent
                case .optional:
                    optionalPermissionsContent
                case .settings:
                    commonSettingsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack {
                Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if step != .welcome {
                    Button("Back") {
                        previousStep()
                    }
                }

                Button("Skip") {
                    showSkipConfirmation = true
                }
                .keyboardShortcut(.cancelAction)

                Button(primaryButtonTitle) {
                    handlePrimaryAction()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear {
            refreshStatus()
        }
        .alert("Skip setup?", isPresented: $showSkipConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Skip Setup", role: .destructive) {
                onSkip()
            }
        } message: {
            Text("You can run setup later from Settings.")
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("TinyClips")
                        .font(.title3.weight(.semibold))
                    Text("Fast captures from your menu bar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Screen Recording is required to capture your screen.", systemImage: "display")
                Label("Microphone and Notifications are optional.", systemImage: "slider.horizontal.3")
                Label("This setup only takes a moment.", systemImage: "sparkles")
            }
            .font(.callout)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var screenPermissionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            permissionRow(
                title: "Screen Recording",
                isGranted: screenGranted,
                grantedText: "Allowed",
                deniedText: "Not allowed"
            )

            HStack(spacing: 10) {
                Button("Allow Screen Recording") {
                    requestScreenPermission()
                }

                Button("Re-check") {
                    recheckScreenPermission()
                }

                Button("Open System Settings") {
                    PermissionManager.shared.openScreenRecordingSettings()
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)

                Text("After enabling Screen Recording in System Settings, you must restart TinyClips for the change to apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var optionalPermissionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            permissionRow(
                title: "Microphone",
                isGranted: microphoneGranted,
                grantedText: "Allowed",
                deniedText: "Not allowed"
            )

            HStack(spacing: 10) {
                Button(microphoneGranted ? "Re-check" : "Allow Microphone") {
                    requestMicrophonePermission()
                }

                Button("Open Microphone Settings") {
                    PermissionManager.shared.openMicrophoneSettings()
                }
            }

            Divider()

            permissionRow(
                title: "Notifications",
                isGranted: notificationsGranted,
                grantedText: "Allowed",
                deniedText: "Not allowed"
            )

            HStack(spacing: 10) {
                Button(notificationsGranted ? "Re-check" : "Allow Notifications") {
                    requestNotificationPermission()
                }

                Button("Open Notifications Settings") {
                    PermissionManager.shared.openNotificationSettings()
                }
            }
        }
    }

    private var commonSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your default capture behavior. You can change this any time in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            editorDefaultsRow(
                title: "Screenshots",
                openLabel: "Open editor after capture",
                openBinding: $settings.showScreenshotEditor,
                saveBinding: $settings.saveImmediatelyScreenshot,
                copyBinding: $settings.copyScreenshotToClipboard,
                openHelp: "Open the screenshot editor after capture so you can annotate or crop before finishing.",
                saveHelp: "When enabled, screenshots save right away instead of waiting for editor actions.",
                copyHelp: "Copy saved screenshots to the clipboard as an image."
            )

            editorDefaultsRow(
                title: "Videos",
                openLabel: "Open trimmer after recording",
                openBinding: $settings.showTrimmer,
                saveBinding: $settings.saveImmediatelyVideo,
                copyBinding: $settings.copyVideoToClipboard,
                openHelp: "Open the video trimmer after recording so you can trim before finishing.",
                saveHelp: "When enabled, videos save right away instead of waiting for trimmer actions.",
                copyHelp: "Copy saved videos to the clipboard as a file URL."
            )

            editorDefaultsRow(
                title: "GIFs",
                openLabel: "Open trimmer after recording",
                openBinding: $settings.showGifTrimmer,
                saveBinding: $settings.saveImmediatelyGif,
                copyBinding: $settings.copyGifToClipboard,
                openHelp: "Open the GIF trimmer after recording so you can trim before finishing.",
                saveHelp: "When enabled, GIFs save right away instead of waiting for trimmer actions.",
                copyHelp: "Copy saved GIFs to the clipboard as a file URL."
            )
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:
            return "Get Started"
        case .screen:
            return "Next"
        case .optional:
            return "Next"
        case .settings:
            return "Finish"
        }
    }

    private func handlePrimaryAction() {
        switch step {
        case .welcome:
            step = .screen
        case .screen:
            step = .optional
        case .optional:
            step = .settings
        case .settings:
            onFinish()
        }
    }

    private func previousStep() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func refreshStatus() {
        screenGranted = PermissionManager.shared.hasScreenRecordingPermission()
        microphoneGranted = PermissionManager.shared.microphonePermissionGranted()

        Task {
            notificationsGranted = await PermissionManager.shared.notificationPermissionGranted()
        }
    }

    private func requestScreenPermission() {
        Task {
            let granted = await PermissionManager.shared.checkPermission()
            screenGranted = granted || PermissionManager.shared.hasScreenRecordingPermission()
        }
    }

    private func recheckScreenPermission() {
        screenGranted = PermissionManager.shared.hasScreenRecordingPermission()
    }

    private func requestMicrophonePermission() {
        Task {
            microphoneGranted = await PermissionManager.shared.requestMicrophonePermission()
        }
    }

    private func requestNotificationPermission() {
        Task {
            notificationsGranted = await PermissionManager.shared.requestNotificationPermission()
        }
    }

    private func permissionRow(title: String, isGranted: Bool, grantedText: String, deniedText: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isGranted ? .green : .secondary)

            Text(title)
                .fontWeight(.medium)

            Spacer()

            Text(isGranted ? grantedText : deniedText)
                .foregroundStyle(.secondary)
        }
    }

    private func editorDefaultsRow(
        title: String,
        openLabel: String,
        openBinding: Binding<Bool>,
        saveBinding: Binding<Bool>,
        copyBinding: Binding<Bool>,
        openHelp: String,
        saveHelp: String,
        copyHelp: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            toggleRow(openLabel, binding: openBinding, helpText: openHelp)
                .onChange(of: openBinding.wrappedValue) { _, isEnabled in
                    if !isEnabled {
                        saveBinding.wrappedValue = true
                    }
                }

            toggleRow("Save immediately", binding: saveBinding, isIndented: true, helpText: saveHelp)
                .disabled(!openBinding.wrappedValue)
            toggleRow("Copy to clipboard", binding: copyBinding, helpText: copyHelp)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func toggleRow(_ title: String, binding: Binding<Bool>, isIndented: Bool = false, helpText: String? = nil) -> some View {
        let row = Toggle(title, isOn: binding)
            .toggleStyle(.checkbox)
            .font(.callout)
            .padding(.leading, isIndented ? 18 : 0)

        if let helpText {
            row.help(helpText)
        } else {
            row
        }
    }
}
