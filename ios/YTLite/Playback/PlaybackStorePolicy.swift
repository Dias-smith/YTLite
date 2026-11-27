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
        #if targetEnvironment(macCatalyst)
        let limit = Double(MacPlaybackCacheStore.maxMinutes * 60)
        #else
        let limit = Double(maxStorableDurationSeconds)
        #endif
        return seconds <= limit
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
        isMediaCachePolicyEnabled
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
    /// Bumped when a download starts or the user cancels, so a stale task cannot clear the next one.
    private var downloadGeneration: [String: UInt] = [:]
    private var activityAt: [String: Date] = [:]
    /// No byte progress for this long means the ring can be tapped to cancel.
    static let stallAfter: TimeInterval = 8

    /// Starts a visible download and returns the generation later progress updates must match.
    func beginDownload(videoId: String) -> UInt {
        let next = (downloadGeneration[videoId] ?? 0) &+ 1
        downloadGeneration[videoId] = next
        activityAt[videoId] = Date()
        guard !videoIds.contains(videoId) else { return next }
        fractions[videoId] = 0
        return next
    }

    func cancelDownload(videoId: String) {
        downloadGeneration[videoId] = (downloadGeneration[videoId] ?? 0) &+ 1
        activityAt.removeValue(forKey: videoId)
        fractions.removeValue(forKey: videoId)
    }

    func isStalled(videoId: String, now: Date = Date()) -> Bool {
        guard fractions[videoId] != nil, !videoIds.contains(videoId) else { return false }
        guard let at = activityAt[videoId] else { return true }
        return now.timeIntervalSince(at) >= Self.stallAfter
    }

    func owns(videoId: String, generation: UInt) -> Bool {
        downloadGeneration[videoId] == generation
    }

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

    func setFraction(videoId: String, _ value: Double, generation: UInt? = nil) {
        if let generation, downloadGeneration[videoId] != generation { return }
        guard !videoIds.contains(videoId) else { return }
        activityAt[videoId] = Date()
        let clamped = min(0.99, max(0, value))
        if let current = fractions[videoId], abs(current - clamped) < 0.01 { return }
        fractions[videoId] = clamped
    }

    func clearFraction(videoId: String, generation: UInt? = nil) {
        if let generation, downloadGeneration[videoId] != generation { return }
        activityAt.removeValue(forKey: videoId)
        guard fractions[videoId] != nil else { return }
        fractions.removeValue(forKey: videoId)
    }
}

/// Progressive URL the player is using for the song that is on now.
struct MacPlaybackStreamSource: Sendable {
    let videoId: String
    let streamURL: URL
    let itag: Int
    let mimeType: String
    let title: String
    let channelName: String
    let thumbnailURL: URL?
    let durationSeconds: Int
}

/// Starts a manual playback-file download for one song and refreshes the card indicator.
@MainActor
enum MacSongCacheDownloads {
    static func start(
        items: [VideoItem],
        libraryStore: LibraryStore?,
        playback: PlaybackController
    ) {
        for item in items {
            guard !item.isLive else { continue }
            let isCurrent = playback.nowPlaying?.videoId == item.videoId
            start(
                videoId: item.videoId,
                thumbnailURL: item.thumbnailURL,
                libraryStore: libraryStore,
                playingSource: isCurrent ? playback.macPlaybackStreamSource() : nil,
                requirePlayingSource: isCurrent
            )
        }
    }

