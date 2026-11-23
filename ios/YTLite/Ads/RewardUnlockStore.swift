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
    /// First entitlement read of this process has finished.
    @Published private(set) var hasResolvedEntitlement = false
    /// Per-product intro eligibility (App Store introductory offers).
    @Published private(set) var introEligibleByProductID: [String: Bool] = [:]

    private var transactionListener: Task<Void, Never>?
    private let debugForceKey = "debug_force_vip"
    private var lastLoggedStatusKey: String?

    private init() {
        VipProbe.log("init")
        #if targetEnvironment(macCatalyst)
        // Website DMG Mac build: all VIP features unlocked; no StoreKit / ads.
        isVipActive = true
        hasResolvedEntitlement = true
        VipProbe.log("init.mac", "vip_forced=1 ads=off")
        #else
        transactionListener = Task { await listenForTransactions() }
        Task { await refresh() }
        #endif
    }

    deinit {
        transactionListener?.cancel()
    }

    #if DEBUG
    var debugForceVip: Bool {
        get { UserDefaults.standard.bool(forKey: debugForceKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: debugForceKey)
            VipProbe.log("debug_force", "enabled=\(newValue)")
            applyEntitlementState()
        }
    }
    #endif

    func loadProducts() async {
        #if targetEnvironment(macCatalyst)
        products = []
        return
        #endif
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        VipProbe.log("products.load.start", "ids=\(VipProductID.all.joined(separator: ","))")
        do {
            let loaded = try await Product.products(for: VipProductID.all)
            products = loaded.sorted { lhs, rhs in
                rank(lhs.id) < rank(rhs.id)
            }
            var eligibility: [String: Bool] = [:]
            for product in products {
                guard let subscription = product.subscription else {
                    eligibility[product.id] = false
                    VipProbe.log(
                        "products.item",
                        "id=\(product.id) price=\(product.displayPrice) subscription=nil"
                    )
                    continue
                }
                // Prefer group-level eligibility (more reliable than the instance property).
                let eligible = await Product.SubscriptionInfo.isEligibleForIntroOffer(
                    for: subscription.subscriptionGroupID
                )
                eligibility[product.id] = eligible
                let intro = subscription.introductoryOffer
                VipProbe.log(
                    "products.item",
                    "id=\(product.id) price=\(product.displayPrice) " +
                        "intro=\(intro.map { "\($0.displayPrice)/\($0.paymentMode)" } ?? "nil") " +
                        "eligible=\(eligible)"
                )
            }
            introEligibleByProductID = eligibility
            lastErrorMessage = nil
            revision += 1
            let missing = VipProductID.all.filter { id in !products.contains(where: { $0.id == id }) }
            VipProbe.log(
                "products.load.ok",
                "count=\(products.count)" +
                    (missing.isEmpty ? "" : " missing=\(missing.joined(separator: ","))")
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            VipProbe.log("products.load.fail", error.localizedDescription)
        }
    }

    /// Re-fetch App Store prices / offers whenever the VIP paywall is shown.
    func reloadPricing() async {
        VipProbe.log("paywall.open")
        AppAnalytics.vipPaywallOpen()
        await loadProducts()
        await refresh()
    }

    func purchase(_ product: Product) async {
        #if targetEnvironment(macCatalyst)
        return
        #endif
        isPurchasing = true
        defer { isPurchasing = false }
        VipProbe.log("purchase.start", "product=\(product.id)")
        AppAnalytics.vipPurchaseStart(productId: product.id)
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                VipProbe.log(
                    "purchase.success",
                    "product=\(transaction.productID) " +
                        "expires=\(transaction.expirationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "nil")"
                )
                AppAnalytics.vipPurchaseSuccess(productId: transaction.productID)
                await transaction.finish()
                await refresh()
                lastErrorMessage = nil
            case .userCancelled:
                VipProbe.log("purchase.cancel", "product=\(product.id)")
                AppAnalytics.vipPurchaseCancel(productId: product.id)
            case .pending:
                lastErrorMessage = L("vip.purchase_pending")
                VipProbe.log("purchase.pending", "product=\(product.id)")
                AppAnalytics.vipPurchasePending(productId: product.id)
            @unknown default:
                VipProbe.log("purchase.unknown", "product=\(product.id)")
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            VipProbe.log("purchase.fail", "product=\(product.id) error=\(error.localizedDescription)")
            AppAnalytics.vipPurchaseFail(productId: product.id, error: error.localizedDescription)
        }
    }

    func restorePurchases() async {
        #if targetEnvironment(macCatalyst)
        isVipActive = true
        hasResolvedEntitlement = true
        return
        #endif
        isPurchasing = true
        defer { isPurchasing = false }
        VipProbe.log("restore.start")
        do {
            try await AppStore.sync()
            await refresh()
            lastErrorMessage = nil
            VipProbe.log(
                "restore.ok",
                "active=\(isVipActive) product=\(activeProductID ?? "nil")"
            )
            AppAnalytics.vipRestore(ok: true)
        } catch {
            lastErrorMessage = error.localizedDescription
            VipProbe.log("restore.fail", error.localizedDescription)
            AppAnalytics.vipRestore(ok: false, error: error.localizedDescription)
        }
    }

    func refresh() async {
        #if targetEnvironment(macCatalyst)
        isVipActive = true
        hasResolvedEntitlement = true
        activeProductID = nil
        expirationDate = nil
        revision += 1
        VipProbe.log("entitlement.refresh.ok", "mac_forced_vip=1")
        return
        #endif
        VipProbe.log("entitlement.refresh.start")
        var activeID: String?
        var expiry: Date?
        var active = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                VipProbe.log("entitlement.skip", "unverified")
                continue
            }
            guard VipProductID.all.contains(transaction.productID) else { continue }
            if let expiration = transaction.expirationDate {
                if expiration > Date() {
                    active = true
                    activeID = transaction.productID
                    expiry = expiration
                } else {
                    VipProbe.log(
                        "entitlement.expired",
                        "product=\(transaction.productID) " +
                            "at=\(ISO8601DateFormatter().string(from: expiration))"
                    )
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
        let forced = debugForceVip
        isVipActive = active || forced
        #else
        let forced = false
        isVipActive = active
        #endif
        revision += 1
        let statusKey =
            "\(isVipActive)|\(activeID ?? "-")|\(expiry.map { Int($0.timeIntervalSince1970) } ?? 0)|forced=\(forced)"
        if statusKey != lastLoggedStatusKey {
            lastLoggedStatusKey = statusKey
            VipProbe.log(
                "entitlement.refresh.ok",
                "active=\(isVipActive) product=\(activeID ?? "nil") " +
                    "expires=\(expiry.map { ISO8601DateFormatter().string(from: $0) } ?? "nil")" +
                    (forced ? " debugForce=1" : "")
            )
            AppAnalytics.vipStatus(active: isVipActive, productId: activeID)
        } else {
            VipProbe.log("entitlement.refresh.ok", "unchanged active=\(isVipActive)")
        }
        hasResolvedEntitlement = true
        AdEligibility.refreshInventoryIfEligible()
        // VIP → free: start ads SDK if it was skipped at launch.
        if !isVipActive {
            Task { await AdBootstrap.startIfNeeded() }
        }
        ColdStartVipOffer.shared.consider()
    }

    private func applyEntitlementState() {
        Task { await refresh() }
    }

    private func listenForTransactions() async {
        VipProbe.log("transactions.listen")
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else {
                VipProbe.log("transactions.update", "unverified")
                continue
            }
            VipProbe.log(
                "transactions.update",
                "product=\(transaction.productID) " +
                    "expires=\(transaction.expirationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "nil")"
            )
            await transaction.finish()
            await refresh()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            VipProbe.log("verification.fail")
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
