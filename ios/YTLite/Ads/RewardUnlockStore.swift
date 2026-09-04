import Foundation
import StoreKit

/// App Store / Play product identifiers (create matching products in App Store Connect / Play Console).
enum VipProductID {
    static let monthly = "youlite.premium.month"
    static let yearly = "youlite.premium.year"
    static let all: [String] = [monthly, yearly]
}

/// StoreKit 2 VIP entitlement. Primary benefit today: ad-free.
@MainActor
final class VipStore: ObservableObject {
    static let shared = VipStore()

    @Published private(set) var isVipActive = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var activeProductID: String?
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published var lastErrorMessage: String?
    @Published private(set) var revision = 0
    /// Per-product intro eligibility (App Store introductory offers).
    @Published private(set) var introEligibleByProductID: [String: Bool] = [:]

    private var transactionListener: Task<Void, Never>?
    private let debugForceKey = "debug_force_vip"

    private init() {
        transactionListener = Task { await listenForTransactions() }
        Task { await refresh() }
    }

    deinit {
        transactionListener?.cancel()
    }

    #if DEBUG
    var debugForceVip: Bool {
        get { UserDefaults.standard.bool(forKey: debugForceKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: debugForceKey)
            applyEntitlementState()
        }
    }
    #endif

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: VipProductID.all)
            products = loaded.sorted { lhs, rhs in
                rank(lhs.id) < rank(rhs.id)
            }
            var eligibility: [String: Bool] = [:]
            for product in products {
                guard let subscription = product.subscription else {
                    eligibility[product.id] = false
                    continue
                }
                // Prefer group-level eligibility (more reliable than the instance property).
                let eligible = await Product.SubscriptionInfo.isEligibleForIntroOffer(
                    for: subscription.subscriptionGroupID
                )
                eligibility[product.id] = eligible
                let intro = subscription.introductoryOffer
                print(
                    "[YTLite.VIP] product=\(product.id) price=\(product.displayPrice) " +
                        "intro=\(intro.map { "\($0.displayPrice)/\($0.paymentMode)" } ?? "nil") " +
                        "eligible=\(eligible)"
                )
            }
            introEligibleByProductID = eligibility
            lastErrorMessage = nil
            revision += 1
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Re-fetch App Store prices / offers whenever the VIP paywall is shown.
    func reloadPricing() async {
        await loadProducts()
        await refresh()
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refresh()
                lastErrorMessage = nil
            case .userCancelled:
                break
            case .pending:
                lastErrorMessage = L("vip.purchase_pending")
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refresh()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        var activeID: String?
        var expiry: Date?
        var active = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard VipProductID.all.contains(transaction.productID) else { continue }
            if let expiration = transaction.expirationDate {
                if expiration > Date() {
                    active = true
                    activeID = transaction.productID
                    expiry = expiration
                }
            } else {
                // Non-expiring entitlement (e.g. non-consumable) if configured later.
                active = true
                activeID = transaction.productID
                expiry = nil
            }
        }

        activeProductID = activeID
        expirationDate = expiry
        #if DEBUG
        isVipActive = active || debugForceVip
        #else
        isVipActive = active
        #endif
        revision += 1
        AdEligibility.refreshInventoryIfEligible()
    }

    private func applyEntitlementState() {
        Task { await refresh() }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await refresh()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func rank(_ id: String) -> Int {
        switch id {
        case VipProductID.yearly: return 0
        case VipProductID.monthly: return 1
        default: return 99
        }
    }

    private enum StoreError: Error {
        case failedVerification
    }
}

/// Local daily entitlements granted only after the rewarded callback fires.
@MainActor
final class RewardUnlockStore: ObservableObject {
    enum Feature: String {
        case editInfo = "edit_info"
        case themes
    }

    static let shared = RewardUnlockStore()

    @Published private(set) var revision = 0

    private init() {}

    func isUnlockedToday(_ feature: Feature) -> Bool {
        if VipStore.shared.isVipActive { return true }
        guard let date = UserDefaults.standard.object(forKey: key(for: feature)) as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(date)
    }

    func unlockToday(_ feature: Feature) {
        UserDefaults.standard.set(Date(), forKey: key(for: feature))
        revision += 1
        AdProbe.log("reward.unlock", "feature=\(feature.rawValue) scope=today")
    }

    private func key(for feature: Feature) -> String {
        "ad_reward_unlock_\(feature.rawValue)_date"
    }
}
