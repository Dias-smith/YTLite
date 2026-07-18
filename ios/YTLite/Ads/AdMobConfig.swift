import Foundation

/// AdMob IDs and pacing. Currently Google **test** App / unit IDs — replace before release.
/// See `ios/ADMOB.md`.
nonisolated enum AdMobConfig {
    static let appID = "ca-app-pub-3940256099942544~1458002511"

    /// Test-ID phase: enabled in Debug and Release for device verification.
    static let adsEnabled = true

    static let appOpenAdUnitID = "ca-app-pub-3940256099942544/5575463023"
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"

    static let appOpenAdTimeout: TimeInterval = 4 * 60 * 60
    static let interstitialCooldown: TimeInterval = 120
    static let playStartInterstitialDelay: TimeInterval = 20
    static let hotStartMinBackground: TimeInterval = 30
}
