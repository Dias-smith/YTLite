import Combine
import Foundation

/// Watch-side playback remote: transport + queue mirror (Phase 4).
@MainActor
final class WatchPlaybackClient: ObservableObject {
    static let shared = WatchPlaybackClient()

    @Published private(set) var snapshot: WatchConnectivityProtocol.PlaybackSnapshot?
    @Published private(set) var queue: WatchConnectivityProtocol.QueueSnapshot?
    @Published private(set) var lastCommandError: String?

    private var didBind = false
    private var cancellables = Set<AnyCancellable>()
    private var snapshotRetry: AnyCancellable?
    private var didQueueBackgroundHandshake = false

    private init() {}

    func start() {
        if queue == nil, let cached = WatchQueueMirrorStore.load() {
            queue = cached
        }
        let bridge = WatchConnectivityBridge.shared
        bridge.activate()
        bindIfNeeded()
        if bridge.isReachable {
            requestSnapshot()
        }
        startSnapshotRetryLoop()
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
                self?.ingestCachedApplicationContext()
                self?.requestSnapshot()
            }
            .store(in: &cancellables)
        bridge.$isReachable
            .removeDuplicates()
            .sink { [weak self] reachable in
                if reachable {
                    self?.requestSnapshot()
                }
            }
            .store(in: &cancellables)
    }

    private func startSnapshotRetryLoop() {
        snapshotRetry?.cancel()
        snapshotRetry = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                // Keep polling until we have a real now-playing id (device WC can be one-way stale).
                if self.snapshot?.videoId == nil {
                    self.ingestCachedApplicationContext()
                    self.requestSnapshot()
                }
            }
    }

    private func ingestCachedApplicationContext() {
        let bridge = WatchConnectivityBridge.shared
        guard let cached = bridge.receivedApplicationContextEnvelope(),
              cached.kind == .playbackSnapshot,
              let body = try? cached.decodePayload(WatchConnectivityProtocol.PlaybackSnapshot.self) else {
            return
        }
        snapshot = body
    }

    func requestSnapshot() {
        let bridge = WatchConnectivityBridge.shared
        guard bridge.activationState == .activated else { return }
        do {
            let envelope = try WatchConnectivityProtocol.Envelope.make(
                kind: .syncRequestSnapshot,
                body: WatchConnectivityProtocol.EmptyBody()
            )
            // Prefer background channels: sendMessage often times out while isReachable stays stale.
            _ = bridge.updateApplicationContext(envelope)
            bridge.transferUserInfo(envelope)
            _ = bridge.send(envelope)
            didQueueBackgroundHandshake = true
        } catch {
            // Best-effort.
        }
    }

    func togglePlayPause() {
        send(kind: .transportPlayPause, body: WatchConnectivityProtocol.EmptyBody())
    }

    func playNext() {
        send(kind: .transportNext, body: WatchConnectivityProtocol.EmptyBody())
    }

    func playPrevious() {
        send(kind: .transportPrevious, body: WatchConnectivityProtocol.EmptyBody())
    }

    func seek(to position: Double) {
        send(kind: .transportSeek, body: WatchConnectivityProtocol.SeekBody(position: position))
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
        send(kind: .transportSetShuffle, body: WatchConnectivityProtocol.BoolBody(value: enabled))
    }

    func toggleShuffle() {
        setShuffle(!(snapshot?.shuffleEnabled ?? false))
    }

    func cycleRepeat() {
        send(kind: .transportCycleRepeat, body: WatchConnectivityProtocol.EmptyBody())
    }

    func setSpeed(_ speed: Float) {
        send(kind: .transportSetSpeed, body: WatchConnectivityProtocol.SpeedBody(speed: speed))
    }

    func playQueueIndex(_ index: Int) {
        send(kind: .queuePlayIndex, body: WatchConnectivityProtocol.IndexBody(index: index))
    }

    func removeFromQueue(videoIds: [String]) {
        send(kind: .queueRemove, body: WatchConnectivityProtocol.IdsBody(ids: videoIds))
    }

    func playNextInQueue(videoId: String) {
        send(kind: .queuePlayNext, body: WatchConnectivityProtocol.VideoIdBody(videoId: videoId))
    }

    func appendOrMoveToEnd(videoId: String) {
        send(kind: .queueAppend, body: WatchConnectivityProtocol.VideoIdBody(videoId: videoId))
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

    private func handle(_ envelope: WatchConnectivityProtocol.Envelope) {
        switch envelope.kind {
        case .playbackSnapshot:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.PlaybackSnapshot.self) {
                snapshot = body
                lastCommandError = nil
            }
        case .queueSnapshot:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.QueueSnapshot.self) {
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