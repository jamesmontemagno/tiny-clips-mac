
#if APPSTORE
import SwiftUI

struct ProSettingsSection: View {
    @ObservedObject private var storeService = StoreService.shared

    var body: some View {
        if storeService.isPro {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TinyClips Pro")
                            .font(.headline)
                        if let plan = storeService.activeProPlan {
                            Text("Plan: \(plan.label) — thank you for your support!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Active — thank you for your support!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Label("Active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                HStack(spacing: 10) {
                    Button("Manage Subscription") {
                        storeService.manageSubscriptions()
                    }
                    .buttonStyle(.bordered)

                    Button("Restore Purchases") {
                        Task { await storeService.restore() }
                    }
                    .buttonStyle(.plain)
                    .disabled(storeService.isPurchasing)
                }
            }

        } else {
            ProSubscriptionView()
        }
    }
}
#endif
