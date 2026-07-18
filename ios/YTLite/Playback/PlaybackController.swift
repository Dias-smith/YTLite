import Foundation
import AVFoundation
import Combine
import MediaPlayer
import UIKit

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var nowPlaying: NowPlayingItem?
    @Published private(set) var queue: [VideoItem] = []
    @Published private(set) var queueIndex: Int = 0
    /// Playlist that loaded the current queue (Android `sourcePlaylistId`); nil for ad-hoc queues.
    @Published private(set) var sourcePlaylistId: String?
    @Published private(set) var shuffleEnabled: Bool = false
    @Published private(set) var repeatMode: QueueRepeatMode = .off
    @Published private(set) var isPlaying: Bool = false
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            applySpeed()
            UserDefaults.standard.set(playbackSpeed, forKey: Self.speedKey)
            updateNowPlayingInfo()
        }
    }
    /// Progress clock lives here so list tabs observing `PlaybackController` are not
    /// invalidated every 0.5s. Inject `progress` as its own `environmentObject`.
    let progress = PlaybackProgressModel()

    @Published private(set) var isBuffering: Bool = false
    @Published var lastError: String?
    /// True when extract failed because YouTube asked for a signed-in session.
    @Published private(set) var needsLoginForPlayback: Bool = false
    @Published private(set) var isFavorite: Bool = false
    /// Local Not interested (Android player dislike) — mutually exclusive with Like.
    @Published private(set) var isDisliked: Bool = false
    @Published private(set) var isChannelSubscribed: Bool = false
    @Published private(set) var captionTracks: [CaptionTrack] = []
    /// HLS live quality ladder (empty for progressive / non-HLS).
    @Published private(set) var hlsVariants: [HLSVariant] = []
    /// `nil` = Auto (master playlist). Otherwise a variant id from `hlsVariants`.
    @Published private(set) var selectedHLSVariantID: String?
    @Published private(set) var isLoadingHLSVariants: Bool = false
    @Published private(set) var hlsVariantsLoadFailed: Bool = false
    /// Wall-clock end for session sleep timer; nil when inactive.
    @Published private(set) var sleepTimerEndsAt: Date?
    /// Preset minutes that started the current timer (`nil` = Off).
    @Published private(set) var sleepTimerMinutes: Int?

    static let speedOptions: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 5, 8]
    private static let speedKey = "playback_speed"

    /// Forwards to `progress` without publishing on this object.
    var positionSeconds: Double {
        get { progress.positionSeconds }
        set { progress.setPosition(newValue) }
    }

    var durationSeconds: Double {
        get { progress.durationSeconds }
        set { progress.setDuration(newValue) }
    }

    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var extractTask: Task<Void, Never>?
    private var hlsVariantsTask: Task<Void, Never>?
    private var nextPrefetchScheduleTask: Task<Void, Never>?
    private var nearEndPrefetchVerifiedVideoId: String?
    private var lastNearEndPrefetchCheckAt: Date?
    private var currentHLSMasterURL: URL?
    /// True when the current AVPlayer item came from `PlaybackPrefetcher` (one-shot retry on fail).
    private var playingFromPrefetch = false
    /// Prevents infinite prefetch→fail→extract loops.
    private var prefetchPlaybackRetryUsed = false
    /// One-shot re-extract when googlevideo open times out (-1001) on cold/non-prefetch play.
    private var streamTimeoutReextractUsed = false
    /// Probe-only: when current stream open began / which URL is loading.
    private var probeStreamStartedAt: CFAbsoluteTime?
    private var probeStreamURL: URL?
    private var probeStreamSource: String = "cold"
    private var persistTask: Task<Void, Never>?
    private var sleepTimerCancellable: AnyCancellable?
    /// Pre-shuffle queue snapshot (Android `originalOrder`).
    private var originalOrder: [VideoItem]?
    /// Seek target after cold-start restore + extract.
    private var pendingSeekSeconds: Double = 0
    /// While true, time-observer must not overwrite `positionSeconds` with stale `currentTime`.
    private var isSeekInProgress = false
    /// Bumps on each `seek(to:)` so superseded completion handlers are ignored.
    private var seekGeneration: Int = 0
    /// Bumps on each `playCurrentQueueItem` so stale extract callbacks cannot mutate UI.
    private var extractGeneration: Int = 0
    private var artworkImage: UIImage?
    private var artworkVideoId: String?
    private var artworkTask: Task<Void, Never>?
    private var artworkGeneration: Int = 0
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    /// Resume after interruption only if we were playing when interrupted.
    private var resumeAfterInterruption = false

    var hasNextInQueue: Bool {
        if queueIndex + 1 < queue.count { return true }
        return repeatMode == .all && !queue.isEmpty
    }

    var hasPreviousInQueue: Bool {
        if queueIndex > 0 { return true }
        return repeatMode == .all && !queue.isEmpty
    }

    /// True when the current item is playing via HLS (live quality menu eligible).
    var isPlayingHLS: Bool {
        currentHLSMasterURL != nil
    }

    var selectedHLSQualityLabel: String {
        if let id = selectedHLSVariantID,
           let variant = hlsVariants.first(where: { $0.id == id })
        {
            return variant.displayLabel
        }
        return L("player.quality.auto")
    }

    var sleepTimerRemaining: TimeInterval? {
        guard let sleepTimerEndsAt else { return nil }
        _ = progress.sleepTimerTick
        return max(0, sleepTimerEndsAt.timeIntervalSinceNow)
    }

    weak var libraryStore: LibraryStore?
    var onPlaybackStarted: ((NowPlayingItem) -> Void)?

    /// True when `nowPlaying` was restored but AVPlayer has not loaded a stream yet.
    var needsStreamResume: Bool { nowPlaying != nil && player == nil && !isBuffering }

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.speedKey) as? Float
        if let stored, Self.speedOptions.contains(stored) {
            playbackSpeed = stored
        }
        configureAudioSession()
        configureAudioInterruptions()
        configureRemoteCommands()
        restoreSession()
        refreshRemoteCommandEnabled()
    }

    func play(items: [VideoItem], startAt index: Int = 0, sourcePlaylistId: String? = nil) {
        guard !items.isEmpty else { return }
        let start = index.clamped(to: 0...(items.count - 1))
        let selectedItem = items[start]

        // Opening the currently loaded video must not rebuild its queue, re-extract
        // the stream, or reset progress. Only resume it when it is paused.
        if nowPlaying?.videoId == selectedItem.videoId {
            resumeCurrentPlaybackIfNeeded()
            return
        }

        self.sourcePlaylistId = sourcePlaylistId
        originalOrder = items
        PlaybackPrefetcher.shared.clear()
        cancelScheduledNextPrefetch()
        if shuffleEnabled {
            let current = items[start]
            let tail = items.enumerated().filter { $0.offset != start }.map(\.element).shuffled()
            queue = [current] + tail
            queueIndex = 0
        } else {
            queue = items
            queueIndex = start
        }
        pendingSeekSeconds = 0
        playCurrentQueueItem()
        persistSession(immediate: true)
    }

    /// Jump within the existing Up next queue without rebuilding or reshuffling the list.
    func playQueueIndex(_ index: Int) {
        guard !queue.isEmpty else { return }
        let target = index.clamped(to: 0...(queue.count - 1))
        let item = queue[target]
        if nowPlaying?.videoId == item.videoId, queueIndex == target {
            resumeCurrentPlaybackIfNeeded()
            return
        }
        queueIndex = target
        pendingSeekSeconds = 0
        playCurrentQueueItem()
        persistSession(immediate: true)
    }

    private func resumeCurrentPlaybackIfNeeded() {
        guard !isPlaying else { return }
        // An in-flight extraction starts playback when it completes.
        guard !isBuffering else { return }
        if lastError != nil || player == nil || player?.currentItem == nil {
            guard nowPlaying != nil, !queue.isEmpty else { return }
            playCurrentQueueItem()
        } else {
            player?.playImmediately(atRate: playbackSpeed)
            isPlaying = true
            updateNowPlayingInfo()
            persistSession(immediate: true)
        }
    }

    func playSearchItem(_ item: SearchVideoItem) {
        play(items: [item], startAt: 0)
    }

    /// Manual skip — advances even in Repeat One (Android detail `skipToNext`).
    func playNext() {
        guard !queue.isEmpty else { return }
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            playCurrentQueueItem()
            return
        }
        if repeatMode == .all {
            queueIndex = 0
            playCurrentQueueItem()
        }
    }

    /// Manual skip to the previous queue item (does not restart the current track).
    func playPrevious() {
        guard !queue.isEmpty else { return }
        if queueIndex > 0 {
            queueIndex -= 1
            playCurrentQueueItem()
            return
        }
        if repeatMode == .all {
            queueIndex = queue.count - 1
            playCurrentQueueItem()
        }
    }

    @discardableResult
    func toggleShuffle() -> Bool {
        let previousPrefetchTargetId = nextPrefetchQueueItem()?.videoId
        shuffleEnabled.toggle()
        if shuffleEnabled {
            originalOrder = originalOrder ?? queue
            let currentId = nowPlaying?.videoId
                ?? (queue.indices.contains(queueIndex) ? queue[queueIndex].videoId : nil)
            let current = currentId.flatMap { id in queue.first { $0.videoId == id } }
            let tail = queue.filter { $0.videoId != current?.videoId }.shuffled()
            queue = [current].compactMap { $0 } + tail
            queueIndex = 0
        } else {
            let restored = originalOrder ?? queue
            let currentId = nowPlaying?.videoId
                ?? (queue.indices.contains(queueIndex) ? queue[queueIndex].videoId : nil)
            queue = restored
            if let currentId, let idx = restored.firstIndex(where: { $0.videoId == currentId }) {
                queueIndex = idx
            } else {
                queueIndex = queueIndex.clamped(to: 0...max(0, restored.count - 1))
            }
        }
        persistSession(immediate: true)
        refreshRemoteCommandEnabled()
        rescheduleNextTrackPreparation(previousTargetId: previousPrefetchTargetId)
        return shuffleEnabled
    }

    @discardableResult
    func cycleRepeatMode() -> QueueRepeatMode {
        let previousPrefetchTargetId = nextPrefetchQueueItem()?.videoId
        repeatMode.cycle()
        persistSession(immediate: true)
        refreshRemoteCommandEnabled()
        rescheduleNextTrackPreparation(previousTargetId: previousPrefetchTargetId)
        return repeatMode
    }

    func toggleFavorite() {
        guard let item = nowPlaying, let store = libraryStore else { return }
        let video = VideoItem(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURL: item.thumbnailURL
        )
        if store.isFavorite(videoId: item.videoId) {
            store.toggleFavorite(item: video)
        } else {
            store.toggleFavorite(item: video)
            if store.isNotInterested(videoId: item.videoId) {
                store.removeNotInterested(videoId: item.videoId)
            }
        }
        refreshFavoriteState()
    }

    /// Android `toggleDislike` — local Not interested; clears Like when enabling.
    func toggleDislike() {
        guard let item = nowPlaying, let store = libraryStore else { return }
        if store.isNotInterested(videoId: item.videoId) {
            store.removeNotInterested(videoId: item.videoId)
        } else {
            _ = store.toggleNotInterested(videoId: item.videoId)
            if store.isFavorite(videoId: item.videoId) {
                store.toggleFavorite(
                    item: VideoItem(
                        videoId: item.videoId,
                        title: item.title,
                        channelName: item.channelName,
                        thumbnailURL: item.thumbnailURL
                    )
                )
            }
        }
        refreshFavoriteState()
    }

    /// Insert after the currently playing item (Android "Play next").
    func insertNext(_ item: VideoItem) {
        if queue.isEmpty {
            play(items: [item], startAt: 0)
            return
        }
        let insertAt = min(queueIndex + 1, queue.count)
        if let existing = queue.firstIndex(where: { $0.videoId == item.videoId }) {
            guard existing != queueIndex else { return }
            var next = queue
            next.remove(at: existing)
            let adjusted = existing < insertAt ? insertAt - 1 : insertAt
            next.insert(item, at: min(adjusted, next.count))
            if existing < queueIndex { queueIndex -= 1 }
            queue = next
            syncOriginalOrderInsert(item, near: insertAt)
            persistSession(immediate: true)
            return
        }
        queue.insert(item, at: insertAt)
        syncOriginalOrderInsert(item, near: insertAt)
        persistSession(immediate: true)
    }

    /// Append to the end of the play queue (Android "Add to queue").
    func appendToQueue(_ item: VideoItem) {
        if queue.isEmpty {
            play(items: [item], startAt: 0)
            return
        }
        if queue.contains(where: { $0.videoId == item.videoId }) { return }
        queue.append(item)
        if var order = originalOrder, !order.contains(where: { $0.videoId == item.videoId }) {
            order.append(item)
            originalOrder = order
        }
        persistSession(immediate: true)
    }

    /// Reorder the queue while keeping the current track selected.
    func reorderQueue(by areInIncreasingOrder: (VideoItem, VideoItem) -> Bool) {
        guard queue.count > 1 else { return }
        let currentId = nowPlaying?.videoId
            ?? (queue.indices.contains(queueIndex) ? queue[queueIndex].videoId : nil)
        queue.sort(by: areInIncreasingOrder)
        if let currentId, let idx = queue.firstIndex(where: { $0.videoId == currentId }) {
            queueIndex = idx
        }
        if !shuffleEnabled {
            originalOrder = queue
        }
        persistSession(immediate: true)
    }

    func removeFromQueue(videoIds: Set<String>) {
        guard !videoIds.isEmpty else { return }
        let currentId = nowPlaying?.videoId
            ?? (queue.indices.contains(queueIndex) ? queue[queueIndex].videoId : nil)
        let wasPlayingCurrent = currentId.map { videoIds.contains($0) } ?? false
        queue.removeAll { videoIds.contains($0.videoId) }
        originalOrder?.removeAll { videoIds.contains($0.videoId) }
        if queue.isEmpty {
            stop()
            return
        }
        if wasPlayingCurrent {
            queueIndex = min(queueIndex, queue.count - 1)
            playCurrentQueueItem()
        } else if let currentId, let idx = queue.firstIndex(where: { $0.videoId == currentId }) {
            queueIndex = idx
        } else {
            queueIndex = min(queueIndex, queue.count - 1)
        }
        persistSession(immediate: true)
    }

    private func syncOriginalOrderInsert(_ item: VideoItem, near insertAt: Int) {
        guard var order = originalOrder else {
            if !shuffleEnabled { originalOrder = queue }
            return
        }
        if let existing = order.firstIndex(where: { $0.videoId == item.videoId }) {
            order.remove(at: existing)
        }
        order.insert(item, at: min(insertAt, order.count))
        originalOrder = order
    }

    func refreshFavoriteState() {
        guard let videoId = nowPlaying?.videoId else {
            isFavorite = false
            isDisliked = false
            return
        }
        isFavorite = libraryStore?.isFavorite(videoId: videoId) ?? false
        isDisliked = libraryStore?.isNotInterested(videoId: videoId) ?? false
    }

    func refreshSubscribeState() {
        guard let channelId = nowPlaying?.channelId,
              ChannelID.isBrowsable(channelId)
        else {
            isChannelSubscribed = false
            return
        }
        isChannelSubscribed = libraryStore?.isSubscribed(channelId: channelId) ?? false
    }

    /// Android `PlayerViewModel.toggleChannelSubscribe`.
    @discardableResult
    func toggleChannelSubscribe() -> Bool {
        guard let item = nowPlaying,
              let channelId = item.channelId,
              ChannelID.isBrowsable(channelId)
        else { return false }
        let avatar = item.channelAvatarURL?.absoluteString ?? item.thumbnailURL?.absoluteString
        let subscribed = libraryStore?.toggleSubscribeChannel(
            channelId: channelId,
            title: item.channelName,
            avatarUrl: avatar
        ) ?? false
        isChannelSubscribed = subscribed
        return subscribed
    }

    /// Attach a resolved channel avatar onto the current now-playing item.
    func updateChannelAvatar(_ url: URL?) {
        guard let url, var item = nowPlaying else { return }
        guard item.channelAvatarURL != url else { return }
        item.channelAvatarURL = url
        nowPlaying = item
        persistSession(immediate: true)
    }

    private func playCurrentQueueItem(allowPrefetchConsume: Bool = true) {
        guard queue.indices.contains(queueIndex) else { return }
        let item = queue[queueIndex]
        // New queue target → allow one timeout / prefetch re-extract again.
        if nowPlaying?.videoId != item.videoId {
            prefetchPlaybackRetryUsed = false
            streamTimeoutReextractUsed = false
        }
        lastError = nil
        needsLoginForPlayback = false
        captionTracks = []
        playingFromPrefetch = false
        nearEndPrefetchVerifiedVideoId = nil
        lastNearEndPrefetchCheckAt = nil
        PlayProbe.log(
            "play.request",
            videoId: item.videoId,
            "title=\(item.title.prefix(48)) index=\(queueIndex)/\(queue.count)"
        )
        clearHLSQualityState()
        cancelScheduledNextPrefetch()
        AdSceneLifecycle.cancelPlayStartInterstitial()
        AdSceneLifecycle.recordFirstInteraction(source: "play_request")
        PlaybackPrefetcher.shared.retainOnly(videoId: item.videoId)
        isSeekInProgress = false
        seekGeneration += 1
        let knownArtistId = libraryStore?.track(id: item.videoId)?.primaryArtistId
        let knownAvatar = item.channelAvatarURL
            ?? libraryStore?.subscribedChannel(id: knownArtistId ?? "")?.avatarUrl.flatMap(URL.init(string:))
        nowPlaying = NowPlayingItem(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURL: item.thumbnailURL,
            durationText: item.durationText,
            channelId: knownArtistId,
            channelAvatarURL: knownAvatar
        )
        refreshFavoriteState()
        refreshSubscribeState()
        isBuffering = true
        positionSeconds = pendingSeekSeconds
        if pendingSeekSeconds <= 0 {
            durationSeconds = 0
        }
        updateNowPlayingInfo()
        refreshRemoteCommandEnabled()
        extractGeneration += 1
        let generation = extractGeneration
        let expectedVideoId = item.videoId
        let preferLiveHLS = item.isLive
        let canConsumePrefetch = allowPrefetchConsume && !preferLiveHLS
        extractTask?.cancel()
        extractTask = Task {
            do {
                PlayProbe.log(
                    "play.extract.begin",
                    videoId: expectedVideoId,
                    "isLive=\(item.isLive) allowPrefetch=\(canConsumePrefetch)"
                )
                let playback: VideoPlayback
                var usedPrefetch = false
                var warmedPlayerItem: AVPlayerItem?
                if canConsumePrefetch,
                   let warmed = NextTrackWarmup.shared.consume(videoId: expectedVideoId)
                {
                    playback = warmed.playback
                    warmedPlayerItem = warmed.playerItem
                    usedPrefetch = true
                    // Drop extract cache; playback metadata came from the warm bundle.
                    PlaybackPrefetcher.shared.invalidate(videoId: expectedVideoId)
                } else if canConsumePrefetch,
                          let prefetched = await PlaybackPrefetcher.shared.consume(videoId: expectedVideoId)
                {
                    playback = prefetched
                    usedPrefetch = true
                } else {
                    playback = try await extractPlaybackWithRetry(
                        videoId: expectedVideoId,
                        preferLiveHLS: preferLiveHLS
                    )
                }
                PlayProbe.log(
                    "play.extract.ok",
                    videoId: playback.videoId,
                    "formats=\(playback.formats.count) hls=\(playback.hlsManifestURL != nil) prefetch=\(usedPrefetch) warm=\(warmedPlayerItem != nil)"
                )
                guard generation == extractGeneration,
                      !Task.isCancelled,
                      isCurrentExtractTarget(expectedVideoId)
                else {
                    PlayProbe.log("play.extract.stale", videoId: expectedVideoId)
                    return
                }
                let durationText = DurationFormat.text(seconds: playback.durationSeconds)
                    ?? item.durationText
                let channelId = playback.channelId ?? knownArtistId
                let avatar = knownAvatar
                    ?? libraryStore?.subscribedChannel(id: channelId ?? "")?.avatarUrl.flatMap(URL.init(string:))
                let playing = NowPlayingItem(
                    videoId: playback.videoId,
                    title: playback.title == playback.videoId ? item.title : playback.title,
                    channelName: playback.channelName.isEmpty ? item.channelName : playback.channelName,
                    thumbnailURL: playback.thumbnailURL ?? item.thumbnailURL,
                    durationText: durationText,
                    channelId: channelId,
                    channelAvatarURL: avatar
                )
                nowPlaying = playing
                captionTracks = playback.captionTracks
                refreshSubscribeState()
                guard let url = playback.preferredStreamURL(preferVideo: true)
                    ?? playback.preferredStreamURL(preferVideo: false)
                else {
                    PlayProbe.log(
                        "play.stream.fail",
                        videoId: expectedVideoId,
                        "no muxed/hls url (\(playback.preferredStreamDescription())) formats=\(playback.formats.count)"
                    )
                    throw ExtractorBridge.ExtractorError.invalidResponse("no playable url")
                }
                let host = url.host ?? "?"
                PlayProbe.log(
                    "play.stream.select",
                    videoId: expectedVideoId,
                    "\(playback.preferredStreamDescription()) \(PlayProbe.streamSummary(url: url)) prefetch=\(usedPrefetch) warm=\(warmedPlayerItem != nil)"
                )
                guard generation == extractGeneration, isCurrentExtractTarget(expectedVideoId) else { return }
                lastError = nil
                playingFromPrefetch = usedPrefetch
                if usedPrefetch {
                    prefetchPlaybackRetryUsed = false
                }
                let source: String
                if warmedPlayerItem != nil {
                    source = "warm"
                } else if usedPrefetch {
                    source = "prefetch"
                } else {
                    source = "cold"
                }
                PlayProbe.log(
                    "play.avplayer.start",
                    videoId: expectedVideoId,
                    "source=\(source) host=\(host) \(PlayProbe.streamSummary(url: url))"
                )
                if let warmedPlayerItem {
                    probeMarkStreamOpen(url: url, source: source)
                    PlayProbe.log(
                        "stream.open",
                        videoId: expectedVideoId,
                        "source=\(source) \(PlayProbe.streamSummary(url: url))"
                    )
                    play(playerItem: warmedPlayerItem, resumePlaying: true, seekTo: nil)
                } else {
                    play(url: url)
                }
                if let master = playback.hlsManifestURL, url == master {
                    beginHLSQualityLoading(
                        masterURL: master,
                        videoId: expectedVideoId,
                        generation: generation
                    )
                }
                let seekTo = pendingSeekSeconds
                pendingSeekSeconds = 0
                if seekTo > 1 {
                    seek(to: seekTo)
                }
                libraryStore?.recordPlayback(playing, durationSeconds: playback.durationSeconds)
                onPlaybackStarted?(playing)
                refreshFavoriteState()
                persistSession(immediate: true)
                PlayProbe.log("play.ok", videoId: expectedVideoId)
                // Prefetch next only after googlevideo is actually ready (see stream.ready).
                AdSceneLifecycle.schedulePlayStartInterstitial(videoId: expectedVideoId)
            } catch is CancellationError {
                AdSceneLifecycle.cancelPlayStartInterstitial()
                PlayProbe.log("play.cancelled", videoId: expectedVideoId)
                return
            } catch {
                AdSceneLifecycle.cancelPlayStartInterstitial()
                guard generation == extractGeneration,
                      !Task.isCancelled,
                      isCurrentExtractTarget(expectedVideoId)
                else { return }
                // Stop leftover stream from the previous track so we don't show
                // new metadata + old video frames alongside the error.
                player?.pause()
                player?.replaceCurrentItem(with: nil)
                isBuffering = false
                isPlaying = false
                lastError = Self.userFacingExtractError(error)
                needsLoginForPlayback = Self.isLoginRequiredExtractError(error)
                let isTimeout: Bool = {
                    if case ExtractorBridge.ExtractorError.timeout = error { return true }
                    let lower = error.localizedDescription.lowercased()
                    return lower.contains("timed out") || lower.contains("timeout")
                }()
                PlayProbe.log(
                    isTimeout ? "play.fail.timeout" : "play.fail",
                    videoId: expectedVideoId,
                    "raw=\(error.localizedDescription) ui=\(lastError ?? "-") needsLogin=\(needsLoginForPlayback) \(PlayProbe.concurrencySnapshot())"
                )
                updateNowPlayingInfo()
                refreshRemoteCommandEnabled()
            }
        }
    }

    private func isCurrentExtractTarget(_ videoId: String) -> Bool {
        if nowPlaying?.videoId == videoId { return true }
        return queue.indices.contains(queueIndex) && queue[queueIndex].videoId == videoId
    }

    private func extractPlaybackWithRetry(
        videoId: String,
        preferLiveHLS: Bool = false
    ) async throws -> VideoPlayback {
        let t0 = PlayProbe.now()
        do {
            return try await ExtractorBridge.shared.extractPlayback(
                videoId: videoId,
                preferLiveHLS: preferLiveHLS
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            // Timeout already spent ~45s+; a full retry roughly doubles user-visible failures.
            if case ExtractorBridge.ExtractorError.timeout = error {
                PlayProbe.log(
                    "play.extract.timeout.no_retry",
                    videoId: videoId,
                    "ms=\(PlayProbe.ms(since: t0))"
                )
                throw error
            }
            let lower = error.localizedDescription.lowercased()
            if lower.contains("timed out") || lower.contains("timeout") {
                PlayProbe.log(
                    "play.extract.timeout.no_retry",
                    videoId: videoId,
                    "ms=\(PlayProbe.ms(since: t0)) err=\(error.localizedDescription)"
                )
                throw error
            }
            PlayProbe.log(
                "play.extract.retry",
                videoId: videoId,
                "ms=\(PlayProbe.ms(since: t0)) err=\(error.localizedDescription)"
            )
            // One retry helps transient music=null / deposit failures on large player JSON.
            try await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { throw CancellationError() }
            return try await ExtractorBridge.shared.extractPlayback(
                videoId: videoId,
                preferLiveHLS: preferLiveHLS
            )
        }
    }

    private static func userFacingExtractError(_ error: Error) -> String {
        let raw = error.localizedDescription
            .replacingOccurrences(of: "__notRetry@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        if isLoginRequiredMessage(lower) {
            return "Sign in required to play"
        }
        if lower == "unplayable" || lower.contains("unplayable") {
            return "This video can't be played"
        }
        if raw.isEmpty {
            return "Unable to extract playable stream"
        }
        return raw
    }

    private static func isLoginRequiredExtractError(_ error: Error) -> Bool {
        isLoginRequiredMessage(error.localizedDescription.lowercased())
    }

    private static func isLoginRequiredMessage(_ lower: String) -> Bool {
        lower.contains("login required")
            || lower.contains("login_required")
            || lower.contains("sign in to confirm")
            || lower.contains("sign in required")
    }

    /// Re-run extraction for the current queue item (e.g. after Google sign-in).
    func retryCurrentAfterAuth() {
        guard !queue.isEmpty, queue.indices.contains(queueIndex) else { return }
        playCurrentQueueItem()
    }

    func play(url: URL) {
        play(url: url, resumePlaying: true, seekTo: nil)
    }

    /// Switch HLS quality. `nil` = Auto (master playlist).
    func selectHLSVariant(_ variantID: String?) {
        guard let master = currentHLSMasterURL else { return }
        let videoId = nowPlaying?.videoId
        if variantID == selectedHLSVariantID { return }

        let targetURL: URL
        if let variantID {
            guard let variant = hlsVariants.first(where: { $0.id == variantID }) else { return }
            targetURL = variant.url
            PlayProbe.log(
                "hls.quality.select",
                videoId: videoId,
                "variant=\(variant.displayLabel) bw=\(variant.bandwidth)"
            )
        } else {
            targetURL = master
            PlayProbe.log("hls.quality.select", videoId: videoId, "auto")
        }

        let wasPlaying = isPlaying
        let seekTo = seekablePositionForQualitySwitch()
        selectedHLSVariantID = variantID
        isBuffering = true
        play(url: targetURL, resumePlaying: wasPlaying, seekTo: seekTo)
    }

    private func play(url: URL, resumePlaying: Bool, seekTo: Double?) {
        // googlevideo rejects bare AVPlayerItem(url:) without Referer/UA → "Cannot Open".
        probeMarkStreamOpen(url: url, source: "cold")
        PlayProbe.log(
            "stream.open",
            videoId: nowPlaying?.videoId,
            "source=cold \(PlayProbe.streamSummary(url: url))"
        )
        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": YouTubeConstants.streamPlaybackHeaders]
        )
        let avItem = AVPlayerItem(asset: asset)
        play(playerItem: avItem, resumePlaying: resumePlaying, seekTo: seekTo)
    }

    private func play(playerItem avItem: AVPlayerItem, resumePlaying: Bool, seekTo: Double?) {
        // Warm path may call play(playerItem:) directly; ensure probe has a start if missing.
        if probeStreamStartedAt == nil,
           let assetURL = (avItem.asset as? AVURLAsset)?.url
        {
            probeMarkStreamOpen(url: assetURL, source: "warm")
            PlayProbe.log(
                "stream.open",
                videoId: nowPlaying?.videoId,
                "source=warm \(PlayProbe.streamSummary(url: assetURL))"
            )
        }
        observePlayerItem(avItem, videoId: nowPlaying?.videoId)
        if let player {
            player.replaceCurrentItem(with: avItem)
        } else {
            player = AVPlayer(playerItem: avItem)
            attachTimeObserver()
            attachEndObserver()
        }
        player?.allowsExternalPlayback = true
        player?.usesExternalPlaybackWhileExternalScreenIsActive = true
        lastError = nil
        needsLoginForPlayback = false
        isBuffering = false
        applySpeed()
        if resumePlaying {
            player?.play()
            isPlaying = true
        } else {
            player?.pause()
            isPlaying = false
        }
        if let seekTo, seekTo > 1 {
            seek(to: seekTo)
        }
        updateNowPlayingInfo()
    }

    /// Probe-only bookkeeping for stream open latency.
    private func probeMarkStreamOpen(url: URL, source: String) {
        probeStreamStartedAt = PlayProbe.now()
        probeStreamURL = url
        probeStreamSource = source
    }

    private func probeStreamElapsedMs() -> Int {
        guard let t0 = probeStreamStartedAt else { return -1 }
        return PlayProbe.ms(since: t0)
    }

    private func probeStreamDetailSuffix() -> String {
        let urlPart = probeStreamURL.map { PlayProbe.streamSummary(url: $0) } ?? "host=-"
        return "source=\(probeStreamSource) openMs=\(probeStreamElapsedMs()) \(urlPart) fromPrefetch=\(playingFromPrefetch) prefetchRetry=\(prefetchPlaybackRetryUsed) timeoutRetry=\(streamTimeoutReextractUsed)"
    }

    private func beginHLSQualityLoading(masterURL: URL, videoId: String, generation: Int) {
        currentHLSMasterURL = masterURL
        selectedHLSVariantID = nil
        hlsVariants = []
        hlsVariantsLoadFailed = false
        isLoadingHLSVariants = true
        hlsVariantsTask?.cancel()
        hlsVariantsTask = Task { [weak self] in
            guard let self else { return }
            #if DEBUG
            HLSMasterPlaylistParser.debugSelfCheck()
            #endif
            let result = await YouTubeHTTPClient.shared.request(
                url: masterURL.absoluteString,
                method: "GET",
                headers: YouTubeConstants.streamPlaybackHeaders,
                body: nil
            )
            guard generation == self.extractGeneration,
                  self.nowPlaying?.videoId == videoId,
                  !Task.isCancelled
            else { return }
            guard result.success, !result.body.isEmpty else {
                PlayProbe.log(
                    "hls.quality.load.fail",
                    videoId: videoId,
                    result.errMsg.isEmpty ? "empty body" : result.errMsg
                )
                self.isLoadingHLSVariants = false
                self.hlsVariantsLoadFailed = true
                return
            }
            let variants = HLSMasterPlaylistParser.parse(
                playlist: result.body,
                baseURL: masterURL
            )
            guard generation == self.extractGeneration,
                  self.nowPlaying?.videoId == videoId
            else { return }
            self.hlsVariants = variants
            self.isLoadingHLSVariants = false
            self.hlsVariantsLoadFailed = false
            PlayProbe.log(
                "hls.quality.loaded",
                videoId: videoId,
                "count=\(variants.count) labels=\(variants.prefix(5).map(\.displayLabel).joined(separator: ","))"
            )
        }
    }

    private func clearHLSQualityState() {
        hlsVariantsTask?.cancel()
        hlsVariantsTask = nil
        currentHLSMasterURL = nil
        hlsVariants = []
        selectedHLSVariantID = nil
        isLoadingHLSVariants = false
        hlsVariantsLoadFailed = false
    }

    /// Next queue item for prefetch (honors Repeat All wrap).
    private func nextPrefetchQueueItem() -> VideoItem? {
        guard !queue.isEmpty else { return nil }
        // Repeat One replays the already-loaded current item and has no next target.
        guard repeatMode != .one else { return nil }
        if queueIndex + 1 < queue.count {
            return queue[queueIndex + 1]
        }
        if repeatMode == .all, queue.count > 1 {
            return queue[0]
        }
        return nil
    }

    /// Reconcile extract prefetch and AVPlayerItem warm-up after repeat/shuffle changes.
    private func rescheduleNextTrackPreparation(previousTargetId: String?) {
        cancelScheduledNextPrefetch()
        nearEndPrefetchVerifiedVideoId = nil
        lastNearEndPrefetchCheckAt = nil

        let next = nextPrefetchQueueItem()
        let nextId = next?.videoId
        if let previousTargetId, previousTargetId != nextId {
            PlaybackPrefetcher.shared.invalidate(videoId: previousTargetId)
        }

        guard let currentId = nowPlaying?.videoId,
              player?.currentItem?.status == .readyToPlay,
              let next,
              !next.isLive
        else { return }

        PlayProbe.log(
            "prefetch.mode_change",
            videoId: next.videoId,
            "repeat=\(repeatMode.rawValue) shuffle=\(shuffleEnabled)"
        )
        scheduleNextTrackPrefetch(afterCurrentVideoId: currentId)
    }

    /// Prefetch next VOD extract, then warm its AVPlayerItem when ready.
    /// Call only after the current track reaches `stream.ready` so we do not contend
    /// with the first googlevideo open.
    private func scheduleNextTrackPrefetch(afterCurrentVideoId currentId: String) {
        cancelScheduledNextPrefetch()
        // Live HLS current track: skip (bridge busy / next may also be live).
        if isPlayingHLS { return }
        guard let next = nextPrefetchQueueItem(), !next.isLive else { return }
        let nextId = next.videoId
        nextPrefetchScheduleTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard self.nowPlaying?.videoId == currentId else { return }
            guard !self.isPlayingHLS else { return }
            guard let stillNext = self.nextPrefetchQueueItem(),
                  stillNext.videoId == nextId,
                  !stillNext.isLive
            else { return }
            PlayProbe.log(
                "prefetch.schedule",
                videoId: nextId,
                "afterReady current=\(currentId)"
            )
            PlaybackPrefetcher.shared.prefetch(videoId: nextId, preferLiveHLS: false)
            await self.warmNextTrackIfPossible(videoId: nextId, currentId: currentId)
        }
    }

    private func warmNextTrackIfPossible(videoId nextId: String, currentId: String) async {
        guard let playback = await PlaybackPrefetcher.shared.waitUntilReady(videoId: nextId)
        else { return }
        guard !Task.isCancelled else { return }
        guard nowPlaying?.videoId == currentId else { return }
        guard nextPrefetchQueueItem()?.videoId == nextId else { return }
        NextTrackWarmup.shared.warm(videoId: nextId, playback: playback)
    }

    private func cancelScheduledNextPrefetch() {
        nextPrefetchScheduleTask?.cancel()
        nextPrefetchScheduleTask = nil
    }

    private func refreshNextPrefetchIfNeeded() {
        guard !isPlayingHLS else { return }
        guard let next = nextPrefetchQueueItem(), !next.isLive else { return }
        let nextId = next.videoId
        let warmBefore = NextTrackWarmup.shared.readyVideoId
        PlaybackPrefetcher.shared.refreshIfStale(videoId: nextId, preferLiveHLS: false)
        // After a mid-song refresh, rebuild the warm item when extract finishes.
        if warmBefore == nextId, NextTrackWarmup.shared.readyVideoId != nextId,
           let currentId = nowPlaying?.videoId
        {
            nextPrefetchScheduleTask?.cancel()
            nextPrefetchScheduleTask = Task { [weak self] in
                await self?.warmNextTrackIfPossible(videoId: nextId, currentId: currentId)
            }
        }
    }

    /// During the final minute, ensure next extract is fresh and its AVPlayerItem is warmed.
    private func checkNextPrefetchNearEnd(position: Double, duration: Double?) {
        guard !isPlayingHLS,
              let duration,
              duration.isFinite,
              duration > 0,
              position.isFinite,
              duration - position <= 60,
              let next = nextPrefetchQueueItem(),
              !next.isLive
        else { return }

        let nextId = next.videoId
        if NextTrackWarmup.shared.readyVideoId == nextId {
            nearEndPrefetchVerifiedVideoId = nextId
            return
        }

        let now = Date()
        if let last = lastNearEndPrefetchCheckAt,
           now.timeIntervalSince(last) < 3
        {
            return
        }
        lastNearEndPrefetchCheckAt = now

        if PlaybackPrefetcher.shared.ensureCompletedAndValid(
            videoId: nextId,
            preferLiveHLS: false
        ), let playback = PlaybackPrefetcher.shared.peekReady(videoId: nextId) {
            NextTrackWarmup.shared.warm(videoId: nextId, playback: playback)
            if NextTrackWarmup.shared.readyVideoId == nextId {
                nearEndPrefetchVerifiedVideoId = nextId
            }
        } else if let currentId = nowPlaying?.videoId {
            nextPrefetchScheduleTask?.cancel()
            nextPrefetchScheduleTask = Task { [weak self] in
                await self?.warmNextTrackIfPossible(videoId: nextId, currentId: currentId)
            }
        }
    }

    /// Seekable VOD/DVR window position; nil for open live edge (no restore).
    private func seekablePositionForQualitySwitch() -> Double? {
        guard let item = player?.currentItem else { return nil }
        let ranges = item.seekableTimeRanges.compactMap { $0.timeRangeValue }
        guard let range = ranges.last else { return nil }
        let start = range.start.seconds
        let end = (range.start + range.duration).seconds
        let pos = positionSeconds
        // Live edge: near end of window → don't seek (stay at live).
        if end.isFinite, end - pos < 8 { return nil }
        if pos.isFinite, pos > start + 1 { return pos }
        return nil
    }

    private func observePlayerItem(_ item: AVPlayerItem, videoId: String?) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .unknown:
                    PlayProbe.log(
                        "avplayer.status",
                        videoId: videoId,
                        "unknown \(self.probeStreamDetailSuffix())"
                    )
                case .readyToPlay:
                    PlayProbe.log(
                        "stream.ready",
                        videoId: videoId,
                        "duration=\(item.duration.seconds) \(self.probeStreamDetailSuffix())"
                    )
                    PlayProbe.log(
                        "avplayer.status",
                        videoId: videoId,
                        "readyToPlay duration=\(item.duration.seconds) openMs=\(self.probeStreamElapsedMs())"
                    )
                    // Current media is open — only now prefetch the next track.
                    if let videoId, self.nowPlaying?.videoId == videoId {
                        self.scheduleNextTrackPrefetch(afterCurrentVideoId: videoId)
                    }
                case .failed:
                    let ns = item.error as NSError?
                    let underlying = (ns?.userInfo[NSUnderlyingErrorKey] as? NSError)
                        .map { "underlying=\($0.domain)/\($0.code) \($0.localizedDescription)" } ?? ""
                    let err = item.error?.localizedDescription ?? "unknown"
                    let flags = PlayProbe.networkFailFlags(item.error)
                    let isTimeout = PlayProbe.isNetworkTimeout(item.error)
                    PlayProbe.log(
                        "stream.fail",
                        videoId: videoId,
                        "\(flags) err=\(err) \(underlying) \(self.probeStreamDetailSuffix())"
                    )
                    PlayProbe.log(
                        "avplayer.status",
                        videoId: videoId,
                        "failed err=\(err) domain=\(ns?.domain ?? "") code=\(ns?.code ?? -1) \(flags) openMs=\(self.probeStreamElapsedMs()) \(underlying)"
                    )
                    // Fixed HLS variant failed → fall back to Auto (master).
                    if self.selectedHLSVariantID != nil, let master = self.currentHLSMasterURL {
                        PlayProbe.log(
                            "stream.rechain",
                            videoId: videoId,
                            "reason=hls_variant_fail → auto master=\(master.host ?? "?") \(flags)"
                        )
                        PlayProbe.log("hls.quality.fallback_auto", videoId: videoId, err)
                        self.selectedHLSVariantID = nil
                        self.lastError = nil
                        self.play(url: master, resumePlaying: true, seekTo: nil)
                        return
                    }
                    // Prefetched URL expired / rejected → one fresh extract.
                    if self.playingFromPrefetch,
                       !self.prefetchPlaybackRetryUsed,
                       let videoId,
                       self.nowPlaying?.videoId == videoId
                    {
                        PlayProbe.log(
                            "stream.rechain",
                            videoId: videoId,
                            "reason=prefetch_fail → reextract \(flags) openMs=\(self.probeStreamElapsedMs())"
                        )
                        PlayProbe.log("prefetch.playback_fail", videoId: videoId, err)
                        self.playingFromPrefetch = false
                        self.prefetchPlaybackRetryUsed = true
                        self.lastError = nil
                        self.isBuffering = true
                        self.cancelScheduledNextPrefetch()
                        PlaybackPrefetcher.shared.invalidate(videoId: videoId)
                        self.playCurrentQueueItem(allowPrefetchConsume: false)
                        return
                    }
                    // googlevideo open timed out → one re-extract to swap CDN host / URL.
                    if isTimeout,
                       !self.streamTimeoutReextractUsed,
                       let videoId,
                       self.nowPlaying?.videoId == videoId
                    {
                        PlayProbe.log(
                            "stream.rechain",
                            videoId: videoId,
                            "reason=timeout → reextract \(flags) openMs=\(self.probeStreamElapsedMs()) host=\(self.probeStreamURL?.host ?? "-")"
                        )
                        self.streamTimeoutReextractUsed = true
                        self.playingFromPrefetch = false
                        self.lastError = nil
                        self.isBuffering = true
                        self.cancelScheduledNextPrefetch()
                        PlaybackPrefetcher.shared.invalidate(videoId: videoId)
                        NextTrackWarmup.shared.invalidate(videoId: videoId)
                        self.playCurrentQueueItem(allowPrefetchConsume: false)
                        return
                    }
                    PlayProbe.log(
                        "stream.rechain.skip",
                        videoId: videoId,
                        "reason=none fromPrefetch=\(self.playingFromPrefetch) prefetchRetry=\(self.prefetchPlaybackRetryUsed) timeoutRetry=\(self.streamTimeoutReextractUsed) hlsVariant=\(self.selectedHLSVariantID != nil) \(flags)"
                    )
                    self.isBuffering = false
                    self.isPlaying = false
                    self.lastError = err
                    self.updateNowPlayingInfo()
                    self.refreshRemoteCommandEnabled()
                @unknown default:
                    PlayProbe.log("avplayer.status", videoId: videoId, "other")
                }
            }
        }

        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let err = error?.localizedDescription ?? "failedToPlayToEnd"
            let flags = PlayProbe.networkFailFlags(error)
            Task { @MainActor in
                PlayProbe.log(
                    "avplayer.failToEnd",
                    videoId: videoId,
                    "\(flags) err=\(err) \(self?.probeStreamDetailSuffix() ?? "")"
                )
                self?.isPlaying = false
                self?.lastError = err
                self?.updateNowPlayingInfo()
                self?.refreshRemoteCommandEnabled()
            }
        }
    }

    func togglePlayPause() {
        // After extract/play failure (or cold restore with no item), retry loading.
        // Always go through `playCurrentQueueItem` so `isBuffering` shows the canvas spinner.
        let needsReload = lastError != nil
            || player == nil
            || player?.currentItem == nil
        if needsReload {
            guard nowPlaying != nil, !queue.isEmpty else { return }
            playCurrentQueueItem()
            return
        }
        if isPlaying {
            pause()
        } else {
            player?.playImmediately(atRate: playbackSpeed)
            isPlaying = true
            updateNowPlayingInfo()
            persistSession(immediate: true)
        }
    }

    /// Pause without clearing queue / now playing (used by sleep timer).
    func pause() {
        guard player != nil else {
            isPlaying = false
            return
        }
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        persistSession(immediate: true)
    }

    /// Start a wall-clock sleep timer (`nil` / `0` = Off).
    func setSleepTimer(minutes: Int?) {
        guard let minutes, minutes > 0 else {
            cancelSleepTimer()
            return
        }
        sleepTimerMinutes = minutes
        sleepTimerEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        progress.bumpSleepTimerTick()
        startSleepTimerTicker()
    }

    func cancelSleepTimer() {
        sleepTimerEndsAt = nil
        sleepTimerMinutes = nil
        sleepTimerCancellable?.cancel()
        sleepTimerCancellable = nil
    }

    func stop() {
        extractTask?.cancel()
        cancelScheduledNextPrefetch()
        PlaybackPrefetcher.shared.clear()
        playingFromPrefetch = false
        prefetchPlaybackRetryUsed = false
        streamTimeoutReextractUsed = false
        isSeekInProgress = false
        seekGeneration += 1
        clearHLSQualityState()
        artworkGeneration += 1
        artworkTask?.cancel()
        artworkImage = nil
        artworkVideoId = nil
        cancelSleepTimer()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        isBuffering = false
        nowPlaying = nil
        captionTracks = []
        queue = []
        queueIndex = 0
        sourcePlaylistId = nil
        originalOrder = nil
        // Keep shuffle/repeat mode preferences across stop (Android keeps them on clear of items
        // only when wiping session; clearing queue via end-of-list OFF also resets below).
        positionSeconds = 0
        durationSeconds = 0
        pendingSeekSeconds = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        refreshRemoteCommandEnabled()
        PlaybackSessionStore.clear()
    }

    /// End-of-queue with Repeat Off — mirrors Android `handlePlaybackEnded` clear path.
    private func stopAndClearQueueForRepeatOff() {
        extractTask?.cancel()
        cancelScheduledNextPrefetch()
        PlaybackPrefetcher.shared.clear()
        playingFromPrefetch = false
        prefetchPlaybackRetryUsed = false
        streamTimeoutReextractUsed = false
        isSeekInProgress = false
        seekGeneration += 1
        clearHLSQualityState()
        artworkGeneration += 1
        artworkTask?.cancel()
        artworkImage = nil
        artworkVideoId = nil
        cancelSleepTimer()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        isBuffering = false
        nowPlaying = nil
        captionTracks = []
        queue = []
        queueIndex = 0
        sourcePlaylistId = nil
        originalOrder = nil
        shuffleEnabled = false
        repeatMode = .off
        positionSeconds = 0
        durationSeconds = 0
        pendingSeekSeconds = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        refreshRemoteCommandEnabled()
        PlaybackSessionStore.clear()
    }

    func seek(to seconds: Double) {
        let upper = durationSeconds > 0 ? durationSeconds : seconds
        let clamped = min(max(0, seconds), upper)
        seekGeneration += 1
        let generation = seekGeneration
        isSeekInProgress = true
        positionSeconds = clamped
        updateNowPlayingInfo()

        guard let player else {
            isSeekInProgress = false
            return
        }

        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        // Zero tolerance avoids "near enough" snaps that feel like the thumb jumped back.
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                guard generation == self.seekGeneration else { return }
                self.isSeekInProgress = false
                if finished {
                    let actual = player.currentTime().seconds
                    if actual.isFinite {
                        self.positionSeconds = actual
                    }
                    self.updateNowPlayingInfo()
                }
            }
        }
    }

    /// Relative seek for overlay skip controls (e.g. −15s / +30s). No-op for live HLS.
    func seekRelative(by deltaSeconds: Double) {
        guard !isPlayingHLS else { return }
        seek(to: positionSeconds + deltaSeconds)
    }

    private func applySpeed() {
        guard isPlaying else {
            player?.rate = 0
            return
        }
        player?.playImmediately(atRate: playbackSpeed)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {}
    }

    private func configureAudioInterruptions() {
        let center = NotificationCenter.default
        if let interruptionObserver {
            center.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            center.removeObserver(routeChangeObserver)
        }
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleAudioInterruption(note)
            }
        }
        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleRouteChange(note)
            }
        }
    }

    private func handleAudioInterruption(_ note: Notification) {
        guard let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            resumeAfterInterruption = isPlaying
            pause()
            updateNowPlayingInfo()
        case .ended:
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume), resumeAfterInterruption {
                resumeAfterInterruption = false
                if player != nil, !isPlaying {
                    player?.playImmediately(atRate: playbackSpeed)
                    isPlaying = true
                }
            } else {
                resumeAfterInterruption = false
            }
            updateNowPlayingInfo()
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }
        if reason == .oldDeviceUnavailable {
            pause()
            updateNowPlayingInfo()
        }
    }

    private func attachTimeObserver() {
        guard let player else { return }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let duration: Double? = {
                    guard let d = player.currentItem?.duration.seconds, d.isFinite else { return nil }
                    return d
                }()
                if let duration {
                    self.progress.setDuration(duration)
                }
                // During an in-flight seek, `currentTime` often still reports the old
                // position (especially when scrubbing past the buffered range).
                if !self.isSeekInProgress {
                    let position = time.seconds.isFinite ? time.seconds : 0
                    self.progress.setPosition(position)
                    self.checkNextPrefetchNearEnd(position: position, duration: duration)
                }
                self.checkSleepTimerExpired()
                self.refreshNextPrefetchIfNeeded()
                self.updateNowPlayingElapsed()
                self.persistSession(immediate: false)
            }
        }
    }

    private func startSleepTimerTicker() {
        sleepTimerCancellable?.cancel()
        sleepTimerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                self.progress.bumpSleepTimerTick(now)
                self.checkSleepTimerExpired()
            }
    }

    private func checkSleepTimerExpired() {
        guard let sleepTimerEndsAt else { return }
        guard Date() >= sleepTimerEndsAt else { return }
        pause()
        cancelSleepTimer()
    }

    private func attachEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }
    }

    /// Android `GlobalPlaybackViewModel.handlePlaybackEnded`.
    private func handlePlaybackEnded() {
        if let videoId = nowPlaying?.videoId {
            ReviewPromptCoordinator.shared.recordCompletedPlay(videoId: videoId)
        }
        if repeatMode == .one {
            seek(to: 0)
            player?.playImmediately(atRate: playbackSpeed)
            isPlaying = true
            updateNowPlayingInfo()
            return
        }
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            playCurrentQueueItem()
            return
        }
        if repeatMode == .all, !queue.isEmpty {
            queueIndex = 0
            playCurrentQueueItem()
            return
        }
        stopAndClearQueueForRepeatOff()
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Self.runOnMain {
                guard let self else { return .commandFailed }
                if !self.isPlaying { self.togglePlayPause() }
                return .success
            }
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Self.runOnMain {
                guard let self else { return .commandFailed }
                self.pause()
                return .success
            }
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Self.runOnMain {
                guard let self else { return .commandFailed }
                self.togglePlayPause()
                return .success
            }
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Self.runOnMain {
                guard let self else { return .commandFailed }
                guard self.hasNextInQueue else { return .commandFailed }
                self.playNext()
                return .success
            }
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Self.runOnMain {
                guard let self else { return .commandFailed }
                guard self.hasPreviousInQueue else { return .commandFailed }
                self.playPrevious()
                return .success
            }
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            Self.runOnMain {
                guard let self else { return .commandFailed }
                guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                guard self.durationSeconds > 0 else { return .commandFailed }
                self.seek(to: event.positionTime)
                return .success
            }
        }
        refreshRemoteCommandEnabled()
    }

    /// Run remote-command work on the main actor before returning status to the system.
    private nonisolated static func runOnMain(
        _ body: @MainActor () -> MPRemoteCommandHandlerStatus
    ) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        var status: MPRemoteCommandHandlerStatus = .commandFailed
        DispatchQueue.main.sync {
            status = MainActor.assumeIsolated(body)
        }
        return status
    }

    func refreshRemoteCommandEnabled() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = hasNextInQueue
        center.previousTrackCommand.isEnabled = hasPreviousInQueue
        center.changePlaybackPositionCommand.isEnabled = durationSeconds > 0
        center.playCommand.isEnabled = nowPlaying != nil
        center.pauseCommand.isEnabled = nowPlaying != nil
        center.togglePlayPauseCommand.isEnabled = nowPlaying != nil
    }

    /// Push latest Now Playing to the system (e.g. on entering background).
    func publishNowPlaying() {
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let nowPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            refreshRemoteCommandEnabled()
            return
        }
        loadArtworkIfNeeded(for: nowPlaying)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyArtist: nowPlaying.channelName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: positionSeconds,
            MPMediaItemPropertyPlaybackDuration: durationSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(playbackSpeed),
        ]
        if let artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in
                artworkImage
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        refreshRemoteCommandEnabled()
    }

    /// Lightweight elapsed/rate refresh for the periodic time observer (avoids rebuilding artwork).
    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo, nowPlaying != nil else {
            updateNowPlayingInfo()
            return
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = positionSeconds
        info[MPMediaItemPropertyPlaybackDuration] = durationSeconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackSpeed) : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        // Duration may become available after readyToPlay; keep scrub command in sync.
        let center = MPRemoteCommandCenter.shared()
        let seekEnabled = durationSeconds > 0
        if center.changePlaybackPositionCommand.isEnabled != seekEnabled {
            refreshRemoteCommandEnabled()
        }
    }

    private func loadArtworkIfNeeded(for item: NowPlayingItem) {
        guard let url = item.thumbnailURL else {
            if artworkVideoId != item.videoId {
                artworkGeneration += 1
                artworkTask?.cancel()
                artworkTask = nil
                artworkImage = nil
                artworkVideoId = item.videoId
            }
            return
        }
        if artworkVideoId == item.videoId {
            if artworkImage != nil { return }
            if artworkTask != nil { return }
        } else {
            artworkGeneration += 1
            artworkTask?.cancel()
            artworkImage = nil
            artworkVideoId = item.videoId
        }
        artworkGeneration += 1
        let generation = artworkGeneration
        let videoId = item.videoId
        artworkTask = Task { [weak self] in
            let image = await ImageStore.shared.image(for: url, maxPixelSize: 640)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.artworkGeneration == generation,
                      self.nowPlaying?.videoId == videoId
                else { return }
                self.artworkImage = image
                self.artworkVideoId = videoId
                self.artworkTask = nil
                if image != nil {
                    self.updateNowPlayingInfo()
                }
            }
        }
    }

    // MARK: - Session persistence (Android PlaybackSessionStore)

    private func restoreSession() {
        guard let snapshot = PlaybackSessionStore.load(), !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { $0.toVideoItem() }
        queue = items
        queueIndex = snapshot.currentIndex.clamped(to: 0...(items.count - 1))
        sourcePlaylistId = snapshot.sourcePlaylistId
        repeatMode = snapshot.repeatMode
        shuffleEnabled = snapshot.shuffleEnabled
        originalOrder = snapshot.originalOrder?.map { $0.toVideoItem() }
        let item = items[queueIndex]
        nowPlaying = NowPlayingItem(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURL: item.thumbnailURL,
            durationText: item.durationText,
            channelId: snapshot.channelId,
            channelAvatarURL: snapshot.channelAvatarURL.flatMap(URL.init(string:))
        )
        positionSeconds = max(0, snapshot.positionSeconds)
        durationSeconds = max(0, snapshot.durationSeconds)
        pendingSeekSeconds = positionSeconds
        isPlaying = false
        isBuffering = false
        refreshFavoriteState()
        refreshSubscribeState()
        updateNowPlayingInfo()
    }

    /// Flush session immediately (e.g. app backgrounding / kill).
    func flushSession() {
        persistSession(immediate: true)
    }

    private func persistSession(immediate: Bool) {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard !Task.isCancelled else { return }
            writeSessionSnapshot()
        }
        if immediate {
            // Also write synchronously so force-quit after background still has data.
            writeSessionSnapshot()
        }
    }

    private func writeSessionSnapshot() {
        guard nowPlaying != nil, !queue.isEmpty else {
            PlaybackSessionStore.clear()
            return
        }
        let snapshot = PlaybackSessionSnapshot(
            items: queue.map(PersistedQueueItem.from),
            currentIndex: queueIndex.clamped(to: 0...(queue.count - 1)),
            sourcePlaylistId: sourcePlaylistId,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            channelId: nowPlaying?.channelId,
            channelAvatarURL: nowPlaying?.channelAvatarURL?.absoluteString,
            repeatMode: repeatMode,
            shuffleEnabled: shuffleEnabled,
            originalOrder: originalOrder?.map(PersistedQueueItem.from)
        )
        PlaybackSessionStore.save(snapshot)
    }
}

struct NowPlayingItem: Identifiable, Equatable, Sendable {
    var id: String { videoId }
    let videoId: String
    let title: String
    let channelName: String
    let thumbnailURL: URL?
    let durationText: String?
    var channelId: String?
    var channelAvatarURL: URL?

    var canSubscribeChannel: Bool {
        ChannelID.isBrowsable(channelId)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
