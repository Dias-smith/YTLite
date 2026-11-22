import Foundation

/// Rules for automatic local playback media persistence.
enum PlaybackStorePolicy {
    static let maxStoreBytes: Int64 = 512 * 1024 * 1024
    static let lowRamMaxStoreBytes: Int64 = 256 * 1024 * 1024
    static let maxStorableDurationSeconds = 30 * 60

    static var maxStoreBytesForDevice: Int64 {
        ProcessInfo.processInfo.physicalMemory < 2_000_000_000
            ? lowRamMaxStoreBytes
            : maxStoreBytes
    }

    static func isStorableDuration(seconds: Double?) -> Bool {
        guard let seconds, seconds.isFinite, seconds > 0 else { return true }
        return seconds <= Double(maxStorableDurationSeconds)
    }

    static func storeKey(videoId: String, itag: Int?) -> String {
        if let itag { return "\(videoId):\(itag)" }
        return videoId
    }

    static func fileExtension(for mimeType: String) -> String {
        let mime = mimeType.lowercased()
        if mime.contains("audio/mp4") || mime.contains("audio/aac") || mime.contains("audio/m4a") {
            return "m4a"
        }
        if mime.contains("audio/mpeg") || mime.contains("audio/mp3") {
            return "mp3"
        }
        if mime.contains("video/mp4") || mime.contains("mp4") {
            return "mp4"
        }
        return "bin"
    }

    /// iPhone Release never stores streams. iPhone Debug follows the debug switch.
    /// Mac stores streams when its own switch is on.
    static var isMediaCachePolicyEnabled: Bool {
        #if targetEnvironment(macCatalyst)
        return MacPlaybackCacheStore.isEnabled
        #elseif DEBUG
        return DebugPlaybackCacheStore.forceEnableMediaCache
        #else
        return false
        #endif
    }

    /// iPhone Release always resolves a fresh stream. Mac and iPhone Debug may play a stored file.
    static var allowsDirectKickoffPlayback: Bool {
        isMediaCachePolicyEnabled && !NetworkVpnStatus.isActive
    }
}

#if targetEnvironment(macCatalyst)
/// Mac playback-file switch. On until the user turns it off.
enum MacPlaybackCacheStore {
    private static let enabledKey = "mac.playback_media_cache.v1"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}
#endif

#if DEBUG
/// DEBUG-only override so local media caching can be exercised without Remote Config.
enum DebugPlaybackCacheStore {
    private static let forceEnableKey = "debug.force_enable_media_cache.v1"

    static var forceEnableMediaCache: Bool {
        get { UserDefaults.standard.bool(forKey: forceEnableKey) }
        set { UserDefaults.standard.set(newValue, forKey: forceEnableKey) }
    }
}
#endif

/// Best-effort VPN detection via system proxy scoped interfaces.
/// Prefer exact / prefix matches — bare `contains("tun")` false-positives on system `utun*`.
enum NetworkVpnStatus {
    static var isActive: Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = settings["__SCOPED__"] as? [String: Any]
        else { return false }
        return scoped.keys.contains { key in
            let lower = key.lowercased()
            if lower.hasPrefix("utun") { return false }
            return lower.hasPrefix("tap")
                || lower.hasPrefix("tun")
                || lower.hasPrefix("ppp")
                || lower.hasPrefix("ipsec")
                || lower.contains("ipsec")
        }
    }
}
