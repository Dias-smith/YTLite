import AVFoundation
import Combine
import Foundation

/// iPhone-side Watch companion host: playback + queue snapshots and remote commands.
@MainActor
final class WatchPlaybackHost {
    static let shared = WatchPlaybackHost()

    private static let maxQueueItems = 80

    private weak var playback: PlaybackController?
    private var bridgeCancellables = Set<AnyCancellable>()
    private var playbackCancellables = Set<AnyCancellable>()
    private var positionTimer: AnyCancellable?
    private var didBindBridge = false
    private var lastPushedPlayback: WatchConnectivityProtocol.PlaybackSnapshot?
    private var lastPushedQueue: WatchConnectivityProtocol.QueueSnapshot?
    private var volumeObservation: NSKeyValueObservation?

    private init() {}

    func start(playback: PlaybackController) {
        self.playback = playback
        bindBridgeIfNeeded()
        observePlayback(playback)
        observeOutputVolume()
        pushAll(force: true)
    }

    private func bindBridgeIfNeeded() {
        guard !didBindBridge else { return }
        didBindBridge = true
        let bridge = WatchConnectivityBridge.shared
        bridge.onEnvelope { [weak self] envelope in
            self?.handle(envelope)
        }
        bridge.$activationState
            .removeDuplicates()
            .sink { [weak self] state in
                if state == .activated {
                    self?.pushAll(force: true)
                }
            }
            .store(in: &bridgeCancellables)
        bridge.$isWatchAppInstalled
            .removeDuplicates()
            .sink { [weak self] installed in
                guard let self else { return }
                if installed {
                    self.pushAll(force: true)
                    self.configurePositionTimer(playing: self.playback?.isPlaying == true)
                } else if !WatchConnectivityBridge.shared.isWatchDeliveryAvailable {
                    self.positionTimer?.cancel()
                    self.positionTimer = nil
                }
            }
            .store(in: &bridgeCancellables)
        bridge.$isReachable
            .removeDuplicates()
            .sink { [weak self] reachable in
                if reachable {
                    self?.pushAll(force: true)
                    self?.configurePositionTimer(playing: self?.playback?.isPlaying == true)
                }
            }
            .store(in: &bridgeCancellables)
    }

    private func observePlayback(_ playback: PlaybackController) {
        playbackCancellables.removeAll()
        positionTimer?.cancel()
        positionTimer = nil

        Publishers.MergeMany(
            playback.$nowPlaying.map { _ in () }.eraseToAnyPublisher(),
            playback.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            playback.$isBuffering.map { _ in () }.eraseToAnyPublisher(),
            playback.$lastError.map { _ in () }.eraseToAnyPublisher(),
            playback.$shuffleEnabled.map { _ in () }.eraseToAnyPublisher(),
            playback.$repeatMode.map { _ in () }.eraseToAnyPublisher(),
            playback.$playbackSpeed.map { _ in () }.eraseToAnyPublisher(),
            playback.$queueIndex.map { _ in () }.eraseToAnyPublisher(),
            playback.$queue.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.pushAll()
        }
        .store(in: &playbackCancellables)

        playback.$isPlaying
            .removeDuplicates()
            .sink { [weak self] playing in
                self?.configurePositionTimer(playing: playing)
            }
            .store(in: &playbackCancellables)
    }

