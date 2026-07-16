import Foundation
import SwiftData
import Observation
import UIKit

@MainActor
@Observable
final class LibraryStore {
    private let modelContext: ModelContext
    /// Active account bucket (`guest:…` / `user:…`).
    private(set) var ownerKey: String
    var onMutate: (() -> Void)?
    /// Fired after a channel is removed locally so sync can delete the remote row.
    var onUnsubscribeChannel: ((String) -> Void)?

    init(
        modelContext: ModelContext,
        ownerKey: String = OwnerKeyStore.stableGuestOwnerKey
    ) {
        self.modelContext = modelContext
        self.ownerKey = ownerKey
        migrateUnscopedRowsIfNeeded(to: ownerKey)
        ensureSystemPlaylists()
        migrateLegacyPlaylistCovers()
    }

    /// Switch active bucket without deleting other owners' data.
    func setOwnerKey(_ key: String) {
        guard key != ownerKey else {
            ensureSystemPlaylists()
            return
        }
        ownerKey = key
        ensureSystemPlaylists()
    }

    func ensureSystemPlaylists() {
        ensureSystemPlaylists(for: ownerKey)
    }

    func ensureSystemPlaylists(for key: String) {
        ensureSystemPlaylist(for: key, name: "Liked videos", systemType: SystemPlaylistType.favorites)
        ensureSystemPlaylist(for: key, name: "Watch later", systemType: SystemPlaylistType.watchLater)
        try? modelContext.save()
    }

    private func ensureSystemPlaylist(for key: String, name: String, systemType: String) {
        var descriptor = FetchDescriptor<LibraryPlaylist>(
            predicate: #Predicate { $0.ownerKey == key && $0.systemType == systemType }
        )
        descriptor.fetchLimit = 1
        if (try? modelContext.fetch(descriptor))?.first != nil { return }
        modelContext.insert(
            LibraryPlaylist(ownerKey: key, name: name, systemType: systemType, isPinned: true)
        )
    }

    // MARK: - Owner migration / guest merge

