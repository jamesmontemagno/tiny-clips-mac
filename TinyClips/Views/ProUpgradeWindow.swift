#if APPSTORE
import AppKit
import SwiftUI
import StoreKit

// MARK: - Pro Upgrade Window

class ProUpgradeWindow: NSWindow, NSWindowDelegate {
    private var onClose: (() -> Void)?
    private var didClose = false

    convenience init(onClose: @escaping () -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.onClose = onClose
        self.title = "TinyClips Pro"
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.center()
        self.contentView = NSHostingView(rootView: ProUpgradeView())
    }

    func windowWillClose(_ notification: Notification) {
        guard !didClose else { return }
        didClose = true
        let callback = onClose
        onClose = nil
        callback?()
    }
}

// MARK: - Pro Upgrade View

private struct ProUpgradeView: View {
    @ObservedObject private var proManager = ProManager.shared

    var body: some View {
        VStack(spacing: 24) {
            headerSection
            featureList
            Divider()
            purchaseSection
        }
        .padding(24)
        .frame(width: 480)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.yellow)
            Text("TinyClips Pro")
                .font(.largeTitle.bold())
            Text("Unlock the full TinyClips experience")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProFeatureRow(
                icon: "photo.stack",
                title: "Clips Manager",
                description: "Browse all your screenshots, videos, and GIFs in one place"
            )
            ProFeatureRow(
                icon: "square.grid.2x2",
                title: "Grid & List Views",
                description: "Switch between grid and list layouts to organize your clips"
            )
            ProFeatureRow(
                icon: "arrow.up.arrow.down",
                title: "Sort & Filter",
                description: "Sort by date and filter by screenshot, video, or GIF type"
            )
        }
        .padding(.horizontal, 8)
    }

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if case .error(let msg) = proManager.purchaseState {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: { Task { await proManager.purchase() } }) {
                HStack {
                    if case .purchasing = proManager.purchaseState {
                        ProgressView().scaleEffect(0.8)
                    }
                    Text(purchaseButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(proManager.purchaseState.isTransacting)

            Button(action: { Task { await proManager.restore() } }) {
                HStack {
                    if case .restoring = proManager.purchaseState {
                        ProgressView().scaleEffect(0.8)
                    }
                    Text("Restore Purchase")
                }
            }
            .buttonStyle(.plain)
            .disabled(proManager.purchaseState.isTransacting)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var purchaseButtonTitle: String {
        if let product = proManager.proProduct {
            return "Upgrade — \(product.displayPrice)"
        }
        return "Upgrade to Pro"
    }
}

// MARK: - Feature Row

private struct ProFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
