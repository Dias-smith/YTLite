import Foundation

/// Library-size gate for AdMob: no load / no present below the threshold.
@MainActor
enum AdEligibility {
    static let minimumLibrarySongCount = 10

    private static weak var libraryStore: LibraryStore?

    static func bind(libraryStore: LibraryStore?) {
        self.libraryStore = libraryStore
        refreshInventoryIfEligible()
    }

    static var librarySongCount: Int {
        libraryStore?.librarySongs().count ?? 0
    }

    /// Whether ads may be requested or shown.
    static var allowsAds: Bool {
        guard AdMobConfig.adsEnabled else { return false }
        return librarySongCount >= minimumLibrarySongCount
    }

    /// Call after library sync / local mutations that may cross the threshold.
    static func refreshInventoryIfEligible() {
        let count = librarySongCount
        guard allowsAds else {
            AdProbe.log(
                "eligibility.block",
                "songs=\(count) need=\(minimumLibrarySongCount)"
            )
            return
        }
        guard AdConsentManager.canRequestAds else {
            AdProbe.log("eligibility.hold", "songs=\(count) waiting_consent")
            return
        }
        AdProbe.log("eligibility.ok", "songs=\(count)")
        AppOpenAdManager.shared.loadAd()
        InterstitialAdManager.loadAll()
        RewardedInterstitialAdManager.shared.loadAd()
    }
}
