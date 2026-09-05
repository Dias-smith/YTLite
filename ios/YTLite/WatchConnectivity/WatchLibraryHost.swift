import Combine
import Foundation
import UIKit

/// iPhone-side library mirror + CRUD / share for Watch (Phase 6).
@MainActor
final class WatchLibraryHost {
    static let shared = WatchLibraryHost()

    private static let maxPlaylists = 30
    private static let maxTracksPerPlaylist = 40
    private static let maxHistory = 40

    private weak var store: LibraryStore?
    private weak var playback: PlaybackController?
    private weak var auth: AuthService?
    private var bridgeCancellables = Set<AnyCancellable>()
    private var didBindBridge = false
    private var lastPushed: WatchConnectivityProtocol.LibrarySnapshot?

    private init() {}

    func start(store: LibraryStore, playback: PlaybackController, auth: AuthService) {
        self.store = store
        self.playback = playback
        self.auth = auth

        let previous = store.onMutate
        store.onMutate = { [weak self] in
            previous?()
            self?.pushSnapshot(force: true)
        }

        bindBridgeIfNeeded()
        pushSnapshot(force: true)
    }

    func refresh() {
        pushSnapshot(force: true)
    }

    private func bindBridgeIfNeeded() {
        guard !didBindBridge else { return }
        didBindBridge = true
        let bridge = WatchConnectivityBridge.shared
        bridge.onEnvelope { [weak self] envelope in
            self?.handle(envelope)
        }
        bridge.$isReachable
            .removeDuplicates()
            .sink { [weak self] reachable in
                if reachable {
                    self?.pushSnapshot(force: true)
                }
            }
            .store(in: &bridgeCancellables)
    }

