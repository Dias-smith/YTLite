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
            InterstitialAdManager.loadAll()
            RewardedInterstitialAdManager.shared.loadAd()
            AdSceneLifecycle.adEnvironmentDidBecomeReady(source: "sdk_already_started")
            return
        }
        didStartSDK = true
        AdProbe.log("sdk.start")
        // Default ads muted so interstitial / app-open audio does not blast over playback.
        MobileAds.shared.isApplicationMuted = true
        MobileAds.shared.start { _ in
            Task { @MainActor in
                AdProbe.log("sdk.ready")
                AppOpenAdManager.shared.loadAd()
                InterstitialAdManager.loadAll()
                RewardedInterstitialAdManager.shared.loadAd()
                AdSceneLifecycle.adEnvironmentDidBecomeReady(source: "sdk_ready")
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
    private static var hasColdStartInteraction = false
    private static var playStartInterstitialTask: Task<Void, Never>?
    private static var leavePlayerInterstitialTask: Task<Void, Never>?
    private static var playStartInterstitialsShownThisSession = 0
    private static var uiBlockers: Set<String> = []

    /// Ordinary ads wait until sheets / full-screen UX have closed.
    static var isAdUIBlocked: Bool {
        ReviewPromptCoordinator.shared.showSheet || !uiBlockers.isEmpty
    }

    static func setUIBlocked(_ key: String, blocked: Bool) {
        if blocked {
            uiBlockers.insert(key)
        } else {
            uiBlockers.remove(key)
            adEnvironmentDidBecomeReady(source: "ui_unblocked_\(key)")
        }
    }

    static func handleScenePhase(_ phase: ScenePhase) {
        guard AdMobConfig.adsEnabled else { return }
        switch phase {
        case .active:
            if isColdStart {
                isColdStart = false
                pending = .cold
                hasPresentedSinceForeground = false
                hasColdStartInteraction = false
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
                InterstitialAdManager.loadAll()
                RewardedInterstitialAdManager.shared.loadAd()
            }
            AdProbe.log("lifecycle.background")
        default:
            break
        }
    }

    /// Tab switch / play request — unlocks cold App Open once per cold start.
    static func recordFirstInteraction(source: String) {
        guard AdMobConfig.adsEnabled else { return }
        hasColdStartInteraction = true
        AdProbe.log("lifecycle.interaction", source)
        attemptPendingPresentation(source: source)
    }

    /// Consent, inventory, UI, or another full-screen ad became ready.
    static func adEnvironmentDidBecomeReady(source: String) {
        attemptPendingPresentation(source: source)
    }

    private static func attemptPendingPresentation(source: String) {
        guard AdConsentManager.canRequestAds else {
            AdProbe.log("lifecycle.pending.hold", "no consent yet source=\(source)")
            return
        }
        guard !hasPresentedSinceForeground, let p = pending else { return }
        if case .cold = p, !hasColdStartInteraction {
            AdProbe.log("lifecycle.pending.hold", "awaiting interaction source=\(source)")
            return
        }
        guard !isAdUIBlocked else {
            AdProbe.log("lifecycle.pending.blocked", source)
            return
        }
        let didPresent: Bool
        switch p {
        case .cold:
            didPresent = AppOpenAdManager.shared.showAdIfAvailable(reason: "cold_\(source)")
        case .hot:
            if AppOpenAdManager.shared.isReady {
                didPresent = AppOpenAdManager.shared.showAdIfAvailable(reason: "hot_\(source)")
            } else {
                didPresent = InterstitialAdManager.hot.showIfAppropriate(
                    reason: "hot_\(source)"
                )
            }
        }
        if didPresent {
            pending = nil
            hasPresentedSinceForeground = true
        } else {
            AdProbe.log("lifecycle.pending.retain", "source=\(source)")
        }
    }

    /// After successful play start — delayed interstitial.
    static func schedulePlayStartInterstitial(videoId: String) {
        guard AdMobConfig.adsEnabled else { return }
        guard playStartInterstitialsShownThisSession
            < AdMobConfig.playStartInterstitialSessionLimit
        else {
            AdProbe.log("play_start.skip", "session_limit")
            return
        }
        playStartInterstitialTask?.cancel()
        let delay = AdMobConfig.playStartInterstitialDelay
        AdProbe.log("play_start.schedule", "id=\(videoId) delay=\(Int(delay))s")
        playStartInterstitialTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard AdConsentManager.canRequestAds else { return }
            if InterstitialAdManager.inApp.showIfAppropriate(reason: "play_start") {
                playStartInterstitialsShownThisSession += 1
            }
        }
    }

    static func cancelPlayStartInterstitial() {
        playStartInterstitialTask?.cancel()
        playStartInterstitialTask = nil
    }

    static func onPlayerDetailClosed() {
        guard AdMobConfig.adsEnabled else { return }
        AdProbe.log("player_detail.closed")
        leavePlayerInterstitialTask?.cancel()
        leavePlayerInterstitialTask = Task {
            let delay = AdMobConfig.leavePlayerPresentationDelay
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            _ = InterstitialAdManager.inApp.showIfAppropriate(reason: "leave_player")
        }
    }

    static func onSearchResultsPresented(query: String) {
        guard AdMobConfig.adsEnabled else { return }
        AdProbe.log("search_results.presented", "queryLen=\(query.count)")
        _ = InterstitialAdManager.inApp.showIfAppropriate(reason: "search_results")
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

    /// Single entry for PlayerDetail presentation so leave_player covers swipe + button dismiss.
    /// Always a sheet (not fullScreenCover) so pull-down returns to the mini player on iPhone and iPad.
    func playerDetailPresentation(isPresented: Binding<Bool>) -> some View {
        modifier(PlayerDetailPresentationModifier(isPresented: isPresented))
    }

    /// Backward-compatible alias — prefer `playerDetailPresentation` at the app chrome host.
    func playerDetailSheet(isPresented: Binding<Bool>) -> some View {
        playerDetailPresentation(isPresented: isPresented)
    }
}

private struct PlayerDetailPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var useFullScreen: Bool {
        YTLiteAdaptive.isRegularWidth(horizontalSizeClass)
    }

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { !useFullScreen && isPresented },
                    set: { newValue in
                        if !useFullScreen { isPresented = newValue }
                    }
                ),
                onDismiss: { AdSceneLifecycle.onPlayerDetailClosed() }
            ) {
                NavigationStack {
                    PlayerDetailView()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
            }
            // Regular width (iPad): immersive full screen; swipe down on the
            // canvas or the chevron dismisses back to the mini player.
            .fullScreenCover(
                isPresented: Binding(
                    get: { useFullScreen && isPresented },
                    set: { newValue in
                        if useFullScreen { isPresented = newValue }
                    }
                ),
                onDismiss: { AdSceneLifecycle.onPlayerDetailClosed() }
            ) {
                NavigationStack {
                    PlayerDetailView()
                }
            }
    }
}
