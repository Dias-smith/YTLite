import Combine
import Foundation
import WidgetKit

/// Watch-side playback remote: transport + queue mirror (Phase 4).
@MainActor
final class WatchPlaybackClient: ObservableObject {
    static let shared = WatchPlaybackClient()

    @Published private(set) var snapshot: WatchConnectivityProtocol.PlaybackSnapshot?
    @Published private(set) var queue: WatchConnectivityProtocol.QueueSnapshot?
    @Published private(set) var lastCommandError: String?

    private var didBind = false
    private var cancellables = Set<AnyCancellable>()
    private var lastPlaybackUpdatedAt: TimeInterval = 0
    private var lastQueueUpdatedAt: TimeInterval = 0
    private var reconcileTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var playSyncTimer: AnyCancellable?
    private var lastRequestedSyncAt: Date = .distantPast
    /// Local volume chrome hold — do not advance `lastPlaybackUpdatedAt` or phone metadata is blocked.
    private var volumeHoldUntil: Date?

    private init() {}

    func start() {
        if queue == nil, let cached = WatchQueueMirrorStore.load() {
            queue = cached
        }
        let bridge = WatchConnectivityBridge.shared
        bridge.activate()
        bindIfNeeded()
        WatchWidgetCommandBridge.shared.start(client: self)
        syncWithPhone(bootstrap: true)
        publishWidgetSnapshot()
    }

    /// ***
    /// - Parameter bootstrap: retry several times after launch / foreground.
    func syncWithPhone(bootstrap: Bool = false) {
        ingestCachedApplicationContext()
        requestSnapshot(force: true)
        configurePlaySyncTimer(playing: snapshot?.isPlaying == true)
        if bootstrap {
            scheduleBootstrapSync()
        }
    }

    /// Pull latest phone Now Playing from WC applicationContext (works without isReachable).
    func refreshFromApplicationContext() {
        ingestCachedApplicationContext()
    }

