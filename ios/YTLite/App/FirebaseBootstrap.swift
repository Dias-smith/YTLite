import Foundation
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import FirebaseRemoteConfig

/// Product analytics (Firebase). Keeps event names stable; DEBUG also prints to Console.
enum AppAnalytics {
    private static var pendingSignInSource = "unknown"
    private static var lastAdEligibilityKey: String?
    private static var didLogColdOpen = false
    private static var lastAppOpenAt: Date?

    static func log(_ name: String, _ params: [String: Any] = [:]) {
        var sanitized: [String: Any] = [:]
        for (key, value) in params {
            switch value {
            case let s as String:
                sanitized[key] = String(s.prefix(100))
            case let i as Int:
                sanitized[key] = i
            case let b as Bool:
                sanitized[key] = b ? 1 : 0
            case let d as Double:
                sanitized[key] = Int(d.rounded())
            default:
                sanitized[key] = String(describing: value).prefix(100).description
            }
        }
        #if DEBUG
        let detail = sanitized
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        print("[YTLite.Analytics] [\(name)]\(detail.isEmpty ? "" : " | \(detail)")")
        #endif
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(name, parameters: sanitized.isEmpty ? nil : sanitized)
    }

    // MARK: - App

    /// One cold open per process. A launch that also flips the scene to active
    /// does not log a second foreground. Later foregrounds stay `cold_start=false`.
    static func appOpen(coldStart: Bool) {
        let now = Date()
        if coldStart {
            guard !didLogColdOpen else { return }
            didLogColdOpen = true
            lastAppOpenAt = now
            log("app_open", ["cold_start": true])
            return
        }
        if !didLogColdOpen {
            didLogColdOpen = true
            lastAppOpenAt = now
            log("app_open", ["cold_start": true])
            return
        }
        if let lastAppOpenAt, now.timeIntervalSince(lastAppOpenAt) < 1.5 {
            return
        }
        lastAppOpenAt = now
        log("app_open", ["cold_start": false])
    }

    static func appBackground() {
        log("app_background")
    }

    // MARK: - Auth

    static func signInStart(provider: String, source: String) {
        pendingSignInSource = source
        log("sign_in_start", ["provider": provider, "source": source])
    }

    static func signInSuccess(provider: String) {
        log("sign_in_success", ["provider": provider, "source": pendingSignInSource])
        pendingSignInSource = "unknown"
    }

    static func signInFail(provider: String, error: String) {
        log("sign_in_fail", ["provider": provider, "source": pendingSignInSource, "error": error])
        pendingSignInSource = "unknown"
    }

    static func signOut() {
        log("sign_out")
    }

    // MARK: - Playback

    static func playRequest(videoId: String, source: String) {
        log("play_request", ["video_id": videoId, "source": source])
    }

    static func playResolveOk(videoId: String, ms: Int, source: String) {
        log("play_resolve_ok", ["video_id": videoId, "ms": ms, "source": source])
    }

    static func playResolveFail(videoId: String, error: String, needsLogin: Bool, attempt: Int) {
        log(
            "play_resolve_fail",
            ["video_id": videoId, "error": error, "needs_login": needsLogin, "attempt": attempt]
        )
    }

    static func playStart(videoId: String, openMs: Int, source: String) {
        log("play_start", ["video_id": videoId, "open_ms": openMs, "source": source])
    }

    static func playFail(videoId: String, error: String, retried: Bool) {
        log("play_fail", ["video_id": videoId, "error": error, "retried": retried])
    }

    static func playComplete(videoId: String, source: String) {
        log("play_complete", ["video_id": videoId, "source": source])
    }

    /// `reason`: next, previous, queue, auto_fail.
    static func playSkip(fromId: String, toId: String, reason: String) {
        guard !fromId.isEmpty, fromId != toId else { return }
        log("play_skip", ["from_id": fromId, "to_id": toId, "reason": reason])
    }

    // MARK: - Discovery

    static func homeFeedLoad(ok: Bool, count: Int, category: String) {
        log("home_feed_load", ["ok": ok, "count": count, "category": category])
    }

