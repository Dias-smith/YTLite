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
        guard AdEligibility.allowsRewardedAds else { return }
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

    /// Waits for inventory, retrying load until `timeout` elapses.
    func waitUntilReady(timeout: TimeInterval = 12) async -> Bool {
        if isReady { return true }
        guard AdEligibility.allowsRewardedAds else {
            return false
        }

        loadAd()
        let deadline = Date().addingTimeInterval(timeout)
        var lastLoadAttempt = Date()

        while Date() < deadline {
            if Task.isCancelled { return false }
            if isReady { return true }
            if !isLoadingAd, rewardedAd == nil, Date().timeIntervalSince(lastLoadAttempt) >= 2 {
                loadAd()
                lastLoadAttempt = Date()
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return isReady
    }

    /// Loads if needed, then presents. Returns whether presentation started.
    @discardableResult
    func showWhenReady(
        reason: String,
        timeout: TimeInterval = 12,
        completion: @escaping (Bool) -> Void
    ) async -> Bool {
        guard await waitUntilReady(timeout: timeout) else { return false }

        let presentDeadline = Date().addingTimeInterval(5)
        while Date() < presentDeadline {
            if Task.isCancelled { return false }
            if show(reason: reason, completion: completion) {
                return true
            }
            if AdFullScreenCoordinator.isPresenting {
                try? await Task.sleep(nanoseconds: 400_000_000)
                continue
            }
            return false
        }
        return false
    }

    /// Completion runs after dismissal, so rewarded UI never mutates the sheet beneath the ad.
    @discardableResult
    func show(reason: String, completion: @escaping (Bool) -> Void) -> Bool {
        guard AdEligibility.allowsRewardedAds else { return false }
        guard AdSceneLifecycle.isAppActiveForAds else {
            AdProbe.log("rewarded.show.skip", "app_inactive reason=\(reason)")
            return false
        }
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
        AdBootstrap.enforceMutedAds()
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
