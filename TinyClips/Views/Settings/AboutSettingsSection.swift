import SwiftUI

struct AboutSettingsSection: View {
    @ObservedObject var sparkleController: SparkleController
    let reportIssueURL: URL
    let appVersion: String
    let appBuild: String

    var body: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(14)
                    }
                    Text("TinyClips")
                        .font(.headline)
                    Text("v\(appVersion) (\(appBuild))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }

        Section {
            Link("GitHub Repository", destination: URL(string: "https://github.com/jamesmontemagno/tiny-clips-mac")!)
                .accessibilityHint("Opens the TinyClips GitHub repository in your browser.")
            Link("Report an Issue", destination: reportIssueURL)
                .accessibilityHint("Opens the issue reporter in your browser.")
            if let privacyURL = URL(string: "https://tinyclips.app/privacy.html") {
                Link("Privacy Policy", destination: privacyURL)
                    .accessibilityHint("Opens Privacy Policy in your browser.")
            }
            if let termsURL = URL(string: "https://tinyclips.app/terms.html") {
                Link("Terms of Use", destination: termsURL)
                    .accessibilityHint("Opens Terms of Use in your browser.")
            }
        }

#if !APPSTORE
        Section {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { sparkleController.automaticallyChecksForUpdates },
                set: { sparkleController.automaticallyChecksForUpdates = $0 }
            ))
            .help("When enabled, TinyClips periodically checks for updates and Sparkle presents the standard update alert when one is available.")

            Button("Check for Updates\u{2026}") {
                sparkleController.checkForUpdates()
            }
            .help("Manually check for updates now.")
        }
#endif
    }
}
