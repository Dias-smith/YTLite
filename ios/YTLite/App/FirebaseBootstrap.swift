import Foundation
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import FirebaseRemoteConfig

/// Product analytics (Firebase). Keeps event names stable; DEBUG also prints to Console.
enum AppAnalytics {
    private static var pendingSignInSource = "unknown"
    private static var lastAdEligibilityKey: String?

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

    static func appOpen(coldStart: Bool) {
        log("app_open", ["cold_start": coldStart])
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

    static func playResolveFail(videoId: String, error: String, needsLogin: Bool) {
        log("play_resolve_fail", ["video_id": videoId, "error": error, "needs_login": needsLogin])
    }

    static func playStart(videoId: String, openMs: Int) {
        log("play_start", ["video_id": videoId, "open_ms": openMs])
    }

    static func playFail(videoId: String, error: String, retried: Bool) {
        log("play_fail", ["video_id": videoId, "error": error, "retried": retried])
    }

    static func playComplete(videoId: String) {
        log("play_complete", ["video_id": videoId])
    }

    static func playSkip(fromId: String, toId: String) {
        log("play_skip", ["from_id": fromId, "to_id": toId])
    }

    // MARK: - Discovery

    static func homeFeedLoad(ok: Bool, count: Int, category: String) {
        log("home_feed_load", ["ok": ok, "count": count, "category": category])
    }

    static func searchSubmit(query: String) {
        log("search_submit", ["query": query, "query_len": query.count])
    }

    static func searchResultTap(type: String) {
        log("search_result_tap", ["type": type])
    }

    static func relatedTap() {
        log("related_tap")
    }

    static func shortsOpen() {
        log("shorts_open")
    }

    // MARK: - Library

    static func libraryAdd(action: String) {
        log("library_add", ["action": action])
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

    static func playbackLoginPrompt(hasGoogle: Bool) {
        log("playback_login_prompt", ["has_google": hasGoogle])
    }

    static func playbackLoginContinue() {
        log("playback_login_continue")
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
    private static let allowOfflineKey = "allow_offline"

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
            allowOfflineKey: NSNumber(value: false),
        ])
    }

    /// Fetch and activate latest values. Safe to call repeatedly from app launch.
    @discardableResult
    static func fetchAndActivate() async -> Bool {
        guard isFirebaseAvailable else { return false }
        do {
            let status = try await RemoteConfig.remoteConfig().fetchAndActivate()
            return status != .error
        } catch {
            return false
        }
    }

    /// When true, play local media store without re-resolving stream URLs.
    static var allowOffline: Bool {
        guard isFirebaseAvailable else { return false }
        return RemoteConfig.remoteConfig().configValue(forKey: allowOfflineKey).boolValue
    }

    private static var isFirebaseAvailable: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
            && FirebaseApp.app() != nil
    }
}