    /// Home tab was on screen, including a cached feed. `home_feed_load` stays network-only.
    static func homeSeen(category: String) {
        log("home_seen", ["category": category])
    }

    /// Chip change after the home tab is already visible. Not a new home visit.
    static func homeChip(category: String) {
        log("home_chip", ["category": category])
    }

    static func searchSubmit(query: String) {
        log("search_submit", ["query": query, "query_len": query.count])
    }

    static func searchResultTap(type: String) {
        log("search_result_tap", ["type": type])
    }

    /// First page of a search. `count` is 0 when the query returned nothing or failed.
    static func searchResults(ok: Bool, count: Int, tab: String) {
        log("search_results", ["ok": ok, "count": count, "tab": tab])
    }

    static func relatedTap() {
        log("related_tap")
    }

    // MARK: - Library

    static func libraryAdd(action: String) {
        log("library_add", ["action": action])
    }

    /// `show` / `add` / `dismiss` / `abandoned` for the one-time save prompt.
    static func librarySavePrompt(action: String) {
        log("library_save_prompt", ["action": action])
    }

    static func libraryRemove(action: String) {
        log("library_remove", ["action": action])
    }

    static func librarySyncStart(source: String) {
        log("library_sync_start", ["source": source])
    }

    static func librarySyncEnd(ok: Bool, ms: Int) {
        log("library_sync_end", ["ok": ok, "ms": ms])
    }

    // MARK: - Ads

    static func adEligibility(songs: Int, allowed: Bool) {
        let key = "\(songs):\(allowed)"
        guard key != lastAdEligibilityKey else { return }
        lastAdEligibilityKey = key
        log("ad_eligibility", ["songs": songs, "allowed": allowed])
    }

    static func adShow(format: String) {
        log("ad_show", ["format": format])
    }

    static func adSkipOrBlock(reason: String) {
        log("ad_skip_or_block", ["reason": reason])
    }

    // MARK: - Growth

    static func reviewPromptShow(reason: String) {
        log("review_prompt_show", ["reason": reason])
    }

    static func reviewPromptAction(action: String) {
        log("review_prompt_action", ["action": action])
    }

    static func notifPermission(status: String) {
        log("notif_permission", ["status": status])
    }

    static func dailyListenTap() {
        log("daily_listen_tap")
    }

    static func dailyListenScheduled(count: Int) {
        log("daily_listen_scheduled", ["count": count])
    }

    static func playbackLoginPrompt(hasGoogle: Bool) {
        log("playback_login_prompt", ["has_google": hasGoogle])
    }

    static func playbackLoginContinue() {
        log("playback_login_continue")
    }

    static func playbackLoginDismiss() {
        log("playback_login_dismiss")
    }

    // MARK: - VIP

    static func vipPaywallOpen() {
        log("vip_paywall_open")
    }

    static func vipPurchaseStart(productId: String) {
        log("vip_purchase_start", ["product_id": productId])
    }

    static func vipPurchaseSuccess(productId: String) {
        log("vip_purchase_success", ["product_id": productId])
    }

    static func vipPurchaseCancel(productId: String) {
        log("vip_purchase_cancel", ["product_id": productId])
    }

    static func vipPurchaseFail(productId: String, error: String) {
        log("vip_purchase_fail", ["product_id": productId, "error": error])
    }

    static func vipPurchasePending(productId: String) {
        log("vip_purchase_pending", ["product_id": productId])
    }

    static func vipRestore(ok: Bool, error: String? = nil) {
        var params: [String: Any] = ["ok": ok]
        if let error { params["error"] = error }
        log("vip_restore", params)
    }

    static func vipStatus(active: Bool, productId: String?) {
        var params: [String: Any] = ["active": active]
        if let productId { params["product_id"] = productId }
        log("vip_status", params)
    }
}

enum FirebaseBootstrap {
    static func configure() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        // GoogleService-Info may ship with IS_ANALYTICS_ENABLED=false; enable collection for product analytics.
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
        RemoteConfigStore.configure()
    }
}

/// Thin wrapper around Firebase Remote Config (parity with Android `RemoteConfigRepository`).
enum RemoteConfigStore {
    private static var allowKickoffKey: String { SaltedLiteral.rcAllowKickoff }
    private static let adsIntervalKey = "ads_interval"
    private static let kickoffIntervalKey = "kickoff_interval"

