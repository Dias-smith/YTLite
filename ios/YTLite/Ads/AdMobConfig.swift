import Foundation

/// AdMob IDs and pacing. Values are injected by Debug / Release xcconfig through Info.plist.
nonisolated enum AdMobConfig {
    static let adsEnabled = true

    static let appID = infoValue("GADApplicationIdentifier")
    static let appOpenAdUnitID = infoValue("YTLiteAdMobAppOpenAdUnitID")
    static let hotInterstitialAdUnitID = infoValue("YTLiteAdMobHotInterstitialAdUnitID")
    static let inAppInterstitialAdUnitID = infoValue("YTLiteAdMobInAppInterstitialAdUnitID")
    static let rewardedInterstitialAdUnitID = infoValue("YTLiteAdMobRewardedInterstitialAdUnitID")

    static let appOpenAdTimeout: TimeInterval = 4 * 60 * 60
    static let interstitialCooldown: TimeInterval = 120
    static let playStartInterstitialDelay: TimeInterval = 20
    static let playStartInterstitialSessionLimit = 2
    static let hotStartMinBackground: TimeInterval = 30
    static let leavePlayerPresentationDelay: TimeInterval = 0.55

    private static func infoValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
