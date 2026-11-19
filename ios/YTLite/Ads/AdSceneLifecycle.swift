import GoogleMobileAds
import SwiftUI
import UIKit

@MainActor
enum AdBootstrap {
    private static var didStartSDK = false

    /// All AdMob formats (app open / interstitial / rewarded) stay muted by default.
    static func enforceMutedAds() {
        guard AdMobConfig.adsEnabled else { return }
        MobileAds.shared.isApplicationMuted = true
    }

    /// Call once after first interactive frame: UMP → Mobile Ads → preload.
    static func startIfNeeded() async {
        guard AdMobConfig.adsEnabled else { return }
        enforceMutedAds()
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
        enforceMutedAds()
        guard !didStartSDK else {
            AdEligibility.refreshInventoryIfEligible()
            AdSceneLifecycle.adEnvironmentDidBecomeReady(source: "sdk_already_started")
            return
        }
        didStartSDK = true
        AdProbe.log("sdk.start")
        MobileAds.shared.start { _ in
            Task { @MainActor in
                AdProbe.log("sdk.ready")
                AdEligibility.refreshInventoryIfEligible()
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
    private static var isAppActive = true

    /// Ads must not present while backgrounded — it interrupts AVAudioSession and breaks review checks.
    static var isAppActiveForAds: Bool { isAppActive }

    /// Player, consent, or another sheet is up. Launch sheets are tracked separately.
    static var hasBlockingForegroundUI: Bool {
        if ReviewPromptCoordinator.shared.showSheet { return true }
        return !uiBlockers.isEmpty
    }

    /// Ordinary ads wait until sheets / full-screen UX have closed.
    static func isAdUIBlocked(for reason: String? = nil) -> Bool {
        if ReviewPromptCoordinator.shared.showSheet { return true }
        // Avoid ads over first-launch locale / feature intro sheets.
        if LaunchSheetGate.isBlocking { return true }
        var blockers = uiBlockers
        if reason == "play_start" {
            blockers.remove("player_detail")
        }
        return !blockers.isEmpty
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
        isAppActive = phase == .active
        if phase == .background {
            ColdStartVipOffer.shared.noteColdLaunchEnded()
        }
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
                AdEligibility.refreshInventoryIfEligible()
            }
            AdProbe.log("lifecycle.background")
        default:
            break
        }
    }

    /// Tab switch unlocks cold App Open once per cold start.
    /// Play taps open the player sheet immediately — do not stack a full-screen ad on top.
    static func recordFirstInteraction(source: String) {
        guard AdMobConfig.adsEnabled else { return }
        hasColdStartInteraction = true
        AdProbe.log("lifecycle.interaction", source)
        if source == "play_request" {
            if pending == .cold {
                pending = nil
                AdProbe.log("lifecycle.cold_skip", "reason=play_request")
            }
            return
        }
        attemptPendingPresentation(source: source)
    }

    /// Consent, inventory, UI, or another full-screen ad became ready.
    static func adEnvironmentDidBecomeReady(source: String) {
        ColdStartVipOffer.shared.consider()
        attemptPendingPresentation(source: source)
    }

    private static func attemptPendingPresentation(source: String) {
        guard isAppActive else {
            AdProbe.log("lifecycle.pending.hold", "app_inactive source=\(source)")
            return
        }
        guard AdEligibility.allowsAds else {
            AdProbe.log(
                "lifecycle.pending.hold",
                "library_songs=\(AdEligibility.librarySongCount) need=\(AdEligibility.minimumLibrarySongCount) source=\(source)"
            )
            AppAnalytics.adSkipOrBlock(reason: "library_threshold")
            return
        }
        guard AdConsentManager.canRequestAds else {
            AdProbe.log("lifecycle.pending.hold", "no consent yet source=\(source)")
            AppAnalytics.adSkipOrBlock(reason: "consent")
            return
        }
        guard !hasPresentedSinceForeground, let p = pending else { return }
        if case .cold = p, !hasColdStartInteraction {
            AdProbe.log("lifecycle.pending.hold", "awaiting interaction source=\(source)")
            return
        }
        guard !isAdUIBlocked(for: nil) else {
            AdProbe.log("lifecycle.pending.blocked", source)
            return
        }
        if case .cold = p, ColdStartVipOffer.shared.holdsColdAd {
            AdProbe.log("lifecycle.pending.hold", "cold_vip source=\(source)")
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

    /// Song tap → full-screen player → muted interstitial after a short delay (from tap, not resolve).
    static func schedulePlayStartInterstitial(videoId: String) {
        guard AdMobConfig.adsEnabled else { return }
        guard AdEligibility.allowsAds else {
            AdProbe.log(
                "play_start.skip",
                "library_songs=\(AdEligibility.librarySongCount) need=\(AdEligibility.minimumLibrarySongCount)"
            )
            return
        }
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
            guard isAppActive else {
                AdProbe.log("play_start.skip", "app_inactive")
                return
            }
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
        guard AdEligibility.allowsAds else {
            AdProbe.log(
                "player_detail.closed.skip_ad",
                "library_songs=\(AdEligibility.librarySongCount)"
            )
            return
        }
        AdProbe.log("player_detail.closed")
        leavePlayerInterstitialTask?.cancel()
        leavePlayerInterstitialTask = Task {
            let delay = AdMobConfig.leavePlayerPresentationDelay
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard isAppActive else {
                AdProbe.log("player_detail.closed.skip_ad", "app_inactive")
                return
            }
            _ = InterstitialAdManager.inApp.showIfAppropriate(reason: "leave_player")
        }
    }

    static func onSearchResultsPresented(query: String) {
        guard AdMobConfig.adsEnabled else { return }
        guard AdEligibility.allowsAds else {
            AdProbe.log(
                "search_results.skip_ad",
                "library_songs=\(AdEligibility.librarySongCount)"
            )
            return
        }
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
    /// Compact: sheet with system pull-to-dismiss (grabber hidden). Regular: fullScreenCover + canvas swipe.
    func playerDetailPresentation(isPresented: Binding<Bool>) -> some View {
        modifier(PlayerDetailPresentationModifier(isPresented: isPresented))
    }

    /// Backward-compatible alias — prefer `playerDetailPresentation` at the app chrome host.
    func playerDetailSheet(isPresented: Binding<Bool>) -> some View {
        playerDetailPresentation(isPresented: isPresented)
    }
}

/// Cold start: library has more than 5 saved songs → VIP paywall, then the cold ad.
@MainActor
final class ColdStartVipOffer: ObservableObject {
    static let shared = ColdStartVipOffer()
    /// Show when the saved library is strictly larger than this.
    static let songThreshold = 5

    @Published var isPresented = false

    private var coldLaunchOpen = true
    private var didDecide = false
    private var didSchedulePostDismissAd = false

    /// Cold app-open stays queued until this launch decides to show or skip the paywall.
    var holdsColdAd: Bool {
        isPresented || (coldLaunchOpen && !didDecide)
    }
    private var isConsidering = false
    private var libraryReady = false
    private var sessionResolved = false
    private var awaitingInitialSync = true
    private var initialSyncFinished = false
    private var launchFlowReady = false
    private var songCount = 0

    private init() {}

    func updateLibrary(count: Int, sessionResolved: Bool, isAuthenticated: Bool) {
        songCount = count
        libraryReady = true
        self.sessionResolved = sessionResolved
        if sessionResolved {
            awaitingInitialSync = isAuthenticated && !initialSyncFinished
        } else {
            awaitingInitialSync = true
        }
        consider()
    }

    func noteInitialSyncFinished(count: Int) {
        songCount = count
        libraryReady = true
        sessionResolved = true
        initialSyncFinished = true
        awaitingInitialSync = false
        consider()
    }

    /// ATT / UMP for this launch have finished, so the paywall is not stacked on them.
    func noteLaunchFlowReady() {
        launchFlowReady = true
        consider()
    }

    /// Background ends the cold-start window. A paywall already on screen stays up.
    func noteColdLaunchEnded() {
        coldLaunchOpen = false
        guard !isPresented else { return }
        finishWithoutPaywall()
    }

    func consider() {
        guard !isConsidering else { return }
        isConsidering = true
        defer { isConsidering = false }
        guard coldLaunchOpen, !didDecide else { return }
        guard libraryReady, sessionResolved, !awaitingInitialSync else { return }
        guard launchFlowReady, VipStore.shared.hasResolvedEntitlement else { return }
        guard !LaunchSheetGate.locale, !LaunchSheetGate.featureIntro else { return }
        guard !AdSceneLifecycle.hasBlockingForegroundUI else { return }
        if VipStore.shared.isVipActive || songCount <= Self.songThreshold {
            finishWithoutPaywall()
            return
        }
        didDecide = true
        LaunchSheetGate.vip = true
        isPresented = true
        AdProbe.log("cold_vip.present", "songs=\(songCount)")
    }

    /// Cover dismiss has finished. Presenting sooner attaches the ad to the
    /// disappearing cover, so the ad is torn down with it.
    func paywallDidFinishDismissing() {
        guard !didSchedulePostDismissAd else { return }
        didSchedulePostDismissAd = true
        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(AdMobConfig.leavePlayerPresentationDelay * 1_000_000_000)
            )
            LaunchSheetGate.vip = false
            AdSceneLifecycle.adEnvironmentDidBecomeReady(source: "cold_vip_dismissed")
        }
    }

    private func finishWithoutPaywall() {
        guard !didDecide else { return }
        didDecide = true
        AdProbe.log(
            "cold_vip.skip",
            "songs=\(songCount) vip=\(VipStore.shared.isVipActive)"
        )
        AdSceneLifecycle.adEnvironmentDidBecomeReady(source: "cold_vip_skipped")
    }
}

private struct PlayerDetailPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Compact width: sheet. Regular width: immersive full screen.
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
                // Hide the grabber (easy to hit under Sleep Timer / EQ sheets) but keep
                // system pull-to-dismiss — custom canvas-only swipe was too hard to trigger.
                .presentationDragIndicator(.hidden)
                .presentationContentInteraction(.scrolls)
            }
            // Regular width: immersive full screen; swipe down on the
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
