import SwiftUI

#if APPSTORE
import StoreKit

// MARK: - Subscription View

struct ProSubscriptionView: View {
    @ObservedObject private var storeService = StoreService.shared
    @State private var selectedPlan: ProPlan = .yearly

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                if storeService.isPro {
                    ProActiveView()
                    accountActions
                } else {
                    featureList
                    planCards
                    purchaseButton
                    restoreLink
                }
                errorMessage
                if !storeService.isPro {
                    legalLinks
                }
            }
            .padding(32)
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .cornerRadius(16)
            }

            Text("Tiny Clips Pro")
                .font(.largeTitle.bold())

            Text("Unlock the full power of your captures.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow(icon: "photo.stack", text: "Clips Manager power tools for screenshots, videos, and GIFs")
            featureRow(icon: "tag", text: "Custom names, tags, notes, collections, and favorites")
            featureRow(icon: "checkmark.circle", text: "Batch actions: select multiple clips, then favorite, tag, or delete")
            featureRow(icon: "wand.and.stars", text: "Edit screenshots and trim videos/GIFs right from the manager")
            featureRow(icon: "icloud.and.arrow.up", text: "Upload to Uploadcare and copy shareable links instantly")
            featureRow(icon: "heart.fill", text: "Support independent development")
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(text)
                .font(.callout)
        }
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        HStack(spacing: 12) {
            ForEach(ProPlan.allCases) { plan in
                PlanCard(
                    plan: plan,
                    product: storeService.product(for: plan),
                    isSelected: selectedPlan == plan,
                    monthlyEquivalent: monthlyEquivalent(for: plan)
                )
                .onTapGesture { selectedPlan = plan }
            }
        }
    }

    private func monthlyEquivalent(for plan: ProPlan) -> String? {
        guard plan == .yearly,
              let product = storeService.yearlyProduct else { return nil }
        let monthly = product.price / 12
        return product.priceFormatStyle.format(monthly) + "/mo"
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        VStack(spacing: 8) {
            if storeService.isLoading {
                ProgressView("Loading plans…")
            } else if let product = storeService.product(for: selectedPlan) {
                Button {
                    Task { await storeService.purchase(product) }
                } label: {
                    HStack {
                        if storeService.isPurchasing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(purchaseButtonTitle(for: product))
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(storeService.isPurchasing)
            } else {
                Button("Subscribe") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
            }
        }
    }

    private func purchaseButtonTitle(for product: Product) -> String {
        if selectedPlan == .lifetime {
            return "Unlock Pro — \(product.displayPrice)"
        }
        return "Subscribe — \(product.displayPrice)/\(selectedPlan == .yearly ? "year" : "month")"
    }

    // MARK: - Restore

    private var restoreLink: some View {
        Button {
            Task { await storeService.restore() }
        } label: {
            Text("Restore Purchases")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(storeService.isPurchasing)
    }

    private var accountActions: some View {
        VStack(spacing: 10) {
            Button {
                storeService.manageSubscriptions()
            } label: {
                Text("Manage Subscription")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)

            restoreLink
        }
    }

    // MARK: - Legal Links

    private var legalLinks: some View {
        HStack(spacing: 16) {
            if let privacyURL = URL(string: "https://tinyclips.app/privacy.html") {
                Link("Privacy Policy", destination: privacyURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Opens Privacy Policy in your browser.")
            }

            Text("·")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            if let termsURL = URL(string: "https://tinyclips.app/terms.html") {
                Link("Terms of Use", destination: termsURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Opens Terms of Use in your browser.")
            }
        }
    }

    // MARK: - Error

    @ViewBuilder
    private var errorMessage: some View {
        if let error = storeService.purchaseError {
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Plan Card

private struct PlanCard: View {
    let plan: ProPlan
    let product: Product?
    let isSelected: Bool
    let monthlyEquivalent: String?

    var body: some View {
        VStack(spacing: 8) {
            if let badge = plan.badge {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), in: Capsule())
                    .foregroundStyle(isSelected ? .white : .secondary)
            } else {
                Text(" ")
                    .font(.caption2.weight(.bold))
                    .padding(.vertical, 2)
            }

            Text(plan.label)
                .font(.headline)

            if let product {
                Text(product.displayPrice)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if plan.isSubscription {
                    Text(plan == .yearly ? "per year" : "per month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("one-time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let monthlyEquivalent {
                    Text(monthlyEquivalent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Pro Active View

struct ProActiveView: View {
    @ObservedObject private var storeService = StoreService.shared

    var body: some View {
        VStack(spacing: 12) {
            Label("Tiny Clips Pro", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)

            if let plan = storeService.activeProPlan {
                Text("Plan: \(plan.label)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Active — thank you for your support!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

#endif
