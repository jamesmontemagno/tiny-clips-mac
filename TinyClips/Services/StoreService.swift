import Foundation

#if APPSTORE
import AppKit
import StoreKit

// MARK: - Pro Plan

enum ProPlan: String, CaseIterable, Identifiable {
    case monthly = "com.refractored.tinyclips.pro.monthly"
    case yearly = "com.refractored.tinyclips.pro.yearly"
    case lifetime = "com.refractored.tinyclips.pro.lifetime"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .lifetime: return "Lifetime"
        }
    }

    var badge: String? {
        switch self {
        case .yearly: return "Best Value"
        case .lifetime: return "One-Time"
        default: return nil
        }
    }

    var isSubscription: Bool {
        self != .lifetime
    }
}

// MARK: - Store Service

@MainActor
class StoreService: ObservableObject {
    static let shared = StoreService()

    static let allProductIDs: Set<String> = Set(ProPlan.allCases.map(\.rawValue))

    @Published var isPro = false
    @Published var activeProPlan: ProPlan?
    @Published var products: [Product] = []
    @Published var isPurchasing = false
    @Published var isLoading = false
    @Published var purchaseError: String?

    private var updateListenerTask: Task<Void, Never>?

    private init() {
        updateListenerTask = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchaseStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Product Accessors

    var monthlyProduct: Product? { products.first { $0.id == ProPlan.monthly.rawValue } }
    var yearlyProduct: Product? { products.first { $0.id == ProPlan.yearly.rawValue } }
    var lifetimeProduct: Product? { products.first { $0.id == ProPlan.lifetime.rawValue } }

    func product(for plan: ProPlan) -> Product? {
        products.first { $0.id == plan.rawValue }
    }

    // MARK: - Product Loading

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: Self.allProductIDs)
            // Sort: yearly, monthly, lifetime
            let order: [ProPlan] = [.yearly, .monthly, .lifetime]
            products = fetched.sorted { a, b in
                let aIdx = order.firstIndex(where: { $0.rawValue == a.id }) ?? 99
                let bIdx = order.firstIndex(where: { $0.rawValue == b.id }) ?? 99
                return aIdx < bIdx
            }
        } catch {
            // Product not available or network error — fail silently
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updatePurchaseStatus()
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    func restore() async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await updatePurchaseStatus()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func manageSubscriptions() {
        purchaseError = nil
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions"),
              NSWorkspace.shared.open(url) else {
            purchaseError = "Could not open subscription management."
            return
        }
    }

    // MARK: - Entitlement Check

    func updatePurchaseStatus() async {
        var foundPro = false
        var foundPlan: ProPlan?
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.allProductIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                foundPro = true
                foundPlan = ProPlan(rawValue: transaction.productID)
                break
            }
        }
        isPro = foundPro
        activeProPlan = foundPlan
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreServiceError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await self?.updatePurchaseStatus()
                    await transaction.finish()
                }
            }
        }
    }
}

// MARK: - Error

enum StoreServiceError: Error {
    case failedVerification
}

#endif