    static func start(
        videoId: String,
        thumbnailURL: URL?,
        libraryStore: LibraryStore?,
        playingSource: MacPlaybackStreamSource? = nil,
        requirePlayingSource: Bool = false
    ) {
        guard !videoId.isEmpty, !LocalTrackID.isLocal(videoId) else { return }
        let current = playingSource?.videoId == videoId ? playingSource : nil
        if requirePlayingSource, current == nil { return }
        let index = MacCachedMediaIndex.shared
        guard !index.videoIds.contains(videoId), index.fractions[videoId] == nil else { return }
        let generation = index.beginDownload(videoId: videoId)
        Task {
            await PlaybackMediaStore.shared.cancelPersist(videoId: videoId)
            var saved = false
            var resolved: VideoPlayback?
            do {
                if let current {
                    let stillCurrent = await MainActor.run { () -> Bool in
                        MacCachedMediaIndex.shared.owns(videoId: videoId, generation: generation)
                    }
                    guard stillCurrent else { return }
                    saved = await PlaybackMediaStore.shared.schedulePersist(
                        videoId: videoId,
                        sourceURL: current.streamURL,
                        itag: current.itag,
                        mimeType: current.mimeType,
                        thumbnailURL: thumbnailURL ?? current.thumbnailURL,
                        generation: generation
                    )
                } else {
                let playback = try await StreamResolver.shared.resolvePlayback(videoId: videoId)
                resolved = playback
                let stillCurrent = await MainActor.run { () -> Bool in
                    MacCachedMediaIndex.shared.owns(videoId: videoId, generation: generation)
                }
                guard stillCurrent else { return }
                guard let format = PlaybackFormatSelector.select(formats: playback.formats, preferVideo: true) else {
                        throw URLError(.unsupportedURL)
                    }
                    saved = await PlaybackMediaStore.shared.schedulePersist(
                        videoId: videoId,
                        sourceURL: format.url,
                        itag: format.itag,
                        mimeType: format.mimeType,
                        thumbnailURL: thumbnailURL ?? playback.thumbnailURL,
                        generation: generation
                    )
                }
            } catch {
                saved = false
            }
            let cached = await PlaybackMediaStore.shared.cachedSnapshots()
            let ids = Set(cached.map(\.videoId))
            let playback = resolved
            await MainActor.run {
                guard MacCachedMediaIndex.shared.owns(videoId: videoId, generation: generation) else { return }
                MacCachedMediaIndex.shared.replace(ids)
                if !saved {
                    MacCachedMediaIndex.shared.clearFraction(videoId: videoId, generation: generation)
                }
                if saved, let current, let libraryStore {
                    _ = libraryStore.upsertTrack(
                        from: VideoItem(
                            videoId: videoId,
                            title: current.title,
                            channelName: current.channelName,
                            thumbnailURL: PlaybackCachedCover.resolveURL(videoId: videoId)
                                ?? thumbnailURL
                                ?? current.thumbnailURL,
                            durationText: DurationFormat.text(seconds: current.durationSeconds)
                        ),
                        durationSeconds: current.durationSeconds
                    )
                    libraryStore.saveLocalOnly()
                } else if saved, let playback, let libraryStore {
                    _ = libraryStore.upsertTrack(
                        from: VideoItem(
                            videoId: videoId,
                            title: playback.title,
                            channelName: playback.channelName,
                            thumbnailURL: PlaybackCachedCover.resolveURL(videoId: videoId)
                                ?? thumbnailURL
                                ?? playback.thumbnailURL,
                            durationText: DurationFormat.text(seconds: playback.durationSeconds)
                        ),
                        durationSeconds: playback.durationSeconds
                    )
                    libraryStore.saveLocalOnly()
                }
                libraryStore?.syncOfflinePlaylist(cached: cached)
            }
        }
    }

    /// Stops the in-flight file so the row can show the download button again.
    static func cancel(videoId: String) {
        guard !videoId.isEmpty else { return }
        MacCachedMediaIndex.shared.cancelDownload(videoId: videoId)
        Task { await PlaybackMediaStore.shared.cancelPersist(videoId: videoId) }
    }
}

/// Mac playback-file switch. On until the user turns it off.
enum MacPlaybackCacheStore {
    private static let enabledKey = "mac.playback_media_cache.v1"
    private static let percentKey = "mac.playback_media_cache.percent.v1"
    private static let minutesKey = "mac.playback_media_cache.max_minutes.v1"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Playback progress, 5...100 in steps of 5, before an automatic download starts.
    static var startPercent: Int {
        get { stepped(UserDefaults.standard.object(forKey: percentKey) == nil ? 10 : UserDefaults.standard.integer(forKey: percentKey), 5, 100, 5) }
        set { UserDefaults.standard.set(stepped(newValue, 5, 100, 5), forKey: percentKey) }
    }

    /// Videos longer than this are not downloaded automatically. 5...240 in steps of 5.
    static var maxMinutes: Int {
        get { stepped(UserDefaults.standard.object(forKey: minutesKey) == nil ? 30 : UserDefaults.standard.integer(forKey: minutesKey), 5, 240, 5) }
        set { UserDefaults.standard.set(stepped(newValue, 5, 240, 5), forKey: minutesKey) }
    }

    private static func stepped(_ value: Int, _ lower: Int, _ upper: Int, _ step: Int) -> Int {
        let clamped = min(upper, max(lower, value))
        let snapped = lower + ((clamped - lower + step / 2) / step) * step
        return min(upper, max(lower, snapped))
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
