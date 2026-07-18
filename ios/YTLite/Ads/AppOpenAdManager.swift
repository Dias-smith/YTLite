import GoogleMobileAds
import UIKit

@MainActor
final class AppOpenAdManager: NSObject {
    static let shared = AppOpenAdManager()

    private var appOpenAd: AppOpenAd?
    private var loadTime: Date?
    private var isShowingAd = false
    private var isLoadingAd = false

    var isReady: Bool {
        appOpenAd != nil && !isAdExpired
    }

    private var isAdExpired: Bool {
        guard let loadTime else { return true }
        return Date().timeIntervalSince(loadTime) > AdMobConfig.appOpenAdTimeout
    }

    func loadAd() {
        guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return }
        guard !isLoadingAd, !isShowingAd else { return }
        if isReady { return }
        isLoadingAd = true
        AdProbe.log("app_open.load.start")

        AppOpenAd.load(with: AdMobConfig.appOpenAdUnitID, request: Request()) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingAd = false
                if let error {
                    AdProbe.log("app_open.load.fail", error.localizedDescription)
                    self.appOpenAd = nil
                    self.loadTime = nil
                    return
                }
                guard let ad else {
                    AdProbe.log("app_open.load.fail", "nil ad")
                    return
                }
                self.appOpenAd = ad
                self.loadTime = Date()
                ad.fullScreenContentDelegate = self
                AdProbe.log("app_open.load.ok")
            }
        }
    }

    @discardableResult
    func showAdIfAvailable(reason: String) -> Bool {
        guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return false }
        guard !AdSceneLifecycle.isAdUIBlocked else {
            AdProbe.log("app_open.show.skip", "ui_blocked reason=\(reason)")
            return false
        }
        guard !isShowingAd else { return false }
        guard let ad = appOpenAd, !isAdExpired else {
            AdProbe.log("app_open.show.miss", "reason=\(reason) → reload")
            loadAd()
            return false
        }
        guard let root = UIApplication.shared.topViewController else {
            AdProbe.log("app_open.show.fail", "no root VC")
            return false
        }
        isShowingAd = true
        AdProbe.log("app_open.show", "reason=\(reason)")
        ad.present(from: root)
        return true
    }
}

extension AppOpenAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        appOpenAd = nil
        isShowingAd = false
        AdProbe.log("app_open.dismiss")
        loadAd()
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        appOpenAd = nil
        isShowingAd = false
        AdProbe.log("app_open.present.fail", error.localizedDescription)
        loadAd()
    }
}
