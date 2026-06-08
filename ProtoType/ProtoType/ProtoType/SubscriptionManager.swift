import StoreKit
import Foundation

@MainActor
final class SubscriptionManager: Observable {
    static let shared = SubscriptionManager()

    // TEMPORARY: bypass the paywall so the app can be tested before the
    // subscription product is live in App Store Connect. Set back to false
    // (or delete) once the product exists and you want to test purchasing.
    static let bypassPaywallForTesting = true

    // Update this product ID after creating it in App Store Connect
    static let productID = "com.harrykhizer.ProtoType.premium.monthly"

    private(set) var isSubscribed = false
    private(set) var isLoading = false

    private let trialStartKey = "trialStartDate"
    private let trialDays: Double = 3

    private init() {
        Task { await refresh() }
        Task { await listenForTransactions() }
    }

    // MARK: - Trial

    var trialStartDate: Date {
        if let saved = UserDefaults.standard.object(forKey: trialStartKey) as? Date {
            return saved
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: trialStartKey)
        return now
    }

    var trialDaysRemaining: Int {
        let elapsed = Date().timeIntervalSince(trialStartDate) / 86_400
        return max(0, Int(ceil(trialDays - elapsed)))
    }

    var trialExpired: Bool {
        Date().timeIntervalSince(trialStartDate) >= trialDays * 86_400
    }

    var shouldShowPaywall: Bool {
        if Self.bypassPaywallForTesting { return false }
        return !isSubscribed && trialExpired
    }

    // MARK: - Purchase

    func purchase() async throws {
        isLoading = true
        defer { isLoading = false }

        let products = try await Product.products(for: [Self.productID])
        guard let product = products.first else {
            throw SubscriptionError.productNotFound
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            await refresh()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        try? await AppStore.sync()
        await refresh()
    }

    // MARK: - Status

    func refresh() async {
        var subscribed = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? result.payloadValue else { continue }
            if transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                subscribed = true
                break
            }
        }
        isSubscribed = subscribed
        AppGroup.defaults.set(subscribed, forKey: "isSubscribed")
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? result.payloadValue else { continue }
            await transaction.finish()
            await refresh()
        }
    }
}

enum SubscriptionError: LocalizedError {
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Subscription product not found. Please try again later."
        }
    }
}
