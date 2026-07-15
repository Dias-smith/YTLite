import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class LibraryStore {
    private let modelContext: ModelContext
    var onMutate: (() -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        ensureSystemPlaylists()
    }

    func ensureSystemPlaylists() {
        ensureSystemPlaylist(name: "Favorites", systemType: SystemPlaylistType.favorites)
        ensureSystemPlaylist(name: "Watch later", systemType: SystemPlaylistType.watchLater)
        try? modelContext.save()
    }

    private func ensureSystemPlaylist(name: String, systemType: String) {
        var descriptor = FetchDescriptor<LibraryPlaylist>(
            predicate: #Predicate { $0.systemType == systemType }
        )
        descriptor.fetchLimit = 1
        if (try? modelContext.fetch(descriptor))?.first != nil { return }
        modelContext.insert(LibraryPlaylist(name: name, systemType: systemType, isPinned: true))
    }

    func upsertTrack(from item: VideoItem, durationSeconds: Int = 0) -> LibraryTrack {
        let resolvedDuration = durationSeconds > 0
            ? durationSeconds
            : DurationFormat.seconds(from: item.durationText)
        let videoId = item.videoId
        var descriptor = FetchDescriptor<LibraryTrack>(
            predicate: #Predicate { $0.videoId == videoId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = item.title
            existing.channelName = item.channelName
            existing.thumbnailURLString = item.thumbnailURL?.absoluteString
            if resolvedDuration > 0 { existing.durationSeconds = resolvedDuration }
            existing.updatedAt = .now
            return existing
        }
        let track = LibraryTrack(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURLString: item.thumbnailURL?.absoluteString,
            durationSeconds: resolvedDuration
        )
        modelContext.insert(track)
        return track
    }

    func favoritesPlaylist() -> LibraryPlaylist? {
        fetchPlaylist(systemType: SystemPlaylistType.favorites)
    }

    func allPlaylists() -> [LibraryPlaylist] {
        let descriptor = FetchDescriptor<LibraryPlaylist>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func history(limit: Int = 100) -> [PlayHistoryItem] {
        var descriptor = FetchDescriptor<PlayHistoryItem>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func isFavorite(videoId: String) -> Bool {
        guard let fav = favoritesPlaylist() else { return false }
        return fav.entries.contains { $0.track?.videoId == videoId }
    }

    func toggleFavorite(item: VideoItem) {
        guard let fav = favoritesPlaylist() else { return }
        if let entry = fav.entries.first(where: { $0.track?.videoId == item.videoId }) {
            modelContext.delete(entry)
        } else {
            let track = upsertTrack(from: item)
            let entry = LibraryPlaylistEntry(position: fav.entries.count, track: track)
            fav.entries.append(entry)
            fav.updatedAt = .now
        }
        save()
    }

    func createPlaylist(name: String, playlistId: String = UUID().uuidString) -> LibraryPlaylist {
        let playlist = LibraryPlaylist(
            playlistId: playlistId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(playlist)
        save()
        return playlist
    }

    func insertImportedPlaylist(_ playlist: LibraryPlaylist) {
        if allPlaylists().contains(where: { $0.playlistId == playlist.playlistId }) { return }
        modelContext.insert(playlist)
        save()
    }

    func add(item: VideoItem, to playlist: LibraryPlaylist) {
        if playlist.entries.contains(where: { $0.track?.videoId == item.videoId }) {
            return
        }
        let track = upsertTrack(from: item)
        let entry = LibraryPlaylistEntry(position: playlist.entries.count, track: track)
        playlist.entries.append(entry)
        playlist.updatedAt = .now
        save()
    }

    func recordPlayback(_ item: NowPlayingItem, durationSeconds: Int = 0) {
        let resolvedDuration = durationSeconds > 0
            ? durationSeconds
            : DurationFormat.seconds(from: item.durationText)
        let video = VideoItem(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURL: item.thumbnailURL,
            durationText: DurationFormat.text(seconds: resolvedDuration) ?? item.durationText
        )
        _ = upsertTrack(from: video, durationSeconds: resolvedDuration)
        let history = PlayHistoryItem(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURLString: item.thumbnailURL?.absoluteString,
            durationSeconds: resolvedDuration > 0 ? resolvedDuration : nil
        )
        modelContext.insert(history)
        save()
    }

    func deletePlaylist(_ playlist: LibraryPlaylist) {
        guard playlist.systemType == nil else { return }
        modelContext.delete(playlist)
        save()
    }

    func save() {
        try? modelContext.save()
        onMutate?()
    }

    private func fetchPlaylist(systemType: String) -> LibraryPlaylist? {
        var descriptor = FetchDescriptor<LibraryPlaylist>(
            predicate: #Predicate { $0.systemType == systemType }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
