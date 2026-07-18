import GoogleMobileAds
import SwiftUI

@MainActor
enum AdBootstrap {
    private static var didStartSDK = false

    /// Call once after first interactive frame: UMP → Mobile Ads → preload.
    static func startIfNeeded() async {
        guard AdMobConfig.adsEnabled else { return }
        AdProbe.log("bootstrap.start")
        let allowed = await AdConsentManager.gatherConsentIfNeeded()
        guard allowed else {
            AdProbe.log("bootstrap.skip", "canRequestAds=false")
            return
        }
        startMobileAdsIfNeeded()
    }

    private static func startMobileAdsIfNeeded() {
        guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return }
        guard !didStartSDK else {
            AppOpenAdManager.shared.loadAd()
            InterstitialAdManager.shared.loadAd()
            return
        }
        didStartSDK = true
        AdProbe.log("sdk.start")
        MobileAds.shared.start { _ in
            Task { @MainActor in
                AdProbe.log("sdk.ready")
                AppOpenAdManager.shared.loadAd()
                InterstitialAdManager.shared.loadAd()
            }
        }
    }
}

@MainActor
enum AdSceneLifecycle {
    private enum Pending {
        case cold
        case hot
    }

    private static var isColdStart = true
    private static var wasInBackground = false
    private static var backgroundEnteredAt: Date?
    private static var pending: Pending?
    private static var hasPresentedSinceForeground = false
    private static var playStartInterstitialTask: Task<Void, Never>?

    /// Review sheet or similar full-screen UX should block ads.
    static var isAdUIBlocked: Bool {
        ReviewPromptCoordinator.shared.showSheet
    }

    static func handleScenePhase(_ phase: ScenePhase) {
        guard AdMobConfig.adsEnabled else { return }
        switch phase {
        case .active:
            if isColdStart {
                isColdStart = false
                pending = .cold
                hasPresentedSinceForeground = false
                AdProbe.log("lifecycle.cold_armed")
            } else if wasInBackground {
                wasInBackground = false
                let bgSecs = backgroundEnteredAt.map { Date().timeIntervalSince($0) } ?? 0
                backgroundEnteredAt = nil
                hasPresentedSinceForeground = false
                if bgSecs >= AdMobConfig.hotStartMinBackground {
                    pending = .hot
                    AdProbe.log("lifecycle.hot_armed", "bgSecs=\(Int(bgSecs))")
                    attemptPendingPresentation(source: "hot_foreground")
                } else {
                    AdProbe.log("lifecycle.hot_skip", "bgSecs=\(Int(bgSecs))")
                }
            }
        case .background:
            wasInBackground = true
            backgroundEnteredAt = Date()
            pending = nil
            if AdConsentManager.canRequestAds {
                AppOpenAdManager.shared.loadAd()
                InterstitialAdManager.shared.loadAd()
            }
            AdProbe.log("lifecycle.background")
        default:
            break
        }
    }

    /// Tab switch / play request — unlocks cold App Open once per cold start.
    static func recordFirstInteraction(source: String) {
        guard AdMobConfig.adsEnabled else { return }
        AdProbe.log("lifecycle.interaction", source)
        attemptPendingPresentation(source: source)
    }

    private static func attemptPendingPresentation(source: String) {
        guard AdConsentManager.canRequestAds else {
            AdProbe.log("lifecycle.pending.hold", "no consent yet source=\(source)")
            return
        }
        guard !hasPresentedSinceForeground, let p = pending else { return }
        guard !isAdUIBlocked else {
            AdProbe.log("lifecycle.pending.blocked", source)
            return
        }
        pending = nil
        hasPresentedSinceForeground = true
        switch p {
        case .cold:
            _ = AppOpenAdManager.shared.showAdIfAvailable(reason: "cold_\(source)")
        case .hot:
            if AppOpenAdManager.shared.isReady {
                _ = AppOpenAdManager.shared.showAdIfAvailable(reason: "hot_\(source)")
            } else {
                _ = InterstitialAdManager.shared.showIfAppropriate(reason: "hot_\(source)")
            }
        }
    }

    /// After successful play start — delayed interstitial.
    static func schedulePlayStartInterstitial(videoId: String) {
        guard AdMobConfig.adsEnabled else { return }
        playStartInterstitialTask?.cancel()
        let delay = AdMobConfig.playStartInterstitialDelay
        AdProbe.log("play_start.schedule", "id=\(videoId) delay=\(Int(delay))s")
        playStartInterstitialTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard AdConsentManager.canRequestAds else { return }
            _ = InterstitialAdManager.shared.showIfAppropriate(reason: "play_start")
        }
    }

    static func cancelPlayStartInterstitial() {
        playStartInterstitialTask?.cancel()
        playStartInterstitialTask = nil
    }

    static func onPlayerDetailClosed() {
        guard AdMobConfig.adsEnabled else { return }
        AdProbe.log("player_detail.closed")
        _ = InterstitialAdManager.shared.showIfAppropriate(reason: "leave_player")
    }
}

private struct AdSceneLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                AdSceneLifecycle.handleScenePhase(phase)
            }
    }
}

extension View {
    func adSceneLifecycle() -> some View {
        modifier(AdSceneLifecycleModifier())
    }
}
