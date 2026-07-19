import GoogleMobileAds
import UIKit

@MainActor
final class RewardedInterstitialAdManager: NSObject {
    static let shared = RewardedInterstitialAdManager()

    private var rewardedAd: RewardedInterstitialAd?
    private var isLoadingAd = false
    private var isShowingAd = false
    private var didEarnReward = false
    private var completion: ((Bool) -> Void)?

    var isReady: Bool { rewardedAd != nil && !isLoadingAd && !isShowingAd }

    func loadAd() {
        guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return }
        guard !AdMobConfig.rewardedInterstitialAdUnitID.isEmpty else {
            AdProbe.log("rewarded.load.skip", "empty_unit_id")
            return
        }
        guard !isLoadingAd, !isShowingAd, rewardedAd == nil else { return }

        isLoadingAd = true
        AdProbe.log("rewarded.load.start")
        RewardedInterstitialAd.load(
            with: AdMobConfig.rewardedInterstitialAdUnitID,
            request: Request()
        ) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingAd = false
                if let error {
                    self.rewardedAd = nil
                    AdProbe.log("rewarded.load.fail", error.localizedDescription)
                    return
                }
                guard let ad else {
                    AdProbe.log("rewarded.load.fail", "nil ad")
                    return
                }
                self.rewardedAd = ad
                ad.fullScreenContentDelegate = self
                AdProbe.log("rewarded.load.ok")
            }
        }
    }

    /// Completion runs after dismissal, so rewarded UI never mutates the sheet beneath the ad.
    @discardableResult
    func show(reason: String, completion: @escaping (Bool) -> Void) -> Bool {
        guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return false }
        guard !isShowingAd, let ad = rewardedAd else {
            AdProbe.log("rewarded.show.miss", "reason=\(reason) → reload")
            loadAd()
            return false
        }
        guard let root = UIApplication.shared.topViewController else {
            AdProbe.log("rewarded.show.fail", "no root VC reason=\(reason)")
            return false
        }
        guard AdFullScreenCoordinator.beginRewarded(reason: reason) else { return false }

        isShowingAd = true
        didEarnReward = false
        self.completion = completion
        AdProbe.log("rewarded.show", "reason=\(reason)")
        ad.present(from: root) { [weak self] in
            Task { @MainActor in
                self?.didEarnReward = true
                AdProbe.log("rewarded.earned", "reason=\(reason)")
            }
        }
        return true
    }

    private func finishPresentation(earned: Bool) {
        let completion = completion
        self.completion = nil
        rewardedAd = nil
        isShowingAd = false
        didEarnReward = false
        AdFullScreenCoordinator.finish(didShowOrdinaryAd: false)
        completion?(earned)
        loadAd()
    }
}

extension RewardedInterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        let earned = didEarnReward
        AdProbe.log("rewarded.dismiss", "earned=\(earned)")
        finishPresentation(earned: earned)
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        AdProbe.log("rewarded.present.fail", error.localizedDescription)
        finishPresentation(earned: false)
    }
}
