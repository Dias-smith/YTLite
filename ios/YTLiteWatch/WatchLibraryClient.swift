import Combine
import Foundation

/// Watch-side library mirror + CRUD commands (Phase 6).
@MainActor
final class WatchLibraryClient: ObservableObject {
    static let shared = WatchLibraryClient()

    @Published private(set) var snapshot: WatchConnectivityProtocol.LibrarySnapshot?
    @Published private(set) var lastCommandError: String?
    @Published private(set) var lastShareMessage: String?

    private var didBind = false
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        if snapshot == nil, let cached = WatchLibraryMirrorStore.load() {
            snapshot = cached
        }
        let bridge = WatchConnectivityBridge.shared
        bridge.activate()
        bindIfNeeded()
        if bridge.isReachable {
            requestSnapshot()
        }
    }

    private func bindIfNeeded() {
        guard !didBind else { return }
        didBind = true
        let bridge = WatchConnectivityBridge.shared
        bridge.onEnvelope { [weak self] envelope in
            self?.handle(envelope)
        }
        bridge.$activationState
            .removeDuplicates()
            .sink { [weak self] state in
                if state == .activated {
                    self?.requestSnapshot()
                }
            }
            .store(in: &cancellables)
        bridge.$isReachable
            .removeDuplicates()
            .sink { [weak self] reachable in
                if reachable {
                    self?.requestSnapshot()
                    self?.lastCommandError = nil
                }
            }
            .store(in: &cancellables)
    }

    func requestSnapshot() {
        let bridge = WatchConnectivityBridge.shared
        guard bridge.activationState == .activated, bridge.isReachable else { return }
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

    func requireConnected() -> Bool {
        let bridge = WatchConnectivityBridge.shared
        guard bridge.isReachable else {
            lastCommandError = WL("watch.phone_disconnected_readonly", "Phone disconnected · Read only")
            return false
        }
        return true
    }

    /// Mutations are Phase 6; surface reconnect messaging when disconnected.
    func requireConnectedForMutation() -> Bool { requireConnected() }

    func playPlaylist(playlistId: String, index: Int) {
        send(
            kind: .libraryPlayPlaylist,
            body: WatchConnectivityProtocol.PlayPlaylistBody(playlistId: playlistId, index: index)
        )
    }

    func playHistory(index: Int) {
        send(kind: .libraryPlayHistory, body: WatchConnectivityProtocol.IndexBody(index: index))
    }

    func shufflePlay(playlistId: String) {
        send(kind: .libraryShufflePlay, body: WatchConnectivityProtocol.PlaylistIdBody(playlistId: playlistId))
    }

    func like(videoId: String) {
        send(kind: .libraryLike, body: WatchConnectivityProtocol.VideoIdBody(videoId: videoId))
    }

    func unlike(videoId: String) {
        send(kind: .libraryUnlike, body: WatchConnectivityProtocol.VideoIdBody(videoId: videoId))
    }

    func notInterested(videoId: String) {
        send(kind: .libraryNotInterested, body: WatchConnectivityProtocol.VideoIdBody(videoId: videoId))
    }

    func removeFromHistory(videoIds: [String]) {
        send(kind: .libraryRemoveFromHistory, body: WatchConnectivityProtocol.IdsBody(ids: videoIds))
    }

    func addToPlaylist(videoId: String, playlistId: String) {
        send(
            kind: .libraryAddToPlaylist,
            body: WatchConnectivityProtocol.AddToPlaylistBody(videoId: videoId, playlistId: playlistId)
        )
    }

    func removeFromPlaylist(videoId: String, playlistId: String) {
        send(
            kind: .libraryRemoveFromPlaylist,
            body: WatchConnectivityProtocol.RemoveFromPlaylistBody(videoId: videoId, playlistId: playlistId)
        )
    }

    func createPlaylist(name: String) {
        send(kind: .libraryCreatePlaylist, body: WatchConnectivityProtocol.CreatePlaylistBody(name: name))
    }

    func renamePlaylist(playlistId: String, name: String) {
        send(
            kind: .libraryRenamePlaylist,
            body: WatchConnectivityProtocol.RenamePlaylistBody(playlistId: playlistId, name: name)
        )
    }

    func deletePlaylist(playlistId: String) {
        send(kind: .libraryDeletePlaylist, body: WatchConnectivityProtocol.PlaylistIdBody(playlistId: playlistId))
    }

    func setPinned(playlistId: String, pinned: Bool) {
        send(
            kind: .librarySetPinned,
            body: WatchConnectivityProtocol.SetPinnedBody(playlistId: playlistId, pinned: pinned)
        )
    }

    func editMetadata(_ body: WatchConnectivityProtocol.EditMetadataBody) {
        send(kind: .libraryEditTrackMetadata, body: body)
    }

    func playNext(videoId: String) {
        send(kind: .libraryQueuePlayNext, body: WatchConnectivityProtocol.VideoIdBody(videoId: videoId))
    }

    func addToQueue(videoId: String) {
        send(kind: .libraryQueueAppend, body: WatchConnectivityProtocol.VideoIdBody(videoId: videoId))
    }

    func share(videoId: String) {
        lastShareMessage = nil
        send(kind: .sharePresent, body: WatchConnectivityProtocol.VideoIdBody(videoId: videoId))
    }

    func isFavorite(videoId: String) -> Bool {
        snapshot?.favoriteVideoIds.contains(videoId) ?? false
    }

    private func send<T: Encodable>(kind: WatchConnectivityProtocol.Kind, body: T) {
        let bridge = WatchConnectivityBridge.shared
        guard bridge.activationState == .activated else {
            lastCommandError = WL("watch.phone_required", "Open Mixtube on iPhone")
            return
        }
        guard bridge.isReachable else {
            lastCommandError = WL("watch.phone_disconnected_readonly", "Phone disconnected · Read only")
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
        case .librarySnapshot:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.LibrarySnapshot.self) {
                snapshot = body
                WatchLibraryMirrorStore.save(body)
                lastCommandError = nil
            }
        case .shareResult:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.ShareResultBody.self) {
                lastShareMessage = body.ok
                    ? WL("watch.share_opened", "Share opened on iPhone")
                    : (body.message ?? WL("watch.share_failed", "Share failed"))
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