    private func bindIfNeeded() {
        guard !didBind else { return }
        didBind = true
        let bridge = WatchConnectivityBridge.shared
        bridge.onEnvelope { [weak self] envelope in
            self?.handle(envelope)
        }
        ingestCachedApplicationContext()
        bridge.$activationState
            .removeDuplicates()
            .sink { [weak self] state in
                guard state == .activated else { return }
                self?.syncWithPhone(bootstrap: true)
            }
            .store(in: &cancellables)
        bridge.$isReachable
            .removeDuplicates()
            .sink { [weak self] reachable in
                if reachable {
                    self?.syncWithPhone(bootstrap: true)
                } else {
                    self?.ingestCachedApplicationContext()
                }
            }
            .store(in: &cancellables)

        // ***
        Timer.publish(every: 2.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.ingestCachedApplicationContext()
                // Keep asking phone while the face is up — even if reachability flickers.
                if WatchConnectivityBridge.shared.isReachable {
                    self.requestSnapshot(force: false)
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleBootstrapSync() {
        bootstrapTask?.cancel()
        bootstrapTask = Task { @MainActor in
            for delayNs in [200_000_000, 600_000_000, 1_500_000_000, 3_000_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                ingestCachedApplicationContext()
                requestSnapshot(force: true)
            }
        }
    }

    /// While phone is playing, actively re-pull so position / track stay aligned.
    private func configurePlaySyncTimer(playing: Bool) {
        playSyncTimer?.cancel()
        playSyncTimer = nil
        guard playing else { return }
        playSyncTimer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.ingestCachedApplicationContext()
                self.requestSnapshot(force: false)
            }
    }

    private func ingestCachedApplicationContext() {
        let bridge = WatchConnectivityBridge.shared
        guard let cached = bridge.receivedApplicationContextEnvelope(),
              cached.kind == .playbackSnapshot,
              let body = try? cached.decodePayload(WatchConnectivityProtocol.PlaybackSnapshot.self) else {
            return
        }
        applyPlaybackSnapshot(body, source: .context)
    }

    func requestSnapshot() {
        requestSnapshot(force: true)
    }

    private func requestSnapshot(force: Bool) {
        let bridge = WatchConnectivityBridge.shared
        guard bridge.activationState == .activated else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastRequestedSyncAt) < 0.9 {
            return
        }
        lastRequestedSyncAt = now
        do {
            let envelope = try WatchConnectivityProtocol.Envelope.make(
                kind: .syncRequestSnapshot,
                body: WatchConnectivityProtocol.EmptyBody()
            )
            _ = bridge.send(envelope)
        } catch {
            // Best-effort.
        }
    }

    func togglePlayPause() {
        applyOptimisticPlayPause()
        send(kind: .transportPlayPause, body: WatchConnectivityProtocol.EmptyBody())
        scheduleReconcile()
    }

    func playNext() {
        applyOptimisticSkip(forward: true)
        send(kind: .transportNext, body: WatchConnectivityProtocol.EmptyBody())
        scheduleReconcile()
    }

    func playPrevious() {
        applyOptimisticSkip(forward: false)
        send(kind: .transportPrevious, body: WatchConnectivityProtocol.EmptyBody())
        scheduleReconcile()
    }

    func seek(to position: Double) {
        send(kind: .transportSeek, body: WatchConnectivityProtocol.SeekBody(position: position))
        scheduleReconcile()
    }

    func seekRelative(by delta: Double) {
        let base = snapshot?.position ?? 0
        let duration = snapshot?.duration
        var target = base + delta
        if let duration, duration > 0 {
            target = min(max(0, target), duration)
        } else {
            target = max(0, target)
        }
        seek(to: target)
    }

    func setShuffle(_ enabled: Bool) {
        if var current = snapshot {
            current.shuffleEnabled = enabled
            snapshot = current
        }
        send(kind: .transportSetShuffle, body: WatchConnectivityProtocol.BoolBody(value: enabled))
        scheduleReconcile()
    }

    func toggleShuffle() {
        setShuffle(!(snapshot?.shuffleEnabled ?? false))
    }

    func cycleRepeat() {
        if var current = snapshot {
            current.repeatMode = nextRepeatMode(current.repeatMode)
            snapshot = current
        }
        send(kind: .transportCycleRepeat, body: WatchConnectivityProtocol.EmptyBody())
        scheduleReconcile()
    }

    func setSpeed(_ speed: Float) {
        if var current = snapshot {
            current.speed = speed
            snapshot = current
        }
        send(kind: .transportSetSpeed, body: WatchConnectivityProtocol.SpeedBody(speed: speed))
        scheduleReconcile()
    }

    func setVolume(_ volume: Float) {
        let clamped = min(max(volume, 0), 1)
        // Optimistic local mirror — hold volume briefly without blocking phone metadata.
        if var current = snapshot {
            current.outputVolume = clamped
            snapshot = current
        }
        volumeHoldUntil = Date().addingTimeInterval(1.6)
        send(kind: .transportSetVolume, body: WatchConnectivityProtocol.VolumeBody(volume: clamped))
        scheduleReconcile()
    }

    func setSleepTimer(minutes: Int?) {
        let normalized: Int? = {
            guard let minutes, minutes > 0 else { return nil }
            return minutes
        }()
        if var current = snapshot {
            current.sleepTimerMinutes = normalized
            current.sleepTimerEndsAt = normalized.map { Date().addingTimeInterval(TimeInterval($0 * 60)).timeIntervalSince1970 }
            snapshot = current
            publishWidgetSnapshot()
        }
        send(
            kind: .transportSetSleepTimer,
            body: WatchConnectivityProtocol.SleepTimerBody(minutes: normalized)
        )
        scheduleReconcile()
    }

    func playQueueIndex(_ index: Int) {
        applyOptimisticQueueIndex(index)
        send(kind: .queuePlayIndex, body: WatchConnectivityProtocol.IndexBody(index: index))
        scheduleReconcile()
    }

    func removeFromQueue(videoIds: [String]) {
        send(kind: .queueRemove, body: WatchConnectivityProtocol.IdsBody(ids: videoIds))
        scheduleReconcile()
    }

    func playNextInQueue(videoId: String) {
        send(kind: .queuePlayNext, body: WatchConnectivityProtocol.VideoIdBody(videoId: videoId))
        scheduleReconcile()
    }

    func appendOrMoveToEnd(videoId: String) {
        send(kind: .queueAppend, body: WatchConnectivityProtocol.VideoIdBody(videoId: videoId))
        scheduleReconcile()
    }

    private func send<T: Encodable>(kind: WatchConnectivityProtocol.Kind, body: T) {
        let bridge = WatchConnectivityBridge.shared
        guard bridge.activationState == .activated else {
            lastCommandError = WL("watch.phone_required", "Open Mixtube on iPhone")
            return
        }
        guard bridge.isReachable else {
            lastCommandError = WL("watch.phone_required", "Open Mixtube on iPhone")
            return
        }
        lastCommandError = nil
        do {
            let envelope = try WatchConnectivityProtocol.Envelope.make(kind: kind, body: body)
            _ = bridge.send(envelope) { [weak self] result in
                if case .failure(let error) = result {
                    self?.lastCommandError = error.localizedDescription
                }
            }
        } catch {
            lastCommandError = error.localizedDescription
        }
    }

    /// Phone often applies the command while backgrounded, but the return snapshot can lag
    /// or drop when `sendMessage` fails — refresh local chrome immediately.
    private func applyOptimisticPlayPause() {
        guard var current = snapshot, current.videoId != nil else { return }
        current.isPlaying.toggle()
        // Do not advance lastPlaybackUpdatedAt — phone stamps must remain authoritative.
        snapshot = current
        publishWidgetSnapshot()
        configurePlaySyncTimer(playing: current.isPlaying)
    }

    private func applyOptimisticSkip(forward: Bool) {
        guard var queueSnapshot = queue, !queueSnapshot.items.isEmpty else { return }
        let count = queueSnapshot.items.count
        let current = queueSnapshot.currentIndex
        let nextIndex: Int
        if forward {
            if current + 1 < count {
                nextIndex = current + 1
            } else if snapshot?.repeatMode == "ALL" {
                nextIndex = 0
            } else {
                return
            }
        } else {
            if current > 0 {
                nextIndex = current - 1
            } else if snapshot?.repeatMode == "ALL" {
                nextIndex = count - 1
            } else {
                return
            }
        }
        applyOptimisticQueueIndex(nextIndex)
    }

    private func applyOptimisticQueueIndex(_ index: Int) {
        guard var queueSnapshot = queue,
              queueSnapshot.items.indices.contains(index)
        else { return }
        let item = queueSnapshot.items[index]
        queueSnapshot.currentIndex = index
        queue = queueSnapshot

        var playback = snapshot ?? WatchConnectivityProtocol.PlaybackSnapshot(
            videoId: nil,
            title: nil,
            artist: nil,
            thumbnailURL: nil,
            position: 0,
            duration: nil,
            isPlaying: true,
            shuffleEnabled: false,
            repeatMode: "OFF",
            speed: 1,
            isExtracting: true,
            isSeekable: false,
            errorMessage: nil,
            outputVolume: nil,
            sleepTimerMinutes: nil,
            sleepTimerEndsAt: nil,
            updatedAt: snapshot?.updatedAt
        )
        playback.videoId = item.videoId
        playback.title = item.title
        playback.artist = item.artist
        playback.thumbnailURL = item.thumbnailURL
        playback.position = 0
        playback.duration = nil
        playback.isPlaying = true
        playback.isExtracting = true
        playback.isSeekable = false
        playback.errorMessage = nil
        // Keep prior watermark so the phone's next snapshot is never rejected.
        snapshot = playback
        publishWidgetSnapshot()
        configurePlaySyncTimer(playing: true)
    }

    private func nextRepeatMode(_ raw: String) -> String {
        switch raw {
        case "OFF": return "ALL"
        case "ALL": return "ONE"
        default: return "OFF"
        }
    }

    /// Pull authoritative phone state after local chrome updates (covers dropped pushes).
    private func scheduleReconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor in
            for delayNs in [150_000_000, 400_000_000, 1_000_000_000, 2_200_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                ingestCachedApplicationContext()
                requestSnapshot(force: true)
            }
        }
    }

    private enum SnapshotSource {
        case context
        case envelope
    }

    private func applyPlaybackSnapshot(
        _ body: WatchConnectivityProtocol.PlaybackSnapshot,
        source: SnapshotSource
    ) {
        let incoming = body.updatedAt ?? 0
        let previousVideoId = snapshot?.videoId
        let previousPlaying = snapshot?.isPlaying
        let trackChanged = body.videoId != nil && body.videoId != previousVideoId
        let metadataChanged = body.videoId != nil
            && body.videoId == previousVideoId
            && (
                nonempty(body.title) != nonempty(snapshot?.title)
                || nonempty(body.artist) != nonempty(snapshot?.artist)
                || body.thumbnailURL != snapshot?.thumbnailURL
            )

        // Progress / transport ticks still require a fresh stamp; track + title/art always win.
        if !trackChanged, !metadataChanged {
            guard incoming >= lastPlaybackUpdatedAt else { return }
        }

        lastPlaybackUpdatedAt = max(incoming, lastPlaybackUpdatedAt)

        var next = body
        if let hold = volumeHoldUntil, Date() < hold, !trackChanged {
            next.outputVolume = snapshot?.outputVolume ?? body.outputVolume
        } else if let hold = volumeHoldUntil, Date() >= hold {
            volumeHoldUntil = nil
        }

        snapshot = next
        lastCommandError = nil
        publishWidgetSnapshot()

        if next.isPlaying != previousPlaying {
            configurePlaySyncTimer(playing: next.isPlaying)
        }

        // Phone-side track change: actively re-pull so queue index / metadata stay aligned.
        if source == .envelope, trackChanged {
            requestSnapshot(force: true)
        }
    }

    private func nonempty(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func publishWidgetSnapshot() {
        WatchWidgetSnapshotBridge.publish(from: snapshot)
    }

    private func handle(_ envelope: WatchConnectivityProtocol.Envelope) {
        switch envelope.kind {
        case .playbackSnapshot:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.PlaybackSnapshot.self) {
                applyPlaybackSnapshot(body, source: .envelope)
            }
        case .queueSnapshot:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.QueueSnapshot.self) {
                guard (body.updatedAt ?? 0) >= lastQueueUpdatedAt else { return }
                lastQueueUpdatedAt = body.updatedAt ?? lastQueueUpdatedAt
                queue = body
                WatchQueueMirrorStore.save(body)
                lastCommandError = nil
            }
        case .hostUnavailable:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.HostUnavailable.self) {
                lastCommandError = body.reason
            } else {
                lastCommandError = WL("watch.phone_required", "Open Mixtube on iPhone")
            }
        case .error:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.ErrorBody.self) {
                lastCommandError = body.message
            }
        default:
            break
        }
    }
}
