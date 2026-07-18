import GoogleMobileAds
import UIKit

@MainActor
final class InterstitialAdManager: NSObject {
    static let shared = InterstitialAdManager()

    private var interstitial: InterstitialAd?
    private var isShowingAd = false
    private var isLoadingAd = false
    private var lastShownAt: Date?

    var isReady: Bool { interstitial != nil && !isShowingAd }

    private var cooldownRemaining: TimeInterval {
        guard let lastShownAt else { return 0 }
        let elapsed = Date().timeIntervalSince(lastShownAt)
        return max(0, AdMobConfig.interstitialCooldown - elapsed)
    }

    func loadAd() {
        guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return }
        guard !isLoadingAd, !isShowingAd else { return }
        if interstitial != nil { return }
        isLoadingAd = true
        AdProbe.log("interstitial.load.start")

        InterstitialAd.load(
            with: AdMobConfig.interstitialAdUnitID,
            request: Request()
        ) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingAd = false
                if let error {
                    AdProbe.log("interstitial.load.fail", error.localizedDescription)
                    self.interstitial = nil
                    return
                }
                guard let ad else {
                    AdProbe.log("interstitial.load.fail", "nil ad")
                    return
                }
                self.interstitial = ad
                ad.fullScreenContentDelegate = self
                AdProbe.log("interstitial.load.ok")
            }
        }
    }

    @discardableResult
    func showIfAppropriate(reason: String) -> Bool {
        guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return false }
        guard !AdSceneLifecycle.isAdUIBlocked else {
            AdProbe.log("interstitial.show.skip", "ui_blocked reason=\(reason)")
            return false
        }
        let remaining = cooldownRemaining
        guard remaining <= 0 else {
            AdProbe.log(
                "interstitial.show.skip",
                "cooldown remaining=\(Int(remaining))s reason=\(reason)"
            )
            return false
        }
        guard !isShowingAd else { return false }
        guard let ad = interstitial else {
            AdProbe.log("interstitial.show.miss", "reason=\(reason) → reload")
            loadAd()
            return false
        }
        guard let root = UIApplication.shared.topViewController else {
            AdProbe.log("interstitial.show.fail", "no root VC")
            return false
        }
        isShowingAd = true
        AdProbe.log("interstitial.show", "reason=\(reason)")
        ad.present(from: root)
        return true
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        interstitial = nil
        isShowingAd = false
        lastShownAt = Date()
        AdProbe.log("interstitial.dismiss")
        loadAd()
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        interstitial = nil
        isShowingAd = false
        AdProbe.log("interstitial.present.fail", error.localizedDescription)
        loadAd()
    }
}
