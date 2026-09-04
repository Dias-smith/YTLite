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
    /// True when resolve failed because YouTube asked for a signed-in session.
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

    /// Preset / custom EQ (VOD only — disabled for live HLS).
    let equalizerStore = PlaybackEqualizerStore()

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
    private var timeControlObservation: NSKeyValueObservation?
    private var resolveTask: Task<Void, Never>?
    private var hlsVariantsTask: Task<Void, Never>?
    private var nextPrepareScheduleTask: Task<Void, Never>?
    private var nearEndPrepareVerifiedVideoId: String?
    private var lastNearEndPrepareCheckAt: Date?
    private var currentHLSMasterURL: URL?
    /// True when the current AVPlayer item came from `PlaybackPreparer` (one-shot retry on fail).
    private var playingFromPrepare = false
    /// Prevents infinite prepare→fail→resolve loops.
    private var preparePlaybackRetryUsed = false
    /// One-shot re-resolve when googlevideo open times out (-1001) on cold/non-prepare play.
    private var streamTimeoutReresolveUsed = false
    /// One-shot re-resolve when AVPlayer opens but fails to decode/play (non-timeout).
    private var streamOpenReresolveUsed = false
    /// Resolved duration from the latest successful resolve (for history on first audible frame).
    private var pendingResolvedDurationSeconds: Int = 0
    /// Prevents duplicate successful-play bookkeeping for the same queue item.
    private var successfulPlaybackRecordedVideoId: String?
    /// Product analytics: where the current play request came from.
    private var analyticsPlaySource: String = "unknown"
    private var analyticsResolveStartedAt: CFAbsoluteTime?
    /// Probe-only: when current stream open began / which URL is loading.
    private var probeStreamStartedAt: CFAbsoluteTime?
    private var probeStreamURL: URL?
    private var probeStreamSource: String = "cold"
    private var persistTask: Task<Void, Never>?
    private var sleepTimerCancellable: AnyCancellable?
    /// Pre-shuffle queue snapshot (Android `originalOrder`).
    private var originalOrder: [VideoItem]?
    /// Seek target after cold-start restore + resolve.
    private var pendingSeekSeconds: Double = 0
    /// While true, time-observer must not overwrite `positionSeconds` with stale `currentTime`.
    private var isSeekInProgress = false
    /// Bumps on each `seek(to:)` so superseded completion handlers are ignored.
    private var seekGeneration: Int = 0
    /// Bumps on each `playCurrentQueueItem` so stale resolve callbacks cannot mutate UI.
    private var resolveGeneration: Int = 0
    private var artworkImage: UIImage?
    private var artworkVideoId: String?
    private var artworkTask: Task<Void, Never>?
    private var artworkGeneration: Int = 0
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var fullScreenAdDismissObserver: NSObjectProtocol?
    private var fullScreenAdPresentObserver: NSObjectProtocol?
    private var fullScreenAdKeepaliveCancellable: AnyCancellable?
    /// Resume after interruption only if we were playing when interrupted.
    private var resumeAfterInterruption = false
    /// Progressive stream eligible for local persistence after the watch threshold.
    private struct PlaybackStoreContext {
        let videoId: String
        let streamURL: URL
        let itag: Int
        let mimeType: String
    }
    private var playbackStoreContext: PlaybackStoreContext?
    private var playbackStoreThresholdMet = false

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

    /// Snapshot for AppDebugKit `/state` (DEBUG regression).
    func debugStateSnapshot() -> [String: Any] {
        let next = nextPrepareQueueItem()
        let nextId = next?.videoId
        let prepareReady: Bool = {
            guard let nextId else { return false }
            return PlaybackPreparer.shared.peekReady(videoId: nextId) != nil
        }()
        return [
            "videoId": nowPlaying?.videoId as Any,
            "title": nowPlaying?.title as Any,
            "isPlaying": isPlaying,
            "isBuffering": isBuffering,
            "queueCount": queue.count,
            "queueIndex": queueIndex,
            "repeatMode": repeatMode.rawValue,
            "shuffle": shuffleEnabled,
            "lastError": lastError as Any,
            "queueVideoIds": queue.map(\.videoId),
            "nextPrepareVideoId": nextId as Any,
            "primeReadyVideoId": NextTrackPrimer.shared.readyVideoId as Any,
            "prepareReady": prepareReady,
            "streamReady": player?.currentItem?.status == .readyToPlay,
        ]
    }

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.speedKey) as? Float
        if let stored, Self.speedOptions.contains(stored) {
            playbackSpeed = stored
        }
        activatePlaybackAudioSession()
        configureAudioInterruptions()
        configureFullScreenAdObservers()
        configureRemoteCommands()
        restoreSession()
        refreshRemoteCommandEnabled()
    }

    func play(items: [VideoItem], startAt index: Int = 0, sourcePlaylistId: String? = nil, analyticsSource: String = "unknown") {
        guard !items.isEmpty else { return }
        let start = index.clamped(to: 0...(items.count - 1))
        let selectedItem = items[start]

        // Opening the currently loaded video must not rebuild its queue, re-resolve
        // the stream, or reset progress. Only resume it when it is paused.
        if nowPlaying?.videoId == selectedItem.videoId {
            resumeCurrentPlaybackIfNeeded()
            return
        }

        analyticsPlaySource = analyticsSource
        self.sourcePlaylistId = sourcePlaylistId
        originalOrder = items
        PlaybackPreparer.shared.clear()
        cancelScheduledNextPrepare()
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

    /// Consume a song queued by tapping the daily listen notification.
    func consumePendingDailyListenIfNeeded() {
        guard let item = PendingDailyListenPlayback.consume() else { return }
        AppAnalytics.dailyListenTap()
        // Prefer the full library list so Up next stays useful after the jump.
        if let store = libraryStore {
            let songs = store.successfullyPlayedSongs()
            if let index = songs.firstIndex(where: { $0.videoId == item.videoId }) {
                play(items: songs, startAt: index, analyticsSource: "notification")
                return
            }
        }
        play(items: [item], startAt: 0, analyticsSource: "notification")
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
        let fromId = nowPlaying?.videoId ?? ""
        AppAnalytics.playSkip(fromId: fromId, toId: item.videoId)
        analyticsPlaySource = "queue"
        queueIndex = target
        pendingSeekSeconds = 0
        playCurrentQueueItem()
        persistSession(immediate: true)
    }

    private func resumeCurrentPlaybackIfNeeded() {
        guard !isPlaying else { return }
        // An in-flight resolve starts playback when it completes.
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
        play(items: [item], startAt: 0, analyticsSource: "search")
    }

    /// Manual skip — advances even in Repeat One (Android detail `skipToNext`).
    func playNext() {
        guard !queue.isEmpty else { return }
        let fromId = nowPlaying?.videoId ?? ""
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            let toId = queue[queueIndex].videoId
            AppAnalytics.playSkip(fromId: fromId, toId: toId)
            analyticsPlaySource = "queue"
            playCurrentQueueItem()
            return
        }
        if repeatMode == .all {
            queueIndex = 0
            let toId = queue[queueIndex].videoId
            AppAnalytics.playSkip(fromId: fromId, toId: toId)
            analyticsPlaySource = "queue"
            playCurrentQueueItem()
        }
    }

    /// Manual skip to the previous queue item (does not restart the current track).
    func playPrevious() {
        guard !queue.isEmpty else { return }
        let fromId = nowPlaying?.videoId ?? ""
        if queueIndex > 0 {
            queueIndex -= 1
            let toId = queue[queueIndex].videoId
            AppAnalytics.playSkip(fromId: fromId, toId: toId)
            analyticsPlaySource = "queue"
            playCurrentQueueItem()
            return
        }
        if repeatMode == .all {
            queueIndex = queue.count - 1
            let toId = queue[queueIndex].videoId
            AppAnalytics.playSkip(fromId: fromId, toId: toId)
            analyticsPlaySource = "queue"
            playCurrentQueueItem()
        }
    }

    @discardableResult
    func toggleShuffle() -> Bool {
        let previousPrepareTargetId = nextPrepareQueueItem()?.videoId
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
        rescheduleNextTrackPreparation(previousTargetId: previousPrepareTargetId)
        return shuffleEnabled
    }

    @discardableResult
    func cycleRepeatMode() -> QueueRepeatMode {
        let previousPrepareTargetId = nextPrepareQueueItem()?.videoId
        repeatMode.cycle()
        persistSession(immediate: true)
        refreshRemoteCommandEnabled()
        rescheduleNextTrackPreparation(previousTargetId: previousPrepareTargetId)
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

    private func playCurrentQueueItem(allowPrepareConsume: Bool = true) {
        guard queue.indices.contains(queueIndex) else { return }
        let item = queue[queueIndex]
        // New queue target → allow one timeout / prepare re-resolve again.
        if nowPlaying?.videoId != item.videoId {
            preparePlaybackRetryUsed = false
            streamTimeoutReresolveUsed = false
            streamOpenReresolveUsed = false
            successfulPlaybackRecordedVideoId = nil
            pendingResolvedDurationSeconds = 0
        }
        lastError = nil
        needsLoginForPlayback = false
        captionTracks = []
        playingFromPrepare = false
        nearEndPrepareVerifiedVideoId = nil
        lastNearEndPrepareCheckAt = nil
        PlayProbe.log(
            "play.request",
            videoId: item.videoId,
            "title=\(item.title.prefix(48)) index=\(queueIndex)/\(queue.count)"
        )
        AppAnalytics.playRequest(videoId: item.videoId, source: analyticsPlaySource)
        analyticsResolveStartedAt = PlayProbe.now()
        clearHLSQualityState()
        playbackStoreContext = nil
        playbackStoreThresholdMet = false
        cancelScheduledNextPrepare()
        AdSceneLifecycle.cancelPlayStartInterstitial()
        AdSceneLifecycle.recordFirstInteraction(source: "play_request")
        AdSceneLifecycle.schedulePlayStartInterstitial(videoId: item.videoId)
        PlaybackPreparer.shared.retainOnly(videoId: item.videoId)
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
        // Detach old player observers so a still-playing previous item cannot clear the spinner.
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        positionSeconds = pendingSeekSeconds
        if pendingSeekSeconds <= 0 {
            durationSeconds = 0
        }
        updateNowPlayingInfo()
        refreshRemoteCommandEnabled()
        resolveGeneration += 1
        let generation = resolveGeneration
        let expectedVideoId = item.videoId
        let preferLiveHLS = item.isLive
        let canConsumePrepare = allowPrepareConsume && !preferLiveHLS
        resolveTask?.cancel()
        resolveTask = Task {
            do {
                PlayProbe.log(
                    "play.resolve.begin",
                    videoId: expectedVideoId,
                    "isLive=\(item.isLive) allowPrepare=\(canConsumePrepare)"
                )
                if !preferLiveHLS,
                   PlaybackStorePolicy.allowsDirectOfflinePlayback,
                   let localFileURL = await PlaybackMediaStore.shared.localFileURL(videoId: expectedVideoId)
                {
                    guard generation == resolveGeneration,
                          !Task.isCancelled,
                          isCurrentResolveTarget(expectedVideoId)
                    else {
                        PlayProbe.log(SaltedLiteral.probeStale, videoId: expectedVideoId)
                        return
                    }
                    await PlaybackMediaStore.shared.touchLastPlayed(videoId: expectedVideoId)
                    lastError = nil
                    playingFromPrepare = false
                    playbackStoreContext = nil
                    playbackStoreThresholdMet = true
                    PlayProbe.log(
                        SaltedLiteral.probeHit,
                        videoId: expectedVideoId,
                        localFileURL.lastPathComponent
                    )
                    play(url: localFileURL)
                    let seekTo = pendingSeekSeconds
                    pendingSeekSeconds = 0
                    if seekTo > 1 {
                        seek(to: seekTo)
                    }
                    let resolveMs = analyticsResolveStartedAt.map { PlayProbe.ms(since: $0) } ?? 0
                    AppAnalytics.playResolveOk(
                        videoId: expectedVideoId,
                        ms: resolveMs,
                        source: SaltedLiteral.probeLocalSource
                    )
                    if let playing = nowPlaying {
                        onPlaybackStarted?(playing)
                    }
                    refreshFavoriteState()
                    persistSession(immediate: true)
                    PlayProbe.log("play.ok", videoId: expectedVideoId, "source=\(SaltedLiteral.probeLocalSource)")
                    return
                }
                let playback: VideoPlayback
                var usedPrepare = false
                var primedPlayerItem: AVPlayerItem?
                if canConsumePrepare,
                   let primed = NextTrackPrimer.shared.consume(videoId: expectedVideoId)
                {
                    playback = primed.playback
                    primedPlayerItem = primed.playerItem
                    usedPrepare = true
                    // Drop resolve store; playback metadata came from the prime bundle.
                    PlaybackPreparer.shared.invalidate(videoId: expectedVideoId)
                } else if canConsumePrepare,
                          let prepared = await PlaybackPreparer.shared.consume(videoId: expectedVideoId)
                {
                    playback = prepared
                    usedPrepare = true
                } else {
                    playback = try await resolvePlaybackWithRetry(
                        videoId: expectedVideoId,
                        preferLiveHLS: preferLiveHLS
                    )
                }
                PlayProbe.log(
                    "play.resolve.ok",
                    videoId: playback.videoId,
                    "formats=\(playback.formats.count) hls=\(playback.hlsManifestURL != nil) prepare=\(usedPrepare) prime=\(primedPlayerItem != nil)"
                )
                guard generation == resolveGeneration,
                      !Task.isCancelled,
                      isCurrentResolveTarget(expectedVideoId)
                else {
                    PlayProbe.log("play.resolve.stale", videoId: expectedVideoId)
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

                // After resolve: reuse on-disk cache when present (do not re-download / re-persist).
                if !preferLiveHLS,
                   let localFileURL = await PlaybackMediaStore.shared.localFileURL(videoId: expectedVideoId)
                {
                    guard generation == resolveGeneration,
                          !Task.isCancelled,
                          isCurrentResolveTarget(expectedVideoId)
                    else {
                        PlayProbe.log("play.resolve.stale", videoId: expectedVideoId)
                        return
                    }
                    await PlaybackMediaStore.shared.touchLastPlayed(videoId: expectedVideoId)
                    lastError = nil
                    playingFromPrepare = usedPrepare
                    pendingResolvedDurationSeconds = playback.durationSeconds
                    playbackStoreContext = nil
                    playbackStoreThresholdMet = true
                    PlayProbe.log(
                        SaltedLiteral.probeHit,
                        videoId: expectedVideoId,
                        "afterResolve \(localFileURL.lastPathComponent)"
                    )
                    play(url: localFileURL)
                    let seekTo = pendingSeekSeconds
                    pendingSeekSeconds = 0
                    if seekTo > 1 {
                        seek(to: seekTo)
                    }
                    onPlaybackStarted?(playing)
                    refreshFavoriteState()
                    persistSession(immediate: true)
                    PlayProbe.log("play.ok", videoId: expectedVideoId, "source=\(SaltedLiteral.probeLocalSource)")
                    return
                }

                guard let url = playback.preferredStreamURL(preferVideo: true)
                    ?? playback.preferredStreamURL(preferVideo: false)
                else {
                    PlayProbe.log(
                        "play.stream.fail",
                        videoId: expectedVideoId,
                        "no muxed/hls url (\(playback.preferredStreamDescription())) formats=\(playback.formats.count)"
                    )
                    throw StreamResolver.StreamResolverError.invalidResponse("no playable url")
                }
                let host = url.host ?? "?"
                PlayProbe.log(
                    "play.stream.select",
                    videoId: expectedVideoId,
                    "\(playback.preferredStreamDescription()) \(PlayProbe.streamSummary(url: url)) prepare=\(usedPrepare) prime=\(primedPlayerItem != nil)"
                )
                if let fmt = PlaybackFormatSelector.select(formats: playback.formats, preferVideo: true),
                   url == fmt.url
                {
                    playbackStoreContext = PlaybackStoreContext(
                        videoId: expectedVideoId,
                        streamURL: url,
                        itag: fmt.itag,
                        mimeType: fmt.mimeType
                    )
                    playbackStoreThresholdMet = false
                } else {
                    playbackStoreContext = nil
                    playbackStoreThresholdMet = false
                }
                guard generation == resolveGeneration, isCurrentResolveTarget(expectedVideoId) else { return }
                lastError = nil
                playingFromPrepare = usedPrepare
                pendingResolvedDurationSeconds = playback.durationSeconds
                if usedPrepare {
                    preparePlaybackRetryUsed = false
                }
                let source: String
                if primedPlayerItem != nil {
                    source = "prime"
                } else if usedPrepare {
                    source = "prepare"
                } else {
                    source = "cold"
                }
                let resolveMs = analyticsResolveStartedAt.map { PlayProbe.ms(since: $0) } ?? 0
                AppAnalytics.playResolveOk(videoId: expectedVideoId, ms: resolveMs, source: source)
                PlayProbe.log(
                    "play.avplayer.start",
                    videoId: expectedVideoId,
                    "source=\(source) host=\(host) \(PlayProbe.streamSummary(url: url))"
                )
                if let primedPlayerItem {
                    probeMarkStreamOpen(url: url, source: source)
                    PlayProbe.log(
                        "stream.open",
                        videoId: expectedVideoId,
                        "source=\(source) \(PlayProbe.streamSummary(url: url))"
                    )
                    play(playerItem: primedPlayerItem, resumePlaying: true, seekTo: nil)
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
                onPlaybackStarted?(playing)
                refreshFavoriteState()
                persistSession(immediate: true)
                PlayProbe.log("play.ok", videoId: expectedVideoId)
                // Prepare next only after googlevideo is actually ready (see stream.ready).
            } catch is CancellationError {
                AdSceneLifecycle.cancelPlayStartInterstitial()
                PlayProbe.log("play.cancelled", videoId: expectedVideoId)
                // Only clear if this resolve is still the active target (no newer play started).
                if generation == resolveGeneration, isCurrentResolveTarget(expectedVideoId) {
                    isBuffering = false
                    isPlaying = false
                }
                return
            } catch {
                AdSceneLifecycle.cancelPlayStartInterstitial()
                guard generation == resolveGeneration,
                      isCurrentResolveTarget(expectedVideoId)
                else { return }
                // Stop leftover stream from the previous track so we don't show
                // new metadata + old video frames alongside the error.
                player?.pause()
                player?.replaceCurrentItem(with: nil)
                isBuffering = false
                isPlaying = false
                lastError = Self.userFacingResolveError(error)
                needsLoginForPlayback = Self.isLoginRequiredResolveError(error)
                AppAnalytics.playResolveFail(
                    videoId: expectedVideoId,
                    error: lastError ?? error.localizedDescription,
                    needsLogin: needsLoginForPlayback
                )
                let isTimeout: Bool = {
                    if case StreamResolver.StreamResolverError.timeout = error { return true }
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

    private func isCurrentResolveTarget(_ videoId: String) -> Bool {
        if nowPlaying?.videoId == videoId { return true }
        return queue.indices.contains(queueIndex) && queue[queueIndex].videoId == videoId
    }

    private func resolvePlaybackWithRetry(
        videoId: String,
        preferLiveHLS: Bool = false
    ) async throws -> VideoPlayback {
        let t0 = PlayProbe.now()
        do {
            return try await StreamResolver.shared.resolvePlayback(
                videoId: videoId,
                preferLiveHLS: preferLiveHLS
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            // Timeout already spent ~45s+; a full retry roughly doubles user-visible failures.
            if case StreamResolver.StreamResolverError.timeout = error {
                PlayProbe.log(
                    "play.resolve.timeout.no_retry",
                    videoId: videoId,
                    "ms=\(PlayProbe.ms(since: t0))"
                )
                throw error
            }
            let lower = error.localizedDescription.lowercased()
            if lower.contains("timed out") || lower.contains("timeout") {
                PlayProbe.log(
                    "play.resolve.timeout.no_retry",
                    videoId: videoId,
                    "ms=\(PlayProbe.ms(since: t0)) err=\(error.localizedDescription)"
                )
                throw error
            }
            PlayProbe.log(
                "play.resolve.retry",
                videoId: videoId,
                "ms=\(PlayProbe.ms(since: t0)) err=\(error.localizedDescription)"
            )
            // One retry helps transient music=null / deposit failures on large player JSON.
            try await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { throw CancellationError() }
            return try await StreamResolver.shared.resolvePlayback(
                videoId: videoId,
                preferLiveHLS: preferLiveHLS
            )
        }
    }

    private static func userFacingResolveError(_ error: Error) -> String {
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
            return "Unable to resolve playable stream"
        }
        return raw
    }

    private static func isLoginRequiredResolveError(_ error: Error) -> Bool {
        isLoginRequiredMessage(error.localizedDescription.lowercased())
    }

    private static func isLoginRequiredMessage(_ lower: String) -> Bool {
        lower.contains("login required")
            || lower.contains("login_required")
            || lower.contains("sign in to confirm")
            || lower.contains("sign in required")
    }

    /// Re-run resolve for the current queue item (e.g. after Google sign-in).
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

    private func play(url: URL, resumePlaying: Bool = true, seekTo: Double? = nil) {
        let isLocalFile = url.isFileURL
        probeMarkStreamOpen(url: url, source: isLocalFile ? SaltedLiteral.probeLocalSource : "cold")
        PlayProbe.log(
            "stream.open",
            videoId: nowPlaying?.videoId,
            "source=\(isLocalFile ? SaltedLiteral.probeLocalSource : "cold") \(PlayProbe.streamSummary(url: url))"
        )
        let asset: AVURLAsset
        if isLocalFile {
            asset = AVURLAsset(url: url)
        } else {
            asset = AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": YouTubeConstants.streamPlaybackHeaders]
            )
        }
        let avItem = AVPlayerItem(asset: asset)
        play(
            playerItem: avItem,
            resumePlaying: resumePlaying,
            seekTo: seekTo,
            streamURL: url
        )
    }

    private func play(
        playerItem avItem: AVPlayerItem,
        resumePlaying: Bool,
        seekTo: Double?,
        streamURL: URL? = nil
    ) {
        activatePlaybackAudioSession()
        // Prime path may call play(playerItem:) directly; ensure probe has a start if missing.
        if probeStreamStartedAt == nil,
           let assetURL = (avItem.asset as? AVURLAsset)?.url
        {
            probeMarkStreamOpen(url: assetURL, source: "prime")
            PlayProbe.log(
                "stream.open",
                videoId: nowPlaying?.videoId,
                "source=prime \(PlayProbe.streamSummary(url: assetURL))"
            )
        }
        observePlayerItem(avItem, videoId: nowPlaying?.videoId)
        if let player {
            player.replaceCurrentItem(with: avItem)
        } else {
            let newPlayer = AVPlayer(playerItem: avItem)
            newPlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            player = newPlayer
            attachTimeObserver()
            attachEndObserver()
        }
        if let player {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            observePlayerTimeControl(player, expectedVideoId: nowPlaying?.videoId)
        }
        player?.allowsExternalPlayback = true
        player?.usesExternalPlaybackWhileExternalScreenIsActive = true
        lastError = nil
        needsLoginForPlayback = false
        // Keep `isBuffering` until the item is ready and playback has actually started
        // (see `readyToPlay` / `timeControlStatus == .playing`).
        applySpeed()
        if resumePlaying {
            player?.playImmediately(atRate: playbackSpeed)
            isPlaying = true
        } else {
            player?.pause()
            isPlaying = false
        }
        if let seekTo, seekTo > 1 {
            seek(to: seekTo)
        }
        attachEqualizer(to: avItem, streamURL: streamURL ?? (avItem.asset as? AVURLAsset)?.url)
        updateNowPlayingInfo()
    }

    /// Re-apply EQ after preset / slider / toggle changes.
    func refreshEqualizer() {
        let enabled = equalizerStore.isEnabled
        let gains = equalizerStore.activeGainsDb
        let boost = equalizerStore.volumeBoostMultiplier
        Task {
            await PlaybackEqualizerEngine.shared.apply(
                enabled: enabled,
                gainsDb: gains,
                volumeBoost: boost
            )
        }
    }

    private func attachEqualizer(to item: AVPlayerItem, streamURL: URL?) {
        let eligible = PlaybackEqualizerSupport.isEligibleStreamURL(streamURL) && !isPlayingHLS
        let enabled = equalizerStore.isEnabled
        let gains = equalizerStore.activeGainsDb
        Task {
            await PlaybackEqualizerEngine.shared.attach(to: item, eligible: eligible)
            await PlaybackEqualizerEngine.shared.apply(enabled: enabled, gainsDb: gains, volumeBoost: equalizerStore.volumeBoostMultiplier)
        }
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
        return "source=\(probeStreamSource) openMs=\(probeStreamElapsedMs()) \(urlPart) fromPrepare=\(playingFromPrepare) prepareRetry=\(preparePlaybackRetryUsed) timeoutRetry=\(streamTimeoutReresolveUsed) openRetry=\(streamOpenReresolveUsed)"
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
            guard generation == self.resolveGeneration,
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
            guard generation == self.resolveGeneration,
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

    /// Next queue item for prepare (honors Repeat All wrap).
    private func nextPrepareQueueItem() -> VideoItem? {
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

    /// Reconcile stream prepare and AVPlayerItem prime after repeat/shuffle changes.
    private func rescheduleNextTrackPreparation(previousTargetId: String?) {
        cancelScheduledNextPrepare()
        nearEndPrepareVerifiedVideoId = nil
        lastNearEndPrepareCheckAt = nil

        let next = nextPrepareQueueItem()
        let nextId = next?.videoId
        if let previousTargetId, previousTargetId != nextId {
            PlaybackPreparer.shared.invalidate(videoId: previousTargetId)
        }

        guard let currentId = nowPlaying?.videoId,
              player?.currentItem?.status == .readyToPlay,
              let next,
              !next.isLive
        else { return }

        PlayProbe.log(
            "prepare.mode_change",
            videoId: next.videoId,
            "repeat=\(repeatMode.rawValue) shuffle=\(shuffleEnabled)"
        )
        scheduleNextTrackPrepare(afterCurrentVideoId: currentId)
    }

    /// Prepare next VOD resolve, then prime its AVPlayerItem when ready.
    /// Call only after the current track reaches `stream.ready` so we do not contend
    /// with the first googlevideo open.
    private func scheduleNextTrackPrepare(afterCurrentVideoId currentId: String) {
        cancelScheduledNextPrepare()
        // Live HLS current track: skip (bridge busy / next may also be live).
        if isPlayingHLS { return }
        guard let next = nextPrepareQueueItem(), !next.isLive else { return }
        let nextId = next.videoId
        nextPrepareScheduleTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard self.nowPlaying?.videoId == currentId else { return }
            guard !self.isPlayingHLS else { return }
            guard let stillNext = self.nextPrepareQueueItem(),
                  stillNext.videoId == nextId,
                  !stillNext.isLive
            else { return }
            PlayProbe.log(
                "prepare.schedule",
                videoId: nextId,
                "afterReady current=\(currentId)"
            )
            PlaybackPreparer.shared.prepare(videoId: nextId, preferLiveHLS: false)
            await self.primeNextTrackIfPossible(videoId: nextId, currentId: currentId)
        }
    }

    private func primeNextTrackIfPossible(videoId nextId: String, currentId: String) async {
        guard let playback = await PlaybackPreparer.shared.waitUntilReady(videoId: nextId)
        else { return }
        guard !Task.isCancelled else { return }
        guard nowPlaying?.videoId == currentId else { return }
        guard nextPrepareQueueItem()?.videoId == nextId else { return }
        NextTrackPrimer.shared.prime(videoId: nextId, playback: playback)
    }

    private func cancelScheduledNextPrepare() {
        nextPrepareScheduleTask?.cancel()
        nextPrepareScheduleTask = nil
    }

    private func refreshNextPrepareIfNeeded() {
        guard !isPlayingHLS else { return }
        guard let next = nextPrepareQueueItem(), !next.isLive else { return }
        let nextId = next.videoId
        let primeBefore = NextTrackPrimer.shared.readyVideoId
        PlaybackPreparer.shared.refreshIfStale(videoId: nextId, preferLiveHLS: false)
        // After a mid-song refresh, rebuild the prime item when resolve finishes.
        if primeBefore == nextId, NextTrackPrimer.shared.readyVideoId != nextId,
           let currentId = nowPlaying?.videoId
        {
            nextPrepareScheduleTask?.cancel()
            nextPrepareScheduleTask = Task { [weak self] in
                await self?.primeNextTrackIfPossible(videoId: nextId, currentId: currentId)
            }
        }
    }

    /// After 10% watch progress, persist progressive streams for offline replay.
    private func checkPlaybackStoreThreshold(position: Double, duration: Double?) {
        guard !playbackStoreThresholdMet,
              !isPlayingHLS,
              let duration,
              duration.isFinite,
              duration > 0,
              position.isFinite,
              position / duration >= PlaybackStorePolicy.progressThreshold,
              let ctx = playbackStoreContext,
              ctx.videoId == nowPlaying?.videoId,
              PlaybackStorePolicy.isStorableDuration(seconds: duration)
        else { return }

        playbackStoreThresholdMet = true
        let videoId = ctx.videoId
        let streamURL = ctx.streamURL
        let itag = ctx.itag
        let mimeType = ctx.mimeType
        PlayProbe.log(
            SaltedLiteral.probeSchedule,
            videoId: videoId,
            "itag=\(itag) progress=\(Int((position / duration * 100).rounded()))%"
        )
        Task {
            await PlaybackMediaStore.shared.schedulePersist(
                videoId: videoId,
                sourceURL: streamURL,
                itag: itag,
                mimeType: mimeType
            )
        }
    }

    /// During the final minute, ensure next resolve is fresh and its AVPlayerItem is primed.
    private func checkNextPrepareNearEnd(position: Double, duration: Double?) {
        guard !isPlayingHLS,
              let duration,
              duration.isFinite,
              duration > 0,
              position.isFinite,
              duration - position <= 60,
              let next = nextPrepareQueueItem(),
              !next.isLive
        else { return }

        let nextId = next.videoId
        if NextTrackPrimer.shared.readyVideoId == nextId {
            nearEndPrepareVerifiedVideoId = nextId
            return
        }

        let now = Date()
        if let last = lastNearEndPrepareCheckAt,
           now.timeIntervalSince(last) < 3
        {
            return
        }
        lastNearEndPrepareCheckAt = now

        if PlaybackPreparer.shared.ensureCompletedAndValid(
            videoId: nextId,
            preferLiveHLS: false
        ), let playback = PlaybackPreparer.shared.peekReady(videoId: nextId) {
            NextTrackPrimer.shared.prime(videoId: nextId, playback: playback)
            if NextTrackPrimer.shared.readyVideoId == nextId {
                nearEndPrepareVerifiedVideoId = nextId
            }
        } else if let currentId = nowPlaying?.videoId {
            nextPrepareScheduleTask?.cancel()
            nextPrepareScheduleTask = Task { [weak self] in
                await self?.primeNextTrackIfPossible(videoId: nextId, currentId: currentId)
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

    private func observePlayerTimeControl(_ player: AVPlayer, expectedVideoId: String?) {
        timeControlObservation?.invalidate()
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                // Ignore callbacks that still belong to a previous track.
                if let expectedVideoId, self.nowPlaying?.videoId != expectedVideoId { return }
                switch player.timeControlStatus {
                case .playing:
                    guard player.currentItem?.status == .readyToPlay else { return }
                    // First audible frames — hide the resolve/open spinner.
                    self.isBuffering = false
                    self.noteSuccessfulPlaybackIfNeeded(videoId: expectedVideoId)
                case .paused:
                    if player.currentItem?.status == .readyToPlay, !self.isPlaying {
                        self.isBuffering = false
                    }
                case .waitingToPlayAtSpecifiedRate:
                    break
                @unknown default:
                    break
                }
            }
        }
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
                    // Paused load: spinner can drop once the item is ready.
                    // Playing load: wait until `timeControlStatus == .playing`.
                    if videoId == nil || self.nowPlaying?.videoId == videoId {
                        if !self.isPlaying || self.player?.timeControlStatus == .playing {
                            self.isBuffering = false
                        }
                        if self.isPlaying, self.player?.timeControlStatus == .playing {
                            self.noteSuccessfulPlaybackIfNeeded(videoId: videoId)
                        }
                    }
                    // Current media is open — only now prepare the next track.
                    if let videoId, self.nowPlaying?.videoId == videoId {
                        self.scheduleNextTrackPrepare(afterCurrentVideoId: videoId)
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
                    // Prepared URL expired / rejected → one fresh resolve.
                    if self.playingFromPrepare,
                       !self.preparePlaybackRetryUsed,
                       let videoId,
                       self.nowPlaying?.videoId == videoId
                    {
                        PlayProbe.log(
                            "stream.rechain",
                            videoId: videoId,
                            "reason=prepare_fail → reresolve \(flags) openMs=\(self.probeStreamElapsedMs())"
                        )
                        PlayProbe.log("prepare.playback_fail", videoId: videoId, err)
                        self.playingFromPrepare = false
                        self.preparePlaybackRetryUsed = true
                        self.lastError = nil
                        self.isBuffering = true
                        self.cancelScheduledNextPrepare()
                        PlaybackPreparer.shared.invalidate(videoId: videoId)
                        self.playCurrentQueueItem(allowPrepareConsume: false)
                        return
                    }
                    // googlevideo open timed out → one re-resolve to swap CDN host / URL.
                    if isTimeout,
                       !self.streamTimeoutReresolveUsed,
                       let videoId,
                       self.nowPlaying?.videoId == videoId
                    {
                        PlayProbe.log(
                            "stream.rechain",
                            videoId: videoId,
                            "reason=timeout → reresolve \(flags) openMs=\(self.probeStreamElapsedMs()) host=\(self.probeStreamURL?.host ?? "-")"
                        )
                        self.streamTimeoutReresolveUsed = true
                        self.playingFromPrepare = false
                        self.lastError = nil
                        self.isBuffering = true
                        self.cancelScheduledNextPrepare()
                        PlaybackPreparer.shared.invalidate(videoId: videoId)
                        NextTrackPrimer.shared.invalidate(videoId: videoId)
                        self.playCurrentQueueItem(allowPrepareConsume: false)
                        return
                    }
                    // Open/decode failed (e.g. OSStatus -12746) → one fresh resolve / CDN swap.
                    if !isTimeout,
                       !self.streamOpenReresolveUsed,
                       let videoId,
                       self.nowPlaying?.videoId == videoId
                    {
                        PlayProbe.log(
                            "stream.rechain",
                            videoId: videoId,
                            "reason=open_fail → reresolve \(flags) openMs=\(self.probeStreamElapsedMs()) host=\(self.probeStreamURL?.host ?? "-")"
                        )
                        self.streamOpenReresolveUsed = true
                        self.playingFromPrepare = false
                        self.lastError = nil
                        self.isBuffering = true
                        self.cancelScheduledNextPrepare()
                        PlaybackPreparer.shared.invalidate(videoId: videoId)
                        NextTrackPrimer.shared.invalidate(videoId: videoId)
                        self.playCurrentQueueItem(allowPrepareConsume: false)
                        return
                    }
                    PlayProbe.log(
                        "stream.rechain.skip",
                        videoId: videoId,
                        "reason=none fromPrepare=\(self.playingFromPrepare) prepareRetry=\(self.preparePlaybackRetryUsed) timeoutRetry=\(self.streamTimeoutReresolveUsed) openRetry=\(self.streamOpenReresolveUsed) hlsVariant=\(self.selectedHLSVariantID != nil) \(flags)"
                    )
                    self.isBuffering = false
                    self.isPlaying = false
                    self.lastError = err
                    AppAnalytics.playFail(
                        videoId: videoId ?? "",
                        error: err,
                        retried: self.streamOpenReresolveUsed || self.streamTimeoutReresolveUsed || self.preparePlaybackRetryUsed
                    )
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
                self?.isBuffering = false
                self?.isPlaying = false
                self?.lastError = err
                self?.updateNowPlayingInfo()
                self?.refreshRemoteCommandEnabled()
            }
        }
    }

    func togglePlayPause() {
        // After resolve/play failure (or cold restore with no item), retry loading.
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
            activatePlaybackAudioSession()
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
        resolveTask?.cancel()
        cancelScheduledNextPrepare()
        PlaybackPreparer.shared.clear()
        playingFromPrepare = false
        preparePlaybackRetryUsed = false
        streamTimeoutReresolveUsed = false
        streamOpenReresolveUsed = false
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
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
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
        resolveTask?.cancel()
        cancelScheduledNextPrepare()
        PlaybackPreparer.shared.clear()
        playingFromPrepare = false
        preparePlaybackRetryUsed = false
        streamTimeoutReresolveUsed = false
        streamOpenReresolveUsed = false
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
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
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

    private func configureFullScreenAdObservers() {
        let center = NotificationCenter.default
        if let fullScreenAdPresentObserver {
            center.removeObserver(fullScreenAdPresentObserver)
        }
        if let fullScreenAdDismissObserver {
            center.removeObserver(fullScreenAdDismissObserver)
        }
        fullScreenAdPresentObserver = center.addObserver(
            forName: .ytliteFullScreenAdDidPresent,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.beginFullScreenAdPlaybackHold()
            }
        }
        fullScreenAdDismissObserver = center.addObserver(
            forName: .ytliteFullScreenAdDidDismiss,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.endFullScreenAdPlaybackHold()
                self?.resumeAfterExternalPresentationIfNeeded()
            }
        }
    }

    /// Video full-screen ads grab AVAudioSession; keep music playing underneath muted creatives.
    private func beginFullScreenAdPlaybackHold() {
        endFullScreenAdPlaybackHold()
        activatePlaybackAudioSession(allowMixWithOthers: true)
        guard isPlaying else { return }
        player?.playImmediately(atRate: playbackSpeed)
        fullScreenAdKeepaliveCancellable = Timer.publish(every: 0.35, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard AdSceneLifecycle.preservesPlaybackDuringFullScreenAd else {
                    self.endFullScreenAdPlaybackHold()
                    return
                }
                self.activatePlaybackAudioSession(allowMixWithOthers: true)
                guard self.isPlaying, let player = self.player else { return }
                if player.timeControlStatus != .playing || player.rate == 0 {
                    player.playImmediately(atRate: self.playbackSpeed)
                }
            }
    }

    private func endFullScreenAdPlaybackHold() {
        fullScreenAdKeepaliveCancellable?.cancel()
        fullScreenAdKeepaliveCancellable = nil
        activatePlaybackAudioSession(allowMixWithOthers: false)
    }

    /// Full-screen ads take over AVAudioSession; resume music when the ad closes.
    private func resumeAfterExternalPresentationIfNeeded() {
        activatePlaybackAudioSession(allowMixWithOthers: false)
        guard nowPlaying != nil, let player else { return }
        let shouldResume = resumeAfterInterruption || isPlaying
        resumeAfterInterruption = false
        if shouldResume || player.timeControlStatus != .playing {
            player.playImmediately(atRate: playbackSpeed)
            isPlaying = true
            updateNowPlayingInfo()
        }
    }

    private func handleAudioInterruption(_ note: Notification) {
        guard let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            resumeAfterInterruption = isPlaying
            if AdSceneLifecycle.preservesPlaybackDuringFullScreenAd {
                activatePlaybackAudioSession(allowMixWithOthers: true)
                if isPlaying {
                    player?.playImmediately(atRate: playbackSpeed)
                }
                updateNowPlayingInfo()
                return
            }
            pause()
            updateNowPlayingInfo()
        case .ended:
            let mixing = AdSceneLifecycle.preservesPlaybackDuringFullScreenAd
            activatePlaybackAudioSession(allowMixWithOthers: mixing)
            if mixing {
                if resumeAfterInterruption || isPlaying {
                    player?.playImmediately(atRate: playbackSpeed)
                    isPlaying = true
                }
                resumeAfterInterruption = false
                updateNowPlayingInfo()
                return
            }
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
                    self.checkNextPrepareNearEnd(position: position, duration: duration)
                    self.checkPlaybackStoreThreshold(position: position, duration: duration)
                }
                self.checkSleepTimerExpired()
                self.refreshNextPrepareIfNeeded()
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

    /// Record history / gates only after AVPlayer is actually playing (not resolve-only).
    private func noteSuccessfulPlaybackIfNeeded(videoId: String?) {
        guard let videoId, !videoId.isEmpty else { return }
        guard videoId == nowPlaying?.videoId else { return }
        guard successfulPlaybackRecordedVideoId != videoId else { return }
        successfulPlaybackRecordedVideoId = videoId
        guard let playing = nowPlaying else { return }

        let openMs = probeStreamElapsedMs()
        AppAnalytics.playStart(videoId: videoId, openMs: openMs)

        libraryStore?.recordPlayback(
            playing,
            durationSeconds: pendingResolvedDurationSeconds
        )
        ReviewPromptCoordinator.shared.recordSuccessfulPlay(videoId: videoId)
        refreshFavoriteState()
        persistSession(immediate: true)

        let store = libraryStore
        Task { @MainActor in
            AdEligibility.refreshInventoryIfEligible()
            await DailyListenNotificationScheduler.refresh(using: store)
        }
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
            AppAnalytics.playComplete(videoId: videoId)
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

    /// Keep AVAudioSession + AVPlayer alive when the app backgrounds (App Review checks this).
    func prepareForBackgroundPlayback() {
        guard nowPlaying != nil else { return }
        activatePlaybackAudioSession()
        publishNowPlaying()
        guard isPlaying, let player else { return }
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        if player.timeControlStatus != .playing {
            player.playImmediately(atRate: playbackSpeed)
        }
    }

    private func activatePlaybackAudioSession(allowMixWithOthers: Bool = false) {
        do {
            let session = AVAudioSession.sharedInstance()
            var options: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetoothA2DP]
            if allowMixWithOthers {
                options.insert(.mixWithOthers)
            }
            try session.setCategory(
                .playback,
                mode: .default,
                options: options
            )
            try session.setActive(true, options: [])
        } catch {
            #if DEBUG
            print("[YTLite.Playback] AVAudioSession activate failed: \(error)")
            #endif
        }
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