    private func observeOutputVolume() {
        volumeObservation?.invalidate()
        let session = AVAudioSession.sharedInstance()
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.pushPlayback(force: true)
            }
        }
    }

    private func configurePositionTimer(playing: Bool) {
        positionTimer?.cancel()
        positionTimer = nil
        guard playing, WatchConnectivityBridge.shared.isWatchDeliveryAvailable else { return }
        positionTimer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pushPlayback(force: true)
            }
    }

    private func handle(_ envelope: WatchConnectivityProtocol.Envelope) {
        switch envelope.kind {
        case .syncRequestSnapshot:
            pushAll(force: true)
        case .transportPlayPause:
            playback?.togglePlayPause()
            pushAll(force: true)
        case .transportNext:
            playback?.playNext()
            pushAll(force: true)
        case .transportPrevious:
            playback?.playPrevious()
            pushAll(force: true)
        case .transportSeek:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.SeekBody.self) {
                playback?.seek(to: body.position)
                pushPlayback(force: true)
            }
        case .transportSetShuffle:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.BoolBody.self),
               let playback,
               playback.shuffleEnabled != body.value {
                playback.toggleShuffle()
            }
            pushAll(force: true)
        case .transportCycleRepeat:
            playback?.cycleRepeatMode()
            pushAll(force: true)
        case .transportSetSpeed:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.SpeedBody.self),
               let playback {
                let options = WatchConnectivityProtocol.PlaybackSnapshot.speedOptions
                let nearest = options.min(by: { abs($0 - body.speed) < abs($1 - body.speed) }) ?? body.speed
                playback.playbackSpeed = nearest
            }
            pushPlayback(force: true)
        case .queuePlayIndex:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.IndexBody.self) {
                playback?.playQueueIndex(body.index)
                pushAll(force: true)
            }
        case .queueRemove:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.IdsBody.self) {
                playback?.removeFromQueue(videoIds: Set(body.ids))
                pushAll(force: true)
            }
        case .queuePlayNext:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.VideoIdBody.self),
               let item = queueItem(videoId: body.videoId) {
                playback?.insertNext(item)
                pushAll(force: true)
            }
        case .queueAppend:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.VideoIdBody.self) {
                if let playback, playback.queue.contains(where: { $0.videoId == body.videoId }) {
                    playback.moveToEndOfQueue(videoId: body.videoId)
                } else if let item = queueItem(videoId: body.videoId) {
                    playback?.appendToQueue(item)
                }
                pushAll(force: true)
            }
        default:
            break
        }
    }

    private func queueItem(videoId: String) -> VideoItem? {
        playback?.queue.first(where: { $0.videoId == videoId })
    }

    private func pushAll(force: Bool = false) {
        guard WatchConnectivityBridge.shared.isWatchDeliveryAvailable else { return }
        pushPlayback(force: force)
        pushQueue(force: force)
    }

    private func pushPlayback(force: Bool = false) {
        guard WatchConnectivityBridge.shared.isWatchDeliveryAvailable else { return }
        guard let playback else { return }
        let snapshot = makePlaybackSnapshot(from: playback)
        if !force, snapshot == lastPushedPlayback { return }
        send(kind: .playbackSnapshot, body: snapshot, updateContext: true)
        lastPushedPlayback = snapshot
    }

    private func pushQueue(force: Bool = false) {
        guard WatchConnectivityBridge.shared.isWatchDeliveryAvailable else { return }
        guard let playback else { return }
        let snapshot = makeQueueSnapshot(from: playback)
        if !force, snapshot == lastPushedQueue { return }
        send(kind: .queueSnapshot, body: snapshot, updateContext: false)
        lastPushedQueue = snapshot
    }

    private func send<T: Encodable>(
        kind: WatchConnectivityProtocol.Kind,
        body: T,
        updateContext: Bool
    ) {
        do {
            let envelope = try WatchConnectivityProtocol.Envelope.make(kind: kind, body: body)
            let bridge = WatchConnectivityBridge.shared
            if updateContext {
                _ = bridge.updateApplicationContext(envelope)
            }
            if bridge.isReachable {
                _ = bridge.send(envelope)
            } else {
                bridge.transferUserInfo(envelope)
            }
        } catch {
            // Best-effort.
        }
    }

    private func makePlaybackSnapshot(from playback: PlaybackController) -> WatchConnectivityProtocol.PlaybackSnapshot {
        let item = playback.nowPlaying
        let duration = playback.durationSeconds
        let isLive: Bool = {
            let idx = playback.queueIndex
            guard playback.queue.indices.contains(idx) else { return false }
            return playback.queue[idx].isLive
        }()
        let hasDuration = duration.isFinite && duration > 0
        return WatchConnectivityProtocol.PlaybackSnapshot(
            videoId: item?.videoId,
            title: item?.title,
            artist: item?.channelName,
            thumbnailURL: item?.thumbnailURL?.absoluteString,
            position: playback.positionSeconds,
            duration: hasDuration ? duration : nil,
            isPlaying: playback.isPlaying,
            shuffleEnabled: playback.shuffleEnabled,
            repeatMode: playback.repeatMode.rawValue,
            speed: playback.playbackSpeed,
            isExtracting: playback.isBuffering,
            isSeekable: hasDuration && !isLive,
            errorMessage: playback.lastError,
            outputVolume: AVAudioSession.sharedInstance().outputVolume
        )
    }

    private func makeQueueSnapshot(from playback: PlaybackController) -> WatchConnectivityProtocol.QueueSnapshot {
        let capped = Array(playback.queue.prefix(Self.maxQueueItems))
        let items = capped.map { item in
            WatchConnectivityProtocol.QueueTrackDTO(
                videoId: item.videoId,
                title: item.title,
                artist: item.channelName,
                thumbnailURL: item.thumbnailURL?.absoluteString,
                durationText: item.durationText,
                isLive: item.isLive
            )
        }
        let currentIndex: Int = {
            if playback.queueIndex < items.count { return playback.queueIndex }
            return max(0, items.count - 1)
        }()
        return WatchConnectivityProtocol.QueueSnapshot(currentIndex: currentIndex, items: items)
    }
}
