#if APPSTORE
import StoreKit
import Foundation

// MARK: - Pro Manager

@MainActor
class ProManager: ObservableObject {
    static let shared = ProManager()

    @Published var isPro: Bool = false
    @Published var proProduct: Product?
    @Published var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
        case restoring
        case error(String)

        var isTransacting: Bool {
            switch self {
            case .loading, .purchasing, .restoring: return true
            default: return false
            }
        }
    }

    private let proProductID = "com.refractored.tinyclips.pro"
    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchaseStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        purchaseState = .loading
        do {
            let products = try await Product.products(for: [proProductID])
            proProduct = products.first
        } catch {
            // Product loading is non-critical; proceed without product info
        }
        if case .loading = purchaseState {
            purchaseState = .idle
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = proProduct else { return }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    isPro = true
                case .unverified(let transaction, _):
                    await transaction.finish()
                    purchaseState = .error("Purchase could not be verified. Please try again.")
                    return
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseState = .error(error.localizedDescription)
            return
        }
        purchaseState = .idle
    }

    func restore() async {
        purchaseState = .restoring
        do {
            try await AppStore.sync()
            await updatePurchaseStatus()
        } catch {
            purchaseState = .error(error.localizedDescription)
            return
        }
        purchaseState = .idle
    }

    // MARK: - Status

    private func updatePurchaseStatus() async {
        var foundEntitlement = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == proProductID,
               transaction.revocationDate == nil {
                foundEntitlement = true
                break
            }
        }
        isPro = foundEntitlement
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    if transaction.productID == proProductID {
                        isPro = true
                    }
                    await transaction.finish()
                }
            }
        }
    }
}
#endif