    /// Rows created before ownerKey existed (or wiped empty) inherit the boot owner.
    private func migrateUnscopedRowsIfNeeded(to key: String) {
        let empty = ""
        var changed = false

        let playlists = (try? modelContext.fetch(
            FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.ownerKey == empty })
        )) ?? []
        for row in playlists {
            row.ownerKey = key
            changed = true
        }

        let history = (try? modelContext.fetch(
            FetchDescriptor<PlaybackHistoryItem>(predicate: #Predicate { $0.ownerKey == empty })
        )) ?? []
        for row in history {
            row.ownerKey = key
            changed = true
        }

        let lastPlayed = (try? modelContext.fetch(
            FetchDescriptor<UserTrackLastPlayed>(predicate: #Predicate { $0.ownerKey == empty })
        )) ?? []
        for row in lastPlayed {
            row.ownerKey = key
            changed = true
        }

        let metadata = (try? modelContext.fetch(
            FetchDescriptor<UserTrackMetadata>(predicate: #Predicate { $0.ownerKey == empty })
        )) ?? []
        for row in metadata {
            row.ownerKey = key
            changed = true
        }

        let channels = (try? modelContext.fetch(
            FetchDescriptor<UserSubscribedChannel>(predicate: #Predicate { $0.ownerKey == empty })
        )) ?? []
        for row in channels {
            row.ownerKey = key
            changed = true
        }

        let notInterested = (try? modelContext.fetch(
            FetchDescriptor<NotInterestedItem>(predicate: #Predicate { $0.ownerKey == empty })
        )) ?? []
        for row in notInterested {
            row.ownerKey = key
            changed = true
        }

        if changed {
            try? modelContext.save()
        }
    }

    /// Re-home guest bucket into `userKey`, merging system playlists; conflict prefers existing user rows.
    func mergeGuestIntoUser(guestKey: String, userKey: String) {
        guard guestKey != userKey else { return }
        let previousMutate = onMutate
        onMutate = nil
        defer { onMutate = previousMutate }

        ensureSystemPlaylists(for: guestKey)

        let guestSystem = fetchPlaylists(ownerKey: guestKey).filter { $0.systemType != nil }
        for playlist in guestSystem {
            playlist.ownerKey = userKey
            playlist.isSynced = false
            playlist.updatedAt = .now
        }

        ensureSystemPlaylists(for: userKey)
        deduplicateSystemPlaylists(for: userKey)

        mergeLastPlayed(from: guestKey, to: userKey)
        mergeHistory(from: guestKey, to: userKey)
        mergeMetadata(from: guestKey, to: userKey)
        mergeChannels(from: guestKey, to: userKey)
        mergeNotInterested(from: guestKey, to: userKey)

        for playlist in fetchPlaylists(ownerKey: guestKey).filter({ $0.systemType == nil }) {
            if let userPlaylist = fetchPlaylists(ownerKey: userKey)
                .first(where: { $0.playlistId == playlist.playlistId }) {
                mergeEntries(from: playlist, into: userPlaylist)
                modelContext.delete(playlist)
            } else {
                playlist.ownerKey = userKey
                playlist.isSynced = false
                playlist.updatedAt = .now
            }
        }

        ownerKey = userKey
        deduplicateSystemPlaylists(for: userKey)
        try? modelContext.save()
    }

    private func mergeLastPlayed(from guestKey: String, to userKey: String) {
        let guestRows = (try? modelContext.fetch(
            FetchDescriptor<UserTrackLastPlayed>(predicate: #Predicate { $0.ownerKey == guestKey })
        )) ?? []
        let userRows = (try? modelContext.fetch(
            FetchDescriptor<UserTrackLastPlayed>(predicate: #Predicate { $0.ownerKey == userKey })
        )) ?? []
        let userById = Dictionary(uniqueKeysWithValues: userRows.map { ($0.trackId, $0) })
        for guest in guestRows {
            if let user = userById[guest.trackId] {
                if guest.lastPlayedAt > user.lastPlayedAt {
                    user.lastPlayedAt = guest.lastPlayedAt
                    user.progressMs = guest.progressMs
                    user.isSynced = false
                }
                modelContext.delete(guest)
            } else {
                guest.ownerKey = userKey
                guest.isSynced = false
            }
        }
    }

    private func mergeHistory(from guestKey: String, to userKey: String) {
        let rows = (try? modelContext.fetch(
            FetchDescriptor<PlaybackHistoryItem>(predicate: #Predicate { $0.ownerKey == guestKey })
        )) ?? []
        for row in rows {
            row.ownerKey = userKey
            row.isSynced = false
        }
    }

    private func mergeMetadata(from guestKey: String, to userKey: String) {
        let guestRows = (try? modelContext.fetch(
            FetchDescriptor<UserTrackMetadata>(predicate: #Predicate { $0.ownerKey == guestKey })
        )) ?? []
        let userRows = (try? modelContext.fetch(
            FetchDescriptor<UserTrackMetadata>(predicate: #Predicate { $0.ownerKey == userKey })
        )) ?? []
        let userById = Dictionary(uniqueKeysWithValues: userRows.map { ($0.trackId, $0) })
        for guest in guestRows {
            if userById[guest.trackId] != nil {
                modelContext.delete(guest)
            } else {
                guest.ownerKey = userKey
                guest.isSynced = false
            }
        }
    }

    private func mergeChannels(from guestKey: String, to userKey: String) {
        let guestRows = (try? modelContext.fetch(
            FetchDescriptor<UserSubscribedChannel>(predicate: #Predicate { $0.ownerKey == guestKey })
        )) ?? []
        let userRows = (try? modelContext.fetch(
            FetchDescriptor<UserSubscribedChannel>(predicate: #Predicate { $0.ownerKey == userKey })
        )) ?? []
        let userById = Dictionary(uniqueKeysWithValues: userRows.map { ($0.channelId, $0) })
        for guest in guestRows {
            if userById[guest.channelId] != nil {
                modelContext.delete(guest)
            } else {
                guest.ownerKey = userKey
                guest.isSynced = false
            }
        }
    }

    private func mergeNotInterested(from guestKey: String, to userKey: String) {
        let guestRows = (try? modelContext.fetch(
            FetchDescriptor<NotInterestedItem>(predicate: #Predicate { $0.ownerKey == guestKey })
        )) ?? []
        let userRows = (try? modelContext.fetch(
            FetchDescriptor<NotInterestedItem>(predicate: #Predicate { $0.ownerKey == userKey })
        )) ?? []
        let userById = Dictionary(uniqueKeysWithValues: userRows.map { ($0.videoId, $0) })
        for guest in guestRows {
            if userById[guest.videoId] != nil {
                modelContext.delete(guest)
            } else {
                guest.ownerKey = userKey
            }
        }
    }

    private func deduplicateSystemPlaylists(for key: String) {
        for systemType in [SystemPlaylistType.favorites, SystemPlaylistType.watchLater] {
            let duplicates = fetchPlaylists(ownerKey: key).filter { $0.systemType == systemType }
            guard duplicates.count > 1 else { continue }
            let canonical = duplicates.max { a, b in
                if a.isSynced != b.isSynced { return !a.isSynced && b.isSynced }
                if a.entries.count != b.entries.count { return a.entries.count < b.entries.count }
                return a.updatedAt < b.updatedAt
            }!
            for dup in duplicates where dup.playlistId != canonical.playlistId {
                mergeEntries(from: dup, into: canonical)
                modelContext.delete(dup)
            }
            canonical.isSynced = false
            canonical.updatedAt = .now
        }
    }

    private func mergeEntries(from source: LibraryPlaylist, into target: LibraryPlaylist) {
        let existingIds = Set(target.entries.compactMap { $0.track?.trackId })
        var nextPos = target.entries.count
        for entry in source.entries.sorted(by: { $0.position < $1.position }) {
            guard let track = entry.track, !existingIds.contains(track.trackId) else { continue }
            let copy = LibraryPlaylistEntry(
                position: nextPos,
                track: track,
                createdAt: entry.createdAt,
                isSynced: false
            )
            target.entries.append(copy)
            nextPos += 1
        }
    }

    private func fetchPlaylists(ownerKey key: String) -> [LibraryPlaylist] {
        (try? modelContext.fetch(
            FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.ownerKey == key })
        )) ?? []
    }

    // MARK: - Tracks (global catalogue)

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
        playlistsInLibraryOrder()
    }

    /// Library tab / Save-to-library picker: Liked → Watch later → custom (oldest → newest).
    func playlistsInLibraryOrder() -> [LibraryPlaylist] {
        let key = ownerKey
        let all = (try? modelContext.fetch(
            FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.ownerKey == key })
        )) ?? []
        let liked = all.first { $0.systemType == SystemPlaylistType.favorites }
        let watchLater = all.first { $0.systemType == SystemPlaylistType.watchLater }
        let custom = all
            .filter { $0.systemType == nil }
            .sorted { $0.sortCreatedAt < $1.sortCreatedAt }
        return [liked, watchLater].compactMap { $0 } + custom
    }

    func historyVideos(limit: Int = 100) -> [VideoItem] {
        let rows = lastPlayed(limit: limit)
        guard !rows.isEmpty else { return [] }
        let ids = rows.map(\.trackId)
        let tracksById = Dictionary(
            uniqueKeysWithValues: tracks(ids: ids).map { ($0.trackId, $0) }
        )
        return rows.compactMap { tracksById[$0.trackId]?.asVideoItem }
    }

    private func tracks(ids: [String]) -> [LibraryTrack] {
        guard !ids.isEmpty else { return [] }
        let wanted = ids
        return (try? modelContext.fetch(
            FetchDescriptor<LibraryTrack>(predicate: #Predicate { wanted.contains($0.trackId) })
        )) ?? []
    }

    enum LibrarySongSort {
        case recentActivity
        case recentlySaved
        case title
        case duration
    }

    func librarySongs(sort: LibrarySongSort = .recentActivity) -> [VideoItem] {
        struct Acc {
            var item: VideoItem
            var activity: Date
            var saved: Date
        }

        var byId: [String: Acc] = [:]
        let playedAtById = Dictionary(
            lastPlayed(limit: 500).map { ($0.trackId, $0.lastPlayedAt) },
            uniquingKeysWith: { a, b in max(a, b) }
        )

        for playlist in allPlaylists() {
            for entry in playlist.entries {
                guard let track = entry.track else { continue }
                let id = track.trackId
                let item = displayItem(for: track.asVideoItem)
                let saved = entry.createdAt
                let activity = max(playedAtById[id] ?? .distantPast, saved)
                if let prev = byId[id] {
                    byId[id] = Acc(
                        item: item,
                        activity: max(prev.activity, activity),
                        saved: max(prev.saved, saved)
                    )
                } else {
                    byId[id] = Acc(item: item, activity: activity, saved: saved)
                }
            }
        }

        for video in historyVideos(limit: 200) {
            let id = video.videoId
            guard byId[id] == nil else { continue }
            let at = playedAtById[id] ?? .distantPast
            byId[id] = Acc(item: displayItem(for: video), activity: at, saved: at)
        }

        let values = Array(byId.values)
        switch sort {
        case .recentActivity:
            return values.sorted { $0.activity > $1.activity }.map(\.item)
        case .recentlySaved:
            return values.sorted { $0.saved > $1.saved }.map(\.item)
        case .title:
            return values.sorted {
                $0.item.title.localizedCaseInsensitiveCompare($1.item.title) == .orderedAscending
            }.map(\.item)
        case .duration:
            return values.sorted {
                let da = DurationFormat.seconds(from: $0.item.durationText)
                let db = DurationFormat.seconds(from: $1.item.durationText)
                if da != db { return da > db }
                return $0.item.title.localizedCaseInsensitiveCompare($1.item.title) == .orderedAscending
            }.map(\.item)
        }
    }

    func removeTracksFromLocalLibrary(trackIds: [String]) {
        let ids = Set(trackIds)
        guard !ids.isEmpty else { return }
        let key = ownerKey
        for playlist in allPlaylists() {
            let doomed = playlist.entries.filter { entry in
                guard let tid = entry.track?.trackId else { return false }
                return ids.contains(tid)
            }
            guard !doomed.isEmpty else { continue }
            for entry in doomed {
                modelContext.delete(entry)
            }
            for (index, remaining) in playlist.entries.sorted(by: { $0.position < $1.position }).enumerated() {
                remaining.position = index
            }
            playlist.updatedAt = .now
            playlist.isSynced = false
        }
        for id in ids {
            var descriptor = FetchDescriptor<UserTrackLastPlayed>(
                predicate: #Predicate { $0.ownerKey == key && $0.trackId == id }
            )
            descriptor.fetchLimit = 1
            if let row = try? modelContext.fetch(descriptor).first {
                modelContext.delete(row)
            }
        }
        save()
    }

    func playbackHistory(limit: Int = 50) -> [PlaybackHistoryItem] {
        let key = ownerKey
        var descriptor = FetchDescriptor<PlaybackHistoryItem>(
            predicate: #Predicate { $0.ownerKey == key },
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func history(limit: Int = 100) -> [PlaybackHistoryItem] {
        playbackHistory(limit: limit)
    }

    func lastPlayed(limit: Int = 100) -> [UserTrackLastPlayed] {
        let key = ownerKey
        var descriptor = FetchDescriptor<UserTrackLastPlayed>(
            predicate: #Predicate { $0.ownerKey == key },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allMetadata() -> [UserTrackMetadata] {
        let key = ownerKey
        return (try? modelContext.fetch(
            FetchDescriptor<UserTrackMetadata>(predicate: #Predicate { $0.ownerKey == key })
        )) ?? []
    }

    func allSubscribedChannels() -> [UserSubscribedChannel] {
        let key = ownerKey
        let descriptor = FetchDescriptor<UserSubscribedChannel>(
            predicate: #Predicate { $0.ownerKey == key },
            sortBy: [SortDescriptor(\.subscribedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func isSubscribed(channelId: String) -> Bool {
        guard ChannelID.isBrowsable(channelId) else { return false }
        return subscribedChannel(id: channelId) != nil
    }

    func subscribedChannel(id channelId: String) -> UserSubscribedChannel? {
        let id = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = ownerKey
        var descriptor = FetchDescriptor<UserSubscribedChannel>(
            predicate: #Predicate { $0.ownerKey == key && $0.channelId == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    @discardableResult
    func toggleSubscribeChannel(
        channelId: String,
        title: String,
        avatarUrl: String? = nil,
        handle: String? = nil,
        subscriberCountText: String? = nil,
        descriptionText: String? = nil
    ) -> Bool {
        guard ChannelID.isBrowsable(channelId) else { return false }
        let id = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = subscribedChannel(id: id) {
            modelContext.delete(existing)
            save()
            onUnsubscribeChannel?(id)
            return false
        }
        let channel = UserSubscribedChannel(
            ownerKey: ownerKey,
            channelId: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? id,
            handle: handle,
            avatarUrl: avatarUrl,
            subscriberCountText: subscriberCountText,
            descriptionText: descriptionText,
            subscribedAt: .now,
            isSynced: false
        )
        modelContext.insert(channel)
        save()
        return true
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
            ReviewPromptCoordinator.shared.recordPositiveAction()
        }
        save()
    }

    func createPlaylist(name: String, playlistId: String = UUID().uuidString) -> LibraryPlaylist {
        let playlist = LibraryPlaylist(
            ownerKey: ownerKey,
            playlistId: playlistId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(playlist)
        save()
        ReviewPromptCoordinator.shared.recordPositiveAction()
        return playlist
    }

    func insertImportedPlaylist(_ playlist: LibraryPlaylist, persist: Bool = true) {
        if playlist.ownerKey.isEmpty {
            playlist.ownerKey = ownerKey
        }
        if allPlaylists().contains(where: { $0.playlistId == playlist.playlistId }) { return }
        modelContext.insert(playlist)
        if persist { save() }
    }

    /// - Parameters:
    ///   - persist: when false, skips save/onMutate (used by bulk sync pull).
    ///   - markDirty: when false, keeps playlist sync flags (remote pull).
    func add(
        item: VideoItem,
        to playlist: LibraryPlaylist,
        persist: Bool = true,
        markDirty: Bool = true
    ) {
        if playlist.entries.contains(where: { $0.track?.trackId == item.videoId }) {
            return
        }
        let track = upsertTrack(from: item)
        let entry = LibraryPlaylistEntry(
            position: playlist.entries.count,
            track: track,
            isSynced: !markDirty
        )
        playlist.entries.append(entry)
        if markDirty {
            playlist.updatedAt = .now
            playlist.isSynced = false
        }
        if persist { save() }
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
            channelAvatarURL: item.channelAvatarURL,
            durationText: DurationFormat.text(seconds: resolvedDuration) ?? item.durationText
        )
        let track = upsertTrack(from: video, durationSeconds: resolvedDuration)
        if let channelId = item.channelId, ChannelID.isBrowsable(channelId) {
            track.primaryArtistId = channelId
            track.primaryArtistName = item.channelName
        }

        let key = ownerKey
        let history = PlaybackHistoryItem(
            ownerKey: key,
            trackId: item.videoId,
            progressMs: progressMs,
            isSynced: false
        )
        modelContext.insert(history)

        let trackId = item.videoId
        var descriptor = FetchDescriptor<UserTrackLastPlayed>(
            predicate: #Predicate { $0.ownerKey == key && $0.trackId == trackId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.lastPlayedAt = .now
            existing.progressMs = progressMs
            existing.isSynced = false
        } else {
            modelContext.insert(
                UserTrackLastPlayed(
                    ownerKey: key,
                    trackId: trackId,
                    progressMs: progressMs,
                    isSynced: false
                )
            )
        }
        save()
    }

    func upsertLastPlayedRemote(
        trackId: String,
        lastPlayedAt: Date,
        progressMs: Int64
    ) {
        let key = ownerKey
        var descriptor = FetchDescriptor<UserTrackLastPlayed>(
            predicate: #Predicate { $0.ownerKey == key && $0.trackId == trackId }
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
                    ownerKey: key,
                    trackId: trackId,
                    lastPlayedAt: lastPlayedAt,
                    progressMs: progressMs,
                    isSynced: true
                )
            )
        }
    }

    func upsertMetadata(_ meta: UserTrackMetadata) {
        if meta.ownerKey.isEmpty {
            meta.ownerKey = ownerKey
        }
        let key = meta.ownerKey
        let trackId = meta.trackId
        var descriptor = FetchDescriptor<UserTrackMetadata>(
            predicate: #Predicate { $0.ownerKey == key && $0.trackId == trackId }
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
        if channel.ownerKey.isEmpty {
            channel.ownerKey = ownerKey
        }
        let key = channel.ownerKey
        let channelId = channel.channelId
        var descriptor = FetchDescriptor<UserSubscribedChannel>(
            predicate: #Predicate { $0.ownerKey == key && $0.channelId == channelId }
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

    func removeSubscribedChannelLocally(channelId: String) {
        guard let existing = subscribedChannel(id: channelId) else { return }
        modelContext.delete(existing)
    }

    func deletePlaylist(_ playlist: LibraryPlaylist) {
        guard playlist.systemType == nil else { return }
        modelContext.delete(playlist)
        save()
    }

    /// Delete by id within the current owner bucket (safe from sheet/action capture).
    @discardableResult
    func deletePlaylist(id playlistId: String) -> Bool {
        let key = ownerKey
        var descriptor = FetchDescriptor<LibraryPlaylist>(
            predicate: #Predicate { $0.ownerKey == key && $0.playlistId == playlistId }
        )
        descriptor.fetchLimit = 1
        guard let playlist = try? modelContext.fetch(descriptor).first,
              playlist.systemType == nil
        else { return false }
        modelContext.delete(playlist)
        save()
        return true
    }

    func renamePlaylist(_ playlist: LibraryPlaylist, name: String) {
        guard playlist.systemType == nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlist.name = trimmed
        playlist.updatedAt = .now
        playlist.isSynced = false
        save()
    }

    func updatePlaylistCover(_ playlist: LibraryPlaylist, coverUrlOrPath: String?) {
        guard playlist.systemType == nil else { return }
        let previous = playlist.coverUrlOrPath
        if let previous, previous != coverUrlOrPath {
            PlaylistCoverStorage.deleteIfLocal(previous)
        }
        playlist.coverUrlOrPath = coverUrlOrPath
        playlist.updatedAt = .now
        playlist.isSynced = false
        save()
    }

    func setPlaylistCoverImage(_ playlist: LibraryPlaylist, image: UIImage) {
        guard playlist.systemType == nil else { return }
        guard let token = PlaylistCoverStorage.save(image, playlistId: playlist.playlistId) else { return }
        updatePlaylistCover(playlist, coverUrlOrPath: token)
    }

    func reorderPlaylistTracks(_ playlist: LibraryPlaylist, orderedTrackIds: [String]) {
        let byId = Dictionary(
            uniqueKeysWithValues: playlist.entries.compactMap { entry -> (String, LibraryPlaylistEntry)? in
                guard let id = entry.track?.trackId else { return nil }
                return (id, entry)
            }
        )
        for (index, trackId) in orderedTrackIds.enumerated() {
            guard let entry = byId[trackId] else { continue }
            entry.position = index
            entry.isSynced = false
        }
        playlist.updatedAt = .now
        playlist.isSynced = false
        save()
    }

    func removeLastPlayed(trackIds: [String]) {
        guard !trackIds.isEmpty else { return }
        let key = ownerKey
        for id in trackIds {
            var descriptor = FetchDescriptor<UserTrackLastPlayed>(
                predicate: #Predicate { $0.ownerKey == key && $0.trackId == id }
            )
            descriptor.fetchLimit = 1
            if let row = try? modelContext.fetch(descriptor).first {
                modelContext.delete(row)
            }
        }
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
        let key = ownerKey
        var descriptor = FetchDescriptor<NotInterestedItem>(
            predicate: #Predicate { $0.ownerKey == key && $0.videoId == videoId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first != nil
    }

    @discardableResult
    func toggleNotInterested(videoId: String) -> Bool {
        let key = ownerKey
        var descriptor = FetchDescriptor<NotInterestedItem>(
            predicate: #Predicate { $0.ownerKey == key && $0.videoId == videoId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            save()
            return false
        }
        modelContext.insert(NotInterestedItem(ownerKey: key, videoId: videoId))
        save()
        return true
    }

    func removeNotInterested(videoId: String) {
        let key = ownerKey
        var descriptor = FetchDescriptor<NotInterestedItem>(
            predicate: #Predicate { $0.ownerKey == key && $0.videoId == videoId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            save()
        }
    }

    // MARK: - Metadata

    func metadata(for trackId: String) -> UserTrackMetadata? {
        let key = ownerKey
        var descriptor = FetchDescriptor<UserTrackMetadata>(
            predicate: #Predicate { $0.ownerKey == key && $0.trackId == trackId }
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
                ownerKey: ownerKey,
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

    func displayItem(for item: VideoItem) -> VideoItem {
        guard let meta = metadata(for: item.videoId) else { return item }
        return applyMetadata(meta, to: item)
    }

    private func applyMetadata(_ meta: UserTrackMetadata, to item: VideoItem) -> VideoItem {
        VideoItem(
            videoId: item.videoId,
            title: meta.customTitle ?? item.title,
            channelName: meta.customArtistName ?? item.channelName,
            subtitle: item.subtitle,
            thumbnailURL: TrackThumbnailStorage.resolveURL(meta.customThumbnailUrl) ?? item.thumbnailURL,
            channelAvatarURL: item.channelAvatarURL,
            durationText: item.durationText,
            viewCountText: item.viewCountText,
            publishedTimeText: item.publishedTimeText
        )
    }

    func filterNotInterested(_ items: [VideoItem]) -> [VideoItem] {
        guard !items.isEmpty else { return [] }
        let key = ownerKey
        let blocked = Set(
            ((try? modelContext.fetch(
                FetchDescriptor<NotInterestedItem>(predicate: #Predicate { $0.ownerKey == key })
            )) ?? []).map(\.videoId)
        )
        let metaById = Dictionary(
            uniqueKeysWithValues: allMetadata().map { ($0.trackId, $0) }
        )
        return items.compactMap { item in
            guard !blocked.contains(item.videoId) else { return nil }
            if let meta = metaById[item.videoId] {
                return applyMetadata(meta, to: item)
            }
            return item
        }
    }

    func save() {
        try? modelContext.save()
        onMutate?()
    }

    func saveLocalOnly() {
        try? modelContext.save()
    }

    /// Remove all user-scoped rows for `key`. Does not delete global `LibraryTrack` rows.
    func clearOwnerBucket(_ key: String) {
        let previousMutate = onMutate
        onMutate = nil
        defer { onMutate = previousMutate }

        for playlist in fetchPlaylists(ownerKey: key) {
            if let cover = playlist.coverUrlOrPath {
                PlaylistCoverStorage.deleteIfLocal(cover)
            }
            modelContext.delete(playlist)
        }

        let history = (try? modelContext.fetch(
            FetchDescriptor<PlaybackHistoryItem>(predicate: #Predicate { $0.ownerKey == key })
        )) ?? []
        for row in history { modelContext.delete(row) }

        let lastPlayed = (try? modelContext.fetch(
            FetchDescriptor<UserTrackLastPlayed>(predicate: #Predicate { $0.ownerKey == key })
        )) ?? []
        for row in lastPlayed { modelContext.delete(row) }

        let metadata = (try? modelContext.fetch(
            FetchDescriptor<UserTrackMetadata>(predicate: #Predicate { $0.ownerKey == key })
        )) ?? []
        for row in metadata { modelContext.delete(row) }

        let channels = (try? modelContext.fetch(
            FetchDescriptor<UserSubscribedChannel>(predicate: #Predicate { $0.ownerKey == key })
        )) ?? []
        for row in channels { modelContext.delete(row) }

        let notInterested = (try? modelContext.fetch(
            FetchDescriptor<NotInterestedItem>(predicate: #Predicate { $0.ownerKey == key })
        )) ?? []
        for row in notInterested { modelContext.delete(row) }

        try? modelContext.save()
    }

    private func fetchPlaylist(systemType: String) -> LibraryPlaylist? {
        let key = ownerKey
        var descriptor = FetchDescriptor<LibraryPlaylist>(
            predicate: #Predicate { $0.ownerKey == key && $0.systemType == systemType }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func migrateLegacyPlaylistCovers() {
        let key = ownerKey
        let all = (try? modelContext.fetch(
            FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.ownerKey == key })
        )) ?? []
        var changed = false
        for playlist in all where playlist.systemType == nil {
            let before = playlist.coverUrlOrPath
            PlaylistCoverStorage.migrateLegacyIfNeeded(playlist)
            if playlist.coverUrlOrPath != before { changed = true }
        }
        if changed {
            try? modelContext.save()
        }
    }
}

/// Local playlist cover files under Application Support.
enum PlaylistCoverStorage {
    private static let tokenPrefix = "localcover:"

    static func token(for playlistId: String) -> String {
        "\(tokenPrefix)\(playlistId)"
    }

    static func resolveURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if let playlistId = playlistId(fromLocalToken: raw) {
            return existingFileURL(for: playlistId)
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            if FileManager.default.fileExists(atPath: url.path) { return url }
            return existingFileURL(for: url.deletingPathExtension().lastPathComponent)
        }
        if raw.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: raw) {
                return URL(fileURLWithPath: raw)
            }
            let name = URL(fileURLWithPath: raw).deletingPathExtension().lastPathComponent
            return existingFileURL(for: name)
        }
        return nil
    }

    static func isLocalPath(_ raw: String) -> Bool {
        raw.hasPrefix(tokenPrefix) || raw.hasPrefix("/") || raw.hasPrefix("file://")
    }

    static func syncableCover(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        return nil
    }

    static func save(_ image: UIImage, playlistId: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return nil }
        let dir = coversDirectory()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = fileURL(for: playlistId)
            try data.write(to: file, options: .atomic)
            return token(for: playlistId)
        } catch {
            return nil
        }
    }

    static func deleteIfLocal(_ raw: String) {
        guard isLocalPath(raw) else { return }
        if let playlistId = playlistId(fromLocalToken: raw) {
            try? FileManager.default.removeItem(at: fileURL(for: playlistId))
            return
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            try? FileManager.default.removeItem(at: url)
            return
        }
        if raw.hasPrefix("/") {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: raw))
        }
    }

    static func migrateLegacyIfNeeded(_ playlist: LibraryPlaylist) {
        guard let raw = playlist.coverUrlOrPath, !raw.isEmpty else { return }
        if playlistId(fromLocalToken: raw) != nil { return }
        guard isLocalPath(raw) else { return }
        let playlistId = playlist.playlistId
        let destination = fileURL(for: playlistId)
        if let url = resolveURL(raw), url.path != destination.path,
           FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: coversDirectory(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.copyItem(at: url, to: destination)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            playlist.coverUrlOrPath = token(for: playlistId)
        }
    }

    private static func playlistId(fromLocalToken raw: String) -> String? {
        guard raw.hasPrefix(tokenPrefix) else { return nil }
        let id = String(raw.dropFirst(tokenPrefix.count))
        return id.isEmpty ? nil : id
    }

    private static func fileURL(for playlistId: String) -> URL {
        coversDirectory().appendingPathComponent("\(playlistId).jpg")
    }

    private static func existingFileURL(for playlistId: String) -> URL? {
        guard !playlistId.isEmpty else { return nil }
        let file = fileURL(for: playlistId)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private static func coversDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("playlist_covers", isDirectory: true)
    }
}

enum ChannelID {
    static func isBrowsable(_ channelId: String?) -> Bool {
        guard let channelId else { return false }
        let trimmed = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("name:")
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
