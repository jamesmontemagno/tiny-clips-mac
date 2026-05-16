import SwiftUI

struct AboutSettingsSection: View {
    @ObservedObject var sparkleController: SparkleController
    let reportIssueURL: URL
    let appVersion: String
    let appBuild: String
    let distributionChannel: String

    var body: some View {
        Section {
            HStack {
                // App icon, name, version, build, distribution channel
                VStack(alignment: .leading) {
                    Text("TinyClips")
                        .font(.title2)
                        .bold()
                    Text("Version \(appVersion) (\(appBuild))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(distributionChannel)
                        .font(.caption2)
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
            }
            if let termsURL = URL(string: "https://tinyclips.app/terms.html") {
                Link("Terms of Service", destination: termsURL)
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
