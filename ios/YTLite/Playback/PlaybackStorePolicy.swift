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
/// Finished playback files, plus in-flight download fractions for the song-card control.
@MainActor
final class MacCachedMediaIndex: ObservableObject {
    static let shared = MacCachedMediaIndex()

    @Published private(set) var videoIds: Set<String> = []
    /// 0...0.99 while a file is downloading. Removed when the file is saved or the download stops.
    @Published private(set) var fractions: [String: Double] = [:]

    func replace(_ ids: Set<String>) {
        let nextFractions = fractions.filter { !ids.contains($0.key) }
        guard ids != videoIds || nextFractions.count != fractions.count else { return }
        videoIds = ids
        if nextFractions.count != fractions.count {
            fractions = nextFractions
        }
    }

    func removeAll() {
        videoIds = []
        if !fractions.isEmpty {
            fractions = [:]
        }
    }

    func setFraction(videoId: String, _ value: Double) {
        guard !videoIds.contains(videoId) else { return }
        let clamped = min(0.99, max(0, value))
        if let current = fractions[videoId], abs(current - clamped) < 0.01 { return }
        fractions[videoId] = clamped
    }

    func clearFraction(videoId: String) {
        guard fractions[videoId] != nil else { return }
        fractions.removeValue(forKey: videoId)
    }
}

/// Starts a manual playback-file download for one song and refreshes the card indicator.
@MainActor
enum MacSongCacheDownloads {
    static func start(videoId: String, thumbnailURL: URL?, libraryStore: LibraryStore?) {
        guard !videoId.isEmpty, !LocalTrackID.isLocal(videoId) else { return }
        let index = MacCachedMediaIndex.shared
        guard !index.videoIds.contains(videoId), index.fractions[videoId] == nil else { return }
        index.setFraction(videoId: videoId, 0)
        Task {
            var saved = false
            do {
                let playback = try await StreamResolver.shared.resolvePlayback(videoId: videoId)
                guard let format = PlaybackFormatSelector.select(formats: playback.formats, preferVideo: true) else {
                    throw URLError(.unsupportedURL)
                }
                saved = await PlaybackMediaStore.shared.schedulePersist(
                    videoId: videoId,
                    sourceURL: format.url,
                    itag: format.itag,
                    mimeType: format.mimeType,
                    thumbnailURL: thumbnailURL ?? playback.thumbnailURL
                )
            } catch {
                saved = false
            }
            let cached = await PlaybackMediaStore.shared.cachedSnapshots()
            let ids = Set(cached.map(\.videoId))
            await MainActor.run {
                MacCachedMediaIndex.shared.replace(ids)
                if !saved {
                    MacCachedMediaIndex.shared.clearFraction(videoId: videoId)
                }
                libraryStore?.syncOfflinePlaylist(cached: cached)
            }
        }
    }
}

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