    private func handle(_ envelope: WatchConnectivityProtocol.Envelope) {
        switch envelope.kind {
        case .syncRequestSnapshot:
            pushSnapshot(force: true)

        case .libraryPlayPlaylist:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.PlayPlaylistBody.self) {
                playPlaylist(id: body.playlistId, startAt: body.index, shuffle: false)
            }
        case .libraryPlayHistory:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.IndexBody.self) {
                playHistory(startAt: body.index)
            }
        case .libraryShufflePlay:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.PlaylistIdBody.self) {
                playPlaylist(id: body.playlistId, startAt: 0, shuffle: true)
            }

        case .libraryLike:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.VideoIdBody.self) {
                setFavorite(videoId: body.videoId, liked: true)
            }
        case .libraryUnlike:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.VideoIdBody.self) {
                setFavorite(videoId: body.videoId, liked: false)
            }
        case .libraryNotInterested:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.VideoIdBody.self) {
                _ = store?.toggleNotInterested(videoId: body.videoId)
                pushSnapshot(force: true)
            }
        case .libraryRemoveFromHistory:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.IdsBody.self) {
                store?.removeLastPlayed(trackIds: body.ids)
                pushSnapshot(force: true)
            }
        case .libraryAddToPlaylist:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.AddToPlaylistBody.self) {
                addToPlaylist(videoId: body.videoId, playlistId: body.playlistId)
            }
        case .libraryRemoveFromPlaylist:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.RemoveFromPlaylistBody.self) {
                removeFromPlaylist(videoId: body.videoId, playlistId: body.playlistId)
            }
        case .libraryCreatePlaylist:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.CreatePlaylistBody.self) {
                let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    _ = store?.createPlaylist(name: name)
                    pushSnapshot(force: true)
                }
            }
        case .libraryRenamePlaylist:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.RenamePlaylistBody.self),
               let playlist = store?.playlist(id: body.playlistId) {
                store?.renamePlaylist(playlist, name: body.name)
                pushSnapshot(force: true)
            }
        case .libraryDeletePlaylist:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.PlaylistIdBody.self) {
                _ = store?.deletePlaylist(id: body.playlistId)
                pushSnapshot(force: true)
            }
        case .librarySetPinned:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.SetPinnedBody.self),
               let playlist = store?.playlist(id: body.playlistId) {
                store?.setPlaylistPinned(playlist, pinned: body.pinned)
                pushSnapshot(force: true)
            }
        case .libraryEditTrackMetadata:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.EditMetadataBody.self) {
                store?.saveMetadata(
                    trackId: body.videoId,
                    customTitle: body.title,
                    customArtistName: body.artist,
                    customThumbnailUrl: body.thumbnailURL,
                    customAlbum: body.album,
                    customYear: body.year
                )
                pushSnapshot(force: true)
            }
        case .libraryQueuePlayNext:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.VideoIdBody.self),
               let item = resolveVideoItem(videoId: body.videoId) {
                playback?.insertNext(item)
            }
        case .libraryQueueAppend:
            if let body = try? envelope.decodePayload(WatchConnectivityProtocol.VideoIdBody.self),
               let item = resolveVideoItem(videoId: body.videoId) {
                playback?.appendToQueue(item)
            }
        case .sharePresent:
            presentShare(videoId: (try? envelope.decodePayload(WatchConnectivityProtocol.VideoIdBody.self))?.videoId, requestId: envelope.id)

        default:
            break
        }
    }

    private func setFavorite(videoId: String, liked: Bool) {
        guard let store, let item = resolveVideoItem(videoId: videoId) else { return }
        let isFav = store.isFavorite(videoId: videoId)
        if liked, !isFav {
            store.toggleFavorite(item: item)
        } else if !liked, isFav {
            store.toggleFavorite(item: item)
        }
        pushSnapshot(force: true)
    }

    private func addToPlaylist(videoId: String, playlistId: String) {
        guard let store,
              let playlist = store.playlist(id: playlistId),
              let item = resolveVideoItem(videoId: videoId)
        else { return }
        store.add(item: item, to: playlist)
        pushSnapshot(force: true)
    }

    private func removeFromPlaylist(videoId: String, playlistId: String) {
        guard let store, let playlist = store.playlist(id: playlistId) else { return }
        store.remove(trackId: videoId, from: playlist)
        pushSnapshot(force: true)
    }

    private func playPlaylist(id playlistId: String, startAt index: Int, shuffle: Bool) {
        guard let store, let playback else { return }
        guard let playlist = store.playlist(id: playlistId) else { return }
        let items = playlist.entries
            .sorted { $0.position < $1.position }
            .compactMap { entry -> VideoItem? in
                guard let track = entry.track else { return nil }
                return store.displayItem(for: track.asVideoItem)
            }
        guard !items.isEmpty else { return }
        if shuffle, !playback.shuffleEnabled {
            _ = playback.toggleShuffle()
        }
        if !shuffle, playback.shuffleEnabled {
            _ = playback.toggleShuffle()
        }
        playback.play(
            items: items,
            startAt: index,
            sourcePlaylistId: playlistId,
            analyticsSource: shuffle ? "watch_shuffle" : "watch_library"
        )
    }

    private func playHistory(startAt index: Int) {
        guard let store, let playback else { return }
        let items = store.historyVideos(limit: Self.maxHistory).map { store.displayItem(for: $0) }
        guard !items.isEmpty else { return }
        playback.play(items: items, startAt: index, analyticsSource: "watch_history")
    }

    private func resolveVideoItem(videoId: String) -> VideoItem? {
        guard let store else { return nil }
        if let track = store.track(id: videoId) {
            return store.displayItem(for: track.asVideoItem)
        }
        if let fromHistory = store.historyVideos(limit: 200).first(where: { $0.videoId == videoId }) {
            return store.displayItem(for: fromHistory)
        }
        return VideoItem(videoId: videoId, title: videoId, channelName: "")
    }

    private func presentShare(videoId: String?, requestId: String) {
        guard let videoId, !videoId.isEmpty else {
            sendShareResult(requestId: requestId, ok: false, message: "missing_video")
            return
        }
        let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
        guard let presenter = UIApplication.shared.topViewController else {
            sendShareResult(requestId: requestId, ok: false, message: "no_presenter")
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true) { [weak self] in
            self?.sendShareResult(requestId: requestId, ok: true, message: nil)
        }
    }

    private func sendShareResult(requestId: String, ok: Bool, message: String?) {
        let body = WatchConnectivityProtocol.ShareResultBody(
            requestId: requestId,
            ok: ok,
            message: message
        )
        guard let envelope = try? WatchConnectivityProtocol.Envelope.make(kind: .shareResult, body: body) else { return }
        let bridge = WatchConnectivityBridge.shared
        if bridge.isReachable {
            _ = bridge.send(envelope)
        } else {
            bridge.transferUserInfo(envelope)
        }
    }

    private func pushSnapshot(force: Bool = false) {
        guard let store else { return }
        let snapshot = makeSnapshot(from: store)
        if !force, snapshot == lastPushed { return }
        lastPushed = snapshot

        do {
            let envelope = try WatchConnectivityProtocol.Envelope.make(
                kind: .librarySnapshot,
                body: snapshot
            )
            let bridge = WatchConnectivityBridge.shared
            if bridge.isReachable {
                _ = bridge.send(envelope)
            } else {
                bridge.transferUserInfo(envelope)
            }
        } catch {
            // Best-effort.
        }
    }

    private func makeSnapshot(from store: LibraryStore) -> WatchConnectivityProtocol.LibrarySnapshot {
        let playlists = Array(store.playlistsInLibraryOrder().prefix(Self.maxPlaylists)).map { playlist in
            let sortedEntries = playlist.entries.sorted { $0.position < $1.position }
            let tracks = Array(sortedEntries.prefix(Self.maxTracksPerPlaylist)).compactMap { entry -> WatchConnectivityProtocol.LibraryTrackDTO? in
                guard let track = entry.track else { return nil }
                let displayed = store.displayItem(for: track.asVideoItem)
                return WatchConnectivityProtocol.LibraryTrackDTO(
                    videoId: displayed.videoId,
                    title: displayed.title,
                    artist: displayed.channelName,
                    thumbnailURL: displayed.thumbnailURL?.absoluteString,
                    durationText: displayed.durationText
                )
            }
            return WatchConnectivityProtocol.LibraryPlaylistDTO(
                playlistId: playlist.playlistId,
                name: displayName(for: playlist),
                coverURL: playlist.coverUrlOrPath,
                systemType: playlist.systemType,
                trackCount: playlist.trackCount,
                canEdit: playlist.systemType == nil,
                isPinned: playlist.isPinned,
                tracks: tracks
            )
        }

        let history = store.historyVideos(limit: Self.maxHistory).map { item in
            let displayed = store.displayItem(for: item)
            return WatchConnectivityProtocol.LibraryTrackDTO(
                videoId: displayed.videoId,
                title: displayed.title,
                artist: displayed.channelName,
                thumbnailURL: displayed.thumbnailURL?.absoluteString,
                durationText: displayed.durationText
            )
        }

        let favoriteIds: [String] = {
            guard let fav = store.favoritesPlaylist() else { return [] }
            return fav.entries
                .sorted { $0.position < $1.position }
                .compactMap(\.track?.trackId)
        }()

        let isGuest = !(auth?.isAuthenticated ?? false)
        return WatchConnectivityProtocol.LibrarySnapshot(
            playlists: playlists,
            history: history,
            favoriteVideoIds: favoriteIds,
            authIsGuest: isGuest,
            authDisplayName: isGuest ? nil : auth?.displayName,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    private func displayName(for playlist: LibraryPlaylist) -> String {
        switch playlist.systemType {
        case SystemPlaylistType.favorites:
            return "Liked"
        case SystemPlaylistType.watchLater:
            return "Watch later"
        default:
            return playlist.name
        }
    }
}
