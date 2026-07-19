import GoogleMobileAds
import UIKit

@MainActor
final class InterstitialAdManager: NSObject {
    enum Placement: String {
        case hot
        case inApp = "in_app"

        var adUnitID: String {
            switch self {
            case .hot: AdMobConfig.hotInterstitialAdUnitID
            case .inApp: AdMobConfig.inAppInterstitialAdUnitID
            }
        }
    }

    static let hot = InterstitialAdManager(placement: .hot)
    static let inApp = InterstitialAdManager(placement: .inApp)

    private let placement: Placement
    private var interstitial: InterstitialAd?
    private var isShowingAd = false
    private var isLoadingAd = false

    var isReady: Bool { interstitial != nil && !isShowingAd }

    private init(placement: Placement) {
        self.placement = placement
        super.init()
    }

    static func loadAll() {
        hot.loadAd()
        inApp.loadAd()
    }

    func loadAd() {
        guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return }
        guard !isLoadingAd, !isShowingAd else { return }
        guard !placement.adUnitID.isEmpty else {
            AdProbe.log("interstitial.load.skip", "placement=\(placement.rawValue) empty_unit_id")
            return
        }
        if interstitial != nil { return }
        isLoadingAd = true
        AdProbe.log("interstitial.load.start", "placement=\(placement.rawValue)")

        InterstitialAd.load(
            with: placement.adUnitID,
            request: Request()
        ) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingAd = false
                if let error {
                    AdProbe.log(
                        "interstitial.load.fail",
                        "placement=\(self.placement.rawValue) \(error.localizedDescription)"
                    )
                    self.interstitial = nil
                    return
                }
                guard let ad else {
                    AdProbe.log(
                        "interstitial.load.fail",
                        "placement=\(self.placement.rawValue) nil ad"
                    )
                    return
                }
                self.interstitial = ad
                ad.fullScreenContentDelegate = self
                AdProbe.log("interstitial.load.ok", "placement=\(self.placement.rawValue)")
                AdSceneLifecycle.adEnvironmentDidBecomeReady(
                    source: "interstitial_\(self.placement.rawValue)_loaded"
                )
            }
        }
    }

    @discardableResult
    func showIfAppropriate(reason: String) -> Bool {
        guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return false }
        guard !AdSceneLifecycle.isAdUIBlocked else {
            AdProbe.log(
                "interstitial.show.skip",
                "placement=\(placement.rawValue) ui_blocked reason=\(reason)"
            )
            return false
        }
        guard !isShowingAd else { return false }
        guard let ad = interstitial else {
            AdProbe.log(
                "interstitial.show.miss",
                "placement=\(placement.rawValue) reason=\(reason) → reload"
            )
            loadAd()
            return false
        }
        guard let root = UIApplication.shared.topViewController else {
            AdProbe.log("interstitial.show.fail", "no root VC")
            return false
        }
        guard AdFullScreenCoordinator.beginOrdinary(reason: reason) else { return false }
        isShowingAd = true
        AdProbe.log(
            "interstitial.show",
            "placement=\(placement.rawValue) reason=\(reason)"
        )
        ad.present(from: root)
        return true
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        interstitial = nil
        isShowingAd = false
        AdProbe.log("interstitial.dismiss", "placement=\(placement.rawValue)")
        AdFullScreenCoordinator.finish(didShowOrdinaryAd: true)
        loadAd()
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        interstitial = nil
        isShowingAd = false
        AdProbe.log(
            "interstitial.present.fail",
            "placement=\(placement.rawValue) \(error.localizedDescription)"
        )
        AdFullScreenCoordinator.finish(didShowOrdinaryAd: false)
        loadAd()
    }
}
