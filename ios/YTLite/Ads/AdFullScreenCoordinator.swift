import Foundation

/// Serializes all full-screen ad formats and owns their shared cooldown.
@MainActor
enum AdFullScreenCoordinator {
    private static var activeReason: String?
    private static var lastOrdinaryAdFinishedAt: Date?

    static var isPresenting: Bool { activeReason != nil }

    static func beginOrdinary(reason: String, observesCooldown: Bool = true) -> Bool {
        guard activeReason == nil else {
            AdProbe.log("fullscreen.begin.skip", "busy=\(activeReason ?? "-") reason=\(reason)")
            return false
        }
        if observesCooldown, let lastOrdinaryAdFinishedAt {
            let elapsed = Date().timeIntervalSince(lastOrdinaryAdFinishedAt)
            let cooldown = RemoteConfigStore.adsInterval
            let remaining = max(0, cooldown - elapsed)
            guard remaining <= 0 else {
                AdProbe.log(
                    "fullscreen.begin.skip",
                    "cooldown remaining=\(Int(remaining))s interval=\(Int(cooldown))s reason=\(reason)"
                )
                return false
            }
        }
        markPresenting(reason: reason)
        return true
    }

    static func beginRewarded(reason: String) -> Bool {
        guard activeReason == nil else {
            AdProbe.log("fullscreen.begin.skip", "busy=\(activeReason ?? "-") reason=\(reason)")
            return false
        }
        markPresenting(reason: reason)
        return true
    }

    private static func markPresenting(reason: String) {
        activeReason = reason
        NotificationCenter.default.post(name: .ytliteFullScreenAdDidPresent, object: nil)
    }

    static func finish(didShowOrdinaryAd: Bool) {
        let reason = activeReason ?? "-"
        if didShowOrdinaryAd {
            lastOrdinaryAdFinishedAt = Date()
        }
        activeReason = nil
        AdProbe.log("fullscreen.finish", "reason=\(reason) ordinary=\(didShowOrdinaryAd)")
        NotificationCenter.default.post(name: .ytliteFullScreenAdDidDismiss, object: nil)
        AdSceneLifecycle.adEnvironmentDidBecomeReady(source: "fullscreen_finish")
    }
}