    /// Local fallback JSON when Remote Config is unavailable.
    /// ***
    private static let allowKickoffDefaultJSON =
        "{\"enable\":false,\"version\":\"0.0.0\"}"

    /// Local fallback when Remote Config is unavailable or misconfigured. Console unit is minutes.
    private static let adsIntervalDefaultMinutes: Double = AdMobConfig.interstitialCooldownMinutes

    /// Local fallback: percent of duration before local media caching may start.
    private static let kickoffIntervalDefaultPercent: Double = 100

    private struct AllowKickoffConfig: Decodable {
        var enable: Bool
        var version: String
    }

    static func configure() {
        guard isFirebaseAvailable else { return }
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 12 * 60 * 60
        #endif
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults([
            allowKickoffKey: allowKickoffDefaultJSON as NSString,
            adsIntervalKey: NSNumber(value: adsIntervalDefaultMinutes),
            kickoffIntervalKey: NSNumber(value: kickoffIntervalDefaultPercent),
        ])
    }

    /// Fetch and activate latest values. Safe to call repeatedly from app launch.
    @discardableResult
    static func fetchAndActivate() async -> Bool {
        guard isFirebaseAvailable else { return false }
        do {
            let status = try await RemoteConfig.remoteConfig().fetchAndActivate()
            AdProbe.log(
                "remote_config.ads_interval",
                "\(Int(adsIntervalMinutes))min (\(Int(adsInterval))s)"
            )
            AdProbe.log("remote_config.kickoff_interval", "\(Int(kickoffIntervalPercent))%")
            AdProbe.log("remote_config.media_policy", "\(allowKickoff)")
            return status != .error
        } catch {
            return false
        }
    }

    /// True only when an activated remote `allow_kickoff` value is present.
    /// A missing or default value is not a decision to wipe the media cache.
    static var hasRemoteAllowKickoff: Bool {
        guard isFirebaseAvailable else { return false }
        return RemoteConfig.remoteConfig()
            .configValue(forKey: allowKickoffKey)
            .source == .remote
    }

    /// ***
    static var allowKickoff: Bool {
        guard hasRemoteAllowKickoff else { return false }
        let value = RemoteConfig.remoteConfig().configValue(forKey: allowKickoffKey)
        return resolveAllowKickoff(from: value.stringValue)
    }

    /// `ads_interval` from Remote Config, in minutes. Zero means no cooldown.
    static var adsIntervalMinutes: Double {
        guard isFirebaseAvailable else { return adsIntervalDefaultMinutes }
        let raw = RemoteConfig.remoteConfig()
            .configValue(forKey: adsIntervalKey)
            .numberValue
            .doubleValue
        // Negative / NaN → default. Zero means no cooldown.
        guard raw.isFinite, raw >= 0 else { return adsIntervalDefaultMinutes }
        return raw
    }

    /// Minimum seconds between two ordinary full-screen ads (app open / interstitial).
    static var adsInterval: TimeInterval {
        adsIntervalMinutes * 60
    }

    /// Percent of track duration (0…100) before local media caching may start.
    /// Default / invalid → `100` (only after the track has fully played).
    static var kickoffIntervalPercent: Double {
        guard isFirebaseAvailable else { return kickoffIntervalDefaultPercent }
        let raw = RemoteConfig.remoteConfig()
            .configValue(forKey: kickoffIntervalKey)
            .numberValue
            .doubleValue
        guard raw.isFinite, raw >= 0 else { return kickoffIntervalDefaultPercent }
        return min(raw, 100)
    }

    private static func resolveAllowKickoff(from raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let cfg = try? JSONDecoder().decode(AllowKickoffConfig.self, from: data)
        else {
            return false
        }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        // ***
        if compareSemver(current, cfg.version) == .orderedAscending {
            return true
        }
        return cfg.enable
    }

    /// Numeric semver compare: `1.2.0` vs `1.10.0`.
    private static func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    private static var isFirebaseAvailable: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
            && FirebaseApp.app() != nil
    }
}
