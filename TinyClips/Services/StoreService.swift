import Foundation

#if APPSTORE
import StoreKit

// MARK: - Store Service

@MainActor
class StoreService: ObservableObject {
    static let shared = StoreService()

    static let proProductID = "com.refractored.tinyclips.pro"

    @Published var isPro = false
    @Published var proProduct: Product?
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

    // MARK: - Product Loading

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
        } catch {
            // Product not available or network error — fail silently
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = proProduct else { return }
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

    // MARK: - Entitlement Check

    func updatePurchaseStatus() async {
        var foundPro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                foundPro = true
                break
            }
        }
        isPro = foundPro
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
