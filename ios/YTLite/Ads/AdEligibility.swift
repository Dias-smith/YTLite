import Foundation

/// Library-size gate for AdMob: no load / no present below the threshold (successful plays only).
@MainActor
enum AdEligibility {
    static let minimumLibrarySongCount = 10

    private static weak var libraryStore: LibraryStore?

    static func bind(libraryStore: LibraryStore?) {
        self.libraryStore = libraryStore
        refreshInventoryIfEligible()
    }

    static var librarySongCount: Int {
        libraryStore?.successfullyPlayedSongCount() ?? 0
    }

    /// Whether ordinary full-screen ads (app open / interstitial) may load or show.
    static var allowsAds: Bool {
        guard AdMobConfig.adsEnabled else { return false }
        return librarySongCount >= minimumLibrarySongCount
    }

    /// Rewarded unlock ads (theme / edit info) — not gated on library size.
    static var allowsRewardedAds: Bool {
        AdMobConfig.adsEnabled && AdConsentManager.canRequestAds
    }

    /// Call after library sync / local mutations that may cross the threshold.
    static func refreshInventoryIfEligible() {
        refreshRewardedInventoryIfEligible()
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
    }

    static func refreshRewardedInventoryIfEligible() {
        guard allowsRewardedAds else {
            AdProbe.log("eligibility.rewarded.hold", "ads_disabled_or_no_consent")
            return
        }
        AdProbe.log("eligibility.rewarded.ok")
        RewardedInterstitialAdManager.shared.loadAd()
    }
}
