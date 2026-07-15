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
        // Names match Supabase seed_system_playlists() / Android.
        ensureSystemPlaylist(name: "Liked videos", systemType: SystemPlaylistType.favorites)
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
        let durationText = item.durationText ?? DurationFormat.text(seconds: resolvedDuration)
        let trackId = item.videoId
        var descriptor = FetchDescriptor<LibraryTrack>(
            predicate: #Predicate { $0.trackId == trackId }
        )
        descriptor.fetchLimit = 1
        let thumb = item.thumbnailURL?.absoluteString
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = item.title
            existing.primaryArtistName = item.channelName
            if let thumb {
                existing.thumbnailHigh = thumb
            }
            if resolvedDuration > 0 {
                existing.durationSeconds = resolvedDuration
                existing.durationText = durationText
            } else if let durationText {
                existing.durationText = durationText
            }
            existing.updatedAt = .now
            return existing
        }
        let track = LibraryTrack(
            trackId: item.videoId,
            title: item.title,
            durationSeconds: resolvedDuration,
            durationText: durationText,
            thumbnailHigh: thumb,
            primaryArtistName: item.channelName
        )
        modelContext.insert(track)
        return track
    }

    @discardableResult
    func upsertTrackEntity(_ track: LibraryTrack) -> LibraryTrack {
        let trackId = track.trackId
        var descriptor = FetchDescriptor<LibraryTrack>(
            predicate: #Predicate { $0.trackId == trackId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = track.title
            if track.durationSeconds > 0 { existing.durationSeconds = track.durationSeconds }
            if let text = track.durationText { existing.durationText = text }
            if let v = track.thumbnailLow { existing.thumbnailLow = v }
            if let v = track.thumbnailMedium { existing.thumbnailMedium = v }
            if let v = track.thumbnailHigh { existing.thumbnailHigh = v }
            if track.viewCount > 0 { existing.viewCount = track.viewCount }
            if let v = track.viewCountText { existing.viewCountText = v }
            if let v = track.publishedText { existing.publishedText = v }
            if let v = track.primaryArtistId { existing.primaryArtistId = v }
            if let v = track.primaryArtistName { existing.primaryArtistName = v }
            existing.updatedAt = .now
            return existing
        }
        modelContext.insert(track)
        return track
    }

    func track(id trackId: String) -> LibraryTrack? {
        var descriptor = FetchDescriptor<LibraryTrack>(
            predicate: #Predicate { $0.trackId == trackId }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
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

    /// Recent plays for Library Songs (resolved via tracks), mirroring Android last-played list.
    func historyVideos(limit: Int = 100) -> [VideoItem] {
        lastPlayed(limit: limit).compactMap { row in
            track(id: row.trackId)?.asVideoItem
        }
    }

    func playbackHistory(limit: Int = 50) -> [PlaybackHistoryItem] {
        var descriptor = FetchDescriptor<PlaybackHistoryItem>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Legacy name used by sync / older call sites.
    func history(limit: Int = 100) -> [PlaybackHistoryItem] {
        playbackHistory(limit: limit)
    }

    func lastPlayed(limit: Int = 100) -> [UserTrackLastPlayed] {
        var descriptor = FetchDescriptor<UserTrackLastPlayed>(
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allMetadata() -> [UserTrackMetadata] {
        (try? modelContext.fetch(FetchDescriptor<UserTrackMetadata>())) ?? []
    }

    func allSubscribedChannels() -> [UserSubscribedChannel] {
        let descriptor = FetchDescriptor<UserSubscribedChannel>(
            sortBy: [SortDescriptor(\.subscribedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func isFavorite(videoId: String) -> Bool {
        guard let fav = favoritesPlaylist() else { return false }
        return fav.entries.contains { $0.track?.trackId == videoId }
    }

    func toggleFavorite(item: VideoItem) {
        guard let fav = favoritesPlaylist() else { return }
        if let entry = fav.entries.first(where: { $0.track?.trackId == item.videoId }) {
            modelContext.delete(entry)
        } else {
            let track = upsertTrack(from: item)
            let entry = LibraryPlaylistEntry(position: fav.entries.count, track: track)
            fav.entries.append(entry)
            fav.updatedAt = .now
            fav.isSynced = false
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
        if playlist.entries.contains(where: { $0.track?.trackId == item.videoId }) {
            return
        }
        let track = upsertTrack(from: item)
        let entry = LibraryPlaylistEntry(position: playlist.entries.count, track: track)
        playlist.entries.append(entry)
        playlist.updatedAt = .now
        playlist.isSynced = false
        save()
    }

    func recordPlayback(_ item: NowPlayingItem, durationSeconds: Int = 0, progressMs: Int64 = 0) {
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

        let history = PlaybackHistoryItem(
            trackId: item.videoId,
            progressMs: progressMs,
            isSynced: false
        )
        modelContext.insert(history)

        let trackId = item.videoId
        var descriptor = FetchDescriptor<UserTrackLastPlayed>(
            predicate: #Predicate { $0.trackId == trackId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.lastPlayedAt = .now
            existing.progressMs = progressMs
            existing.isSynced = false
        } else {
            modelContext.insert(
                UserTrackLastPlayed(trackId: trackId, progressMs: progressMs, isSynced: false)
            )
        }
        save()
    }

    func upsertLastPlayedRemote(
        trackId: String,
        lastPlayedAt: Date,
        progressMs: Int64
    ) {
        var descriptor = FetchDescriptor<UserTrackLastPlayed>(
            predicate: #Predicate { $0.trackId == trackId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            if lastPlayedAt > existing.lastPlayedAt {
                existing.lastPlayedAt = lastPlayedAt
                existing.progressMs = progressMs
            }
            existing.isSynced = true
        } else {
            modelContext.insert(
                UserTrackLastPlayed(
                    trackId: trackId,
                    lastPlayedAt: lastPlayedAt,
                    progressMs: progressMs,
                    isSynced: true
                )
            )
        }
    }

    func upsertMetadata(_ meta: UserTrackMetadata) {
        let trackId = meta.trackId
        var descriptor = FetchDescriptor<UserTrackMetadata>(
            predicate: #Predicate { $0.trackId == trackId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.customTitle = meta.customTitle
            existing.customArtistName = meta.customArtistName
            existing.customThumbnailUrl = meta.customThumbnailUrl
            existing.customAlbum = meta.customAlbum
            existing.customYear = meta.customYear
            existing.updatedAt = meta.updatedAt
            existing.isSynced = meta.isSynced
        } else {
            modelContext.insert(meta)
        }
    }

    func upsertSubscribedChannel(_ channel: UserSubscribedChannel) {
        let channelId = channel.channelId
        var descriptor = FetchDescriptor<UserSubscribedChannel>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = channel.title
            existing.handle = channel.handle
            existing.avatarUrl = channel.avatarUrl
            existing.subscriberCountText = channel.subscriberCountText
            existing.descriptionText = channel.descriptionText
            existing.subscribedAt = channel.subscribedAt
            existing.isSynced = channel.isSynced
        } else {
            modelContext.insert(channel)
        }
    }

    func deletePlaylist(_ playlist: LibraryPlaylist) {
        guard playlist.systemType == nil else { return }
        modelContext.delete(playlist)
        save()
    }

    func remove(trackId: String, from playlist: LibraryPlaylist) {
        guard let entry = playlist.entries.first(where: { $0.track?.trackId == trackId }) else { return }
        modelContext.delete(entry)
        for (index, remaining) in playlist.entries.sorted(by: { $0.position < $1.position }).enumerated() {
            remaining.position = index
        }
        playlist.updatedAt = .now
        playlist.isSynced = false
        save()
    }

    func playlist(id playlistId: String) -> LibraryPlaylist? {
        allPlaylists().first { $0.playlistId == playlistId }
    }

    // MARK: - Not interested

    func isNotInterested(videoId: String) -> Bool {
        var descriptor = FetchDescriptor<NotInterestedItem>(
            predicate: #Predicate { $0.videoId == videoId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first != nil
    }

    @discardableResult
    func toggleNotInterested(videoId: String) -> Bool {
        var descriptor = FetchDescriptor<NotInterestedItem>(
            predicate: #Predicate { $0.videoId == videoId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            save()
            return false
        }
        modelContext.insert(NotInterestedItem(videoId: videoId))
        save()
        return true
    }

    func removeNotInterested(videoId: String) {
        var descriptor = FetchDescriptor<NotInterestedItem>(
            predicate: #Predicate { $0.videoId == videoId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            save()
        }
    }

    // MARK: - Metadata

    func metadata(for trackId: String) -> UserTrackMetadata? {
        var descriptor = FetchDescriptor<UserTrackMetadata>(
            predicate: #Predicate { $0.trackId == trackId }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func saveMetadata(
        trackId: String,
        customTitle: String?,
        customArtistName: String?,
        customThumbnailUrl: String?,
        customAlbum: String?,
        customYear: String?
    ) {
        let cleanedTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cleanedArtist = customArtistName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cleanedThumb = customThumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cleanedAlbum = customAlbum?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cleanedYear = customYear?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        upsertMetadata(
            UserTrackMetadata(
                trackId: trackId,
                customTitle: cleanedTitle,
                customArtistName: cleanedArtist,
                customThumbnailUrl: cleanedThumb,
                customAlbum: cleanedAlbum,
                customYear: cleanedYear,
                updatedAt: .now,
                isSynced: false
            )
        )
        save()
    }

    /// Apply local metadata overrides onto a display VideoItem.
    func displayItem(for item: VideoItem) -> VideoItem {
        guard let meta = metadata(for: item.videoId) else { return item }
        return VideoItem(
            videoId: item.videoId,
            title: meta.customTitle ?? item.title,
            channelName: meta.customArtistName ?? item.channelName,
            subtitle: item.subtitle,
            thumbnailURL: meta.customThumbnailUrl.flatMap(URL.init(string:)) ?? item.thumbnailURL,
            channelAvatarURL: item.channelAvatarURL,
            durationText: item.durationText,
            viewCountText: item.viewCountText,
            publishedTimeText: item.publishedTimeText
        )
    }

    func filterNotInterested(_ items: [VideoItem]) -> [VideoItem] {
        items.filter { !isNotInterested(videoId: $0.videoId) }.map { displayItem(for: $0) }
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

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
