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
    private var persistTask: Task<Void, Never>?
    private var sleepTimerCancellable: AnyCancellable?
    /// Pre-shuffle queue snapshot (Android `originalOrder`).
    private var originalOrder: [VideoItem]?
    /// Seek target after cold-start restore + extract.
    private var pendingSeekSeconds: Double = 0
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
        !queue.isEmpty
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
        self.sourcePlaylistId = sourcePlaylistId
        originalOrder = items
        let start = index.clamped(to: 0...(items.count - 1))
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

    func playPrevious() {
        if positionSeconds > 3 {
            seek(to: 0)
            return
        }
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
        return shuffleEnabled
    }

    @discardableResult
    func cycleRepeatMode() -> QueueRepeatMode {
        repeatMode.cycle()
        persistSession(immediate: true)
        refreshRemoteCommandEnabled()
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

    private func playCurrentQueueItem() {
        let item = queue[queueIndex]
        lastError = nil
        needsLoginForPlayback = false
        captionTracks = []
        PlayProbe.log(
            "play.request",
            videoId: item.videoId,
            "title=\(item.title.prefix(48)) index=\(queueIndex)/\(queue.count)"
        )
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
        extractTask?.cancel()
        extractTask = Task {
            do {
                PlayProbe.log("play.extract.begin", videoId: expectedVideoId)
                let playback = try await extractPlaybackWithRetry(videoId: expectedVideoId)
                PlayProbe.log(
                    "play.extract.ok",
                    videoId: playback.videoId,
                    "formats=\(playback.formats.count)"
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
                    "\(playback.preferredStreamDescription()) host=\(host) path=\(url.path.prefix(64))"
                )
                guard generation == extractGeneration, isCurrentExtractTarget(expectedVideoId) else { return }
                lastError = nil
                PlayProbe.log("play.avplayer.start", videoId: expectedVideoId)
                play(url: url)
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
            } catch is CancellationError {
                PlayProbe.log("play.cancelled", videoId: expectedVideoId)
                return
            } catch {
                guard generation == extractGeneration,
                      !Task.isCancelled,
                      isCurrentExtractTarget(expectedVideoId)
                else { return }
                // Stop leftover stream from the previous track so we don't show
                // new metadata + old video frames alongside the error.
                player?.pause()
                isBuffering = false
                isPlaying = false
                lastError = Self.userFacingExtractError(error)
                needsLoginForPlayback = Self.isLoginRequiredExtractError(error)
                PlayProbe.log(
                    "play.fail",
                    videoId: expectedVideoId,
                    "raw=\(error.localizedDescription) ui=\(lastError ?? "-") needsLogin=\(needsLoginForPlayback)"
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

    private func extractPlaybackWithRetry(videoId: String) async throws -> VideoPlayback {
        do {
            return try await ExtractorBridge.shared.extractPlayback(videoId: videoId)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            PlayProbe.log("play.extract.retry", videoId: videoId, error.localizedDescription)
            // One retry helps transient music=null / deposit failures on large player JSON.
            try await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { throw CancellationError() }
            return try await ExtractorBridge.shared.extractPlayback(videoId: videoId)
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
        // googlevideo rejects bare AVPlayerItem(url:) without Referer/UA → "Cannot Open".
        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": YouTubeConstants.streamPlaybackHeaders]
        )
        let avItem = AVPlayerItem(asset: asset)
        observePlayerItem(avItem, videoId: nowPlaying?.videoId)
        if let player {
            player.replaceCurrentItem(with: avItem)
        } else {
            player = AVPlayer(playerItem: avItem)
            attachTimeObserver()
            attachEndObserver()
        }
        lastError = nil
        needsLoginForPlayback = false
        isBuffering = false
        applySpeed()
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    private func observePlayerItem(_ item: AVPlayerItem, videoId: String?) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .unknown:
                    PlayProbe.log("avplayer.status", videoId: videoId, "unknown")
                case .readyToPlay:
                    PlayProbe.log(
                        "avplayer.status",
                        videoId: videoId,
                        "readyToPlay duration=\(item.duration.seconds)"
                    )
                case .failed:
                    let ns = item.error as NSError?
                    let underlying = (ns?.userInfo[NSUnderlyingErrorKey] as? NSError)
                        .map { "underlying=\($0.domain)/\($0.code) \($0.localizedDescription)" } ?? ""
                    let err = item.error?.localizedDescription ?? "unknown"
                    PlayProbe.log(
                        "avplayer.status",
                        videoId: videoId,
                        "failed err=\(err) domain=\(ns?.domain ?? "") code=\(ns?.code ?? -1) \(underlying)"
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
            let err = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "failedToPlayToEnd"
            Task { @MainActor in
                PlayProbe.log("avplayer.failToEnd", videoId: videoId, err)
                self?.isPlaying = false
                self?.lastError = err
                self?.updateNowPlayingInfo()
                self?.refreshRemoteCommandEnabled()
            }
        }
    }

    func togglePlayPause() {
        // Cold-start restore: metadata shown, stream not loaded yet.
        if player == nil {
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
        let clamped = max(0, seconds)
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: time)
        positionSeconds = clamped
        updateNowPlayingInfo()
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
                let position = time.seconds.isFinite ? time.seconds : 0
                let duration: Double? = {
                    guard let d = player.currentItem?.duration.seconds, d.isFinite else { return nil }
                    return d
                }()
                self.progress.setPositionAndDuration(position: position, duration: duration)
                self.checkSleepTimerExpired()
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
