import Foundation
import Supabase

@MainActor
final class LibrarySyncService {
    private let auth: AuthService
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoFallback = ISO8601DateFormatter()

    init(auth: AuthService) {
        self.auth = auth
    }

    func syncBidirectional(store: LibraryStore) async {
        let previousMutate = store.onMutate
        store.onMutate = nil
        defer { store.onMutate = previousMutate }

        // Pull first so Library can refresh quickly; push only dirty rows after.
        await pullRemote(into: store)
        store.saveLocalOnly()
        await pushDirty(store: store)
        store.saveLocalOnly()
    }

    /// Guest → first login: re-home guest bucket into the user bucket, then sync that user.
    func mergeGuestIntoUserAndSync(
        store: LibraryStore,
        guestKey: String,
        userKey: String
    ) async {
        let previousMutate = store.onMutate
        store.onMutate = nil
        defer { store.onMutate = previousMutate }

        store.mergeGuestIntoUser(guestKey: guestKey, userKey: userKey)
        store.setOwnerKey(userKey)
        await syncBidirectional(store: store)
    }

    func deleteSubscribedChannel(channelId: String) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }
        _ = try? await client
            .from("user_subscribed_channels")
            .delete()
            .eq("user_id", value: userId)
            .eq("channel_id", value: channelId)
            .execute()
    }

    /// Incremental upload used by `onMutate` and auth sync — skips already-synced rows.
    func pushAll(store: LibraryStore) async {
        await pushDirty(store: store)
        // Persist sync flags without re-entering onMutate.
        store.saveLocalOnly()
    }

    private func pushDirty(store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }

        var pushedTrackIds = Set<String>()

        for playlist in store.allPlaylists() {
            let dirtyEntries = playlist.entries.filter { !$0.isSynced }
            let needsPlaylistUpsert = !playlist.isSynced
            guard needsPlaylistUpsert || !dirtyEntries.isEmpty else { continue }

            var playlistSynced = true
            if needsPlaylistUpsert {
                playlistSynced = await upsertPlaylist(client: client, userId: userId, playlist: playlist)
            }

            for entry in dirtyEntries {
                guard let track = entry.track else { continue }
                if !pushedTrackIds.contains(track.trackId) {
                    await upsertTrack(client: client, track: track)
                    pushedTrackIds.insert(track.trackId)
                }
                await upsertPlaylistTrack(
                    client: client,
                    playlistId: playlist.playlistId,
                    trackId: track.trackId,
                    position: entry.position,
                    createdAt: entry.createdAt
                )
                entry.isSynced = true
            }

            if playlistSynced {
                playlist.isSynced = true
            }
        }

        for item in store.playbackHistory(limit: 100) where !item.isSynced {
            if let track = store.track(id: item.trackId), !pushedTrackIds.contains(track.trackId) {
                await upsertTrack(client: client, track: track)
                pushedTrackIds.insert(track.trackId)
            }
            await insertPlaybackHistory(client: client, userId: userId, item: item)
            item.isSynced = true
        }

        for row in store.lastPlayed(limit: 100) where !row.isSynced {
            if let track = store.track(id: row.trackId), !pushedTrackIds.contains(track.trackId) {
                await upsertTrack(client: client, track: track)
                pushedTrackIds.insert(track.trackId)
            }
            await upsertLastPlayed(client: client, userId: userId, row: row)
            row.isSynced = true
        }

        for meta in store.allMetadata() where !meta.isSynced {
            await upsertMetadata(client: client, userId: userId, meta: meta)
            meta.isSynced = true
        }

        for channel in store.allSubscribedChannels() where !channel.isSynced {
            await upsertSubscribedChannel(client: client, userId: userId, channel: channel)
            channel.isSynced = true
        }
    }

    private func pullRemote(into store: LibraryStore) async {
        guard auth.supabaseClient() != nil, auth.userId != nil else { return }

        // Playlists first (owns the heavy track fetch); then lighter tables in parallel.
        await pullPlaylists(into: store)
        async let lastPlayedDone: Void = pullLastPlayed(into: store)
        async let metadataDone: Void = pullMetadata(into: store)
        async let channelsDone: Void = pullSubscribedChannels(into: store)
        _ = await (lastPlayedDone, metadataDone, channelsDone)
    }

    func pullPlaylists(into store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }
        struct RemotePlaylist: Decodable {
            let playlist_id: String
            let name: String
            let cover_url_or_path: String?
            let description: String?
            let system_type: String?
            let is_pinned: Bool?
            let updated_at: String?
        }
        do {
            let rows: [RemotePlaylist] = try await client
                .from("playlists")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            var targets: [(remoteId: String, local: LibraryPlaylist)] = []
            targets.reserveCapacity(rows.count)

            for row in rows {
                if let system = row.system_type {
                    guard let local = store.allPlaylists().first(where: { $0.systemType == system }) else {
                        continue
                    }
                    local.name = row.name
                    Self.applyRemoteCover(row.cover_url_or_path, to: local)
                    local.descriptionText = row.description
                    local.isPinned = row.is_pinned ?? local.isPinned
                    local.isSynced = true
                    targets.append((row.playlist_id, local))
                    continue
                }
                if let existing = store.allPlaylists().first(where: { $0.playlistId == row.playlist_id }) {
                    existing.name = row.name
                    Self.applyRemoteCover(row.cover_url_or_path, to: existing)
                    existing.descriptionText = row.description
                    existing.isPinned = row.is_pinned ?? existing.isPinned
                    existing.isSynced = true
                    targets.append((row.playlist_id, existing))
                    continue
                }
                let playlist = LibraryPlaylist(
                    ownerKey: store.ownerKey,
                    playlistId: row.playlist_id,
                    name: row.name,
                    coverUrlOrPath: row.cover_url_or_path,
                    descriptionText: row.description,
                    systemType: nil,
                    isPinned: row.is_pinned ?? false,
                    isSynced: true
                )
                store.insertImportedPlaylist(playlist, persist: false)
                targets.append((row.playlist_id, playlist))
            }

            await pullTracksBatched(client: client, store: store, targets: targets)
        } catch {
            // Soft-fail
        }
    }

    private func pullLastPlayed(into store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }
        struct RemoteLastPlayed: Decodable {
            let track_id: String
            let last_played_at: String
            let progress_ms: Int64?
        }
        do {
            let rows: [RemoteLastPlayed] = try await client
                .from("user_track_last_played")
                .select()
                .eq("user_id", value: userId)
                .order("last_played_at", ascending: false)
                .limit(100)
                .execute()
                .value
            let trackIds = rows.map(\.track_id)
            await pullTracksByIds(client: client, store: store, trackIds: trackIds)
            for row in rows {
                store.upsertLastPlayedRemote(
                    trackId: row.track_id,
                    lastPlayedAt: parseDate(row.last_played_at) ?? .now,
                    progressMs: row.progress_ms ?? 0
                )
            }
        } catch {}
    }

    private func pullMetadata(into store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }
        struct RemoteMeta: Decodable {
            let track_id: String
            let custom_title: String?
            let custom_artist_name: String?
            let custom_thumbnail_url: String?
            let custom_album: String?
            let custom_year: String?
            let updated_at: String
        }
        do {
            let rows: [RemoteMeta] = try await client
                .from("user_track_metadata")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value
            for row in rows {
                store.upsertMetadata(
                    UserTrackMetadata(
                        ownerKey: store.ownerKey,
                        trackId: row.track_id,
                        customTitle: row.custom_title,
                        customArtistName: row.custom_artist_name,
                        customThumbnailUrl: row.custom_thumbnail_url,
                        customAlbum: row.custom_album,
                        customYear: row.custom_year,
                        updatedAt: parseDate(row.updated_at) ?? .now,
                        isSynced: true
                    )
                )
            }
        } catch {}
    }

    private func pullSubscribedChannels(into store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }
        struct RemoteChannel: Decodable {
            let channel_id: String
            let title: String
            let handle: String?
            let avatar_url: String?
            let subscriber_count_text: String?
            let description: String?
            let subscribed_at: String
        }
        do {
            let rows: [RemoteChannel] = try await client
                .from("user_subscribed_channels")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value
            let remoteIds = Set(rows.map(\.channel_id))
            for local in store.allSubscribedChannels() where !remoteIds.contains(local.channelId) {
                store.removeSubscribedChannelLocally(channelId: local.channelId)
            }
            for row in rows {
                store.upsertSubscribedChannel(
                    UserSubscribedChannel(
                        ownerKey: store.ownerKey,
                        channelId: row.channel_id,
                        title: row.title,
                        handle: row.handle,
                        avatarUrl: row.avatar_url,
                        subscriberCountText: row.subscriber_count_text,
                        descriptionText: row.description,
                        subscribedAt: parseDate(row.subscribed_at) ?? .now,
                        isSynced: true
                    )
                )
            }
        } catch {}
    }

    private func pullTracksBatched(
        client: SupabaseClient,
        store: LibraryStore,
        targets: [(remoteId: String, local: LibraryPlaylist)]
    ) async {
        guard !targets.isEmpty else { return }
        struct RemoteTrackRef: Decodable {
            let playlist_id: String
            let track_id: String
            let position: Int
        }

        let remoteIds = targets.map(\.remoteId)
        var refs: [RemoteTrackRef] = []
        for chunk in remoteIds.chunked(into: 80) {
            do {
                let part: [RemoteTrackRef] = try await client
                    .from("playlist_track_cross_ref")
                    .select()
                    .in("playlist_id", values: chunk)
                    .execute()
                    .value
                refs.append(contentsOf: part)
            } catch {}
        }

        let allTrackIds = Array(Set(refs.map(\.track_id)))
        await pullTracksByIds(client: client, store: store, trackIds: allTrackIds)

        let localByRemoteId = Dictionary(uniqueKeysWithValues: targets.map { ($0.remoteId, $0.local) })
        let refsByPlaylist = Dictionary(grouping: refs, by: \.playlist_id)

        for (remoteId, playlist) in localByRemoteId {
            let playlistRefs = (refsByPlaylist[remoteId] ?? []).sorted { $0.position < $1.position }
            for ref in playlistRefs {
                guard let track = store.track(id: ref.track_id) else { continue }
                store.add(
                    item: track.asVideoItem,
                    to: playlist,
                    persist: false,
                    markDirty: false
                )
            }
        }
    }

    private func pullTracksByIds(
        client: SupabaseClient,
        store: LibraryStore,
        trackIds: [String]
    ) async {
        guard !trackIds.isEmpty else { return }
        struct RemoteTrack: Decodable {
            let track_id: String
            let title: String
            let duration_seconds: Int?
            let duration_text: String?
            let thumbnail_low: String?
            let thumbnail_medium: String?
            let thumbnail_high: String?
            let view_count: Int64?
            let view_count_text: String?
            let published_text: String?
            let primary_artist_id: String?
            let primary_artist_name: String?
        }
        for chunk in trackIds.chunked(into: 100) {
            do {
                let tracks: [RemoteTrack] = try await client
                    .from("tracks")
                    .select()
                    .in("track_id", values: chunk)
                    .execute()
                    .value
                for t in tracks {
                    store.upsertTrackEntity(
                        LibraryTrack(
                            trackId: t.track_id,
                            title: t.title,
                            durationSeconds: t.duration_seconds ?? 0,
                            durationText: t.duration_text,
                            thumbnailLow: t.thumbnail_low,
                            thumbnailMedium: t.thumbnail_medium,
                            thumbnailHigh: t.thumbnail_high,
                            viewCount: t.view_count ?? 0,
                            viewCountText: t.view_count_text,
                            publishedText: t.published_text,
                            primaryArtistId: t.primary_artist_id,
                            primaryArtistName: t.primary_artist_name
                        )
                    )
                }
            } catch {}
        }
    }

    /// Upserts playlist row. Returns `false` if a local cover still failed to upload (keep dirty).
    @discardableResult
    private func upsertPlaylist(
        client: SupabaseClient,
        userId: String,
        playlist: LibraryPlaylist
    ) async -> Bool {
        struct Payload: Encodable {
            let playlist_id: String
            let user_id: String
            let name: String
            let cover_url_or_path: String?
            let description: String?
            let system_type: String?
            let is_pinned: Bool
            let updated_at: String
        }
        struct PayloadWithoutCover: Encodable {
            let playlist_id: String
            let user_id: String
            let name: String
            let description: String?
            let system_type: String?
            let is_pinned: Bool
            let updated_at: String
        }

        let raw = playlist.coverUrlOrPath
        if let syncable = PlaylistCoverStorage.syncableCover(raw) {
            _ = try? await client.from("playlists").upsert(
                Payload(
                    playlist_id: playlist.playlistId,
                    user_id: userId,
                    name: playlist.name,
                    cover_url_or_path: syncable,
                    description: playlist.descriptionText,
                    system_type: playlist.systemType,
                    is_pinned: playlist.isPinned,
                    updated_at: isoString(from: playlist.updatedAt)
                )
            ).execute()
            return true
        }

        if raw == nil {
            await removeRemoteCover(client: client, userId: userId, playlistId: playlist.playlistId)
            _ = try? await client.from("playlists").upsert(
                Payload(
                    playlist_id: playlist.playlistId,
                    user_id: userId,
                    name: playlist.name,
                    cover_url_or_path: nil,
                    description: playlist.descriptionText,
                    system_type: playlist.systemType,
                    is_pinned: playlist.isPinned,
                    updated_at: isoString(from: playlist.updatedAt)
                )
            ).execute()
            return true
        }

        // Local file / token — upload to Storage first.
        if let uploaded = await uploadLocalCover(client: client, userId: userId, playlist: playlist) {
            playlist.coverUrlOrPath = uploaded
            _ = try? await client.from("playlists").upsert(
                Payload(
                    playlist_id: playlist.playlistId,
                    user_id: userId,
                    name: playlist.name,
                    cover_url_or_path: uploaded,
                    description: playlist.descriptionText,
                    system_type: playlist.systemType,
                    is_pinned: playlist.isPinned,
                    updated_at: isoString(from: playlist.updatedAt)
                )
            ).execute()
            return true
        }

        // Upload failed: update other fields without wiping an existing remote cover.
        struct ExistingRow: Decodable { let playlist_id: String }
        let existing: [ExistingRow] = (try? await client
            .from("playlists")
            .select("playlist_id")
            .eq("user_id", value: userId)
            .eq("playlist_id", value: playlist.playlistId)
            .execute()
            .value) ?? []
        if existing.isEmpty {
            _ = try? await client.from("playlists").upsert(
                Payload(
                    playlist_id: playlist.playlistId,
                    user_id: userId,
                    name: playlist.name,
                    cover_url_or_path: nil,
                    description: playlist.descriptionText,
                    system_type: playlist.systemType,
                    is_pinned: playlist.isPinned,
                    updated_at: isoString(from: playlist.updatedAt)
                )
            ).execute()
        } else {
            _ = try? await client
                .from("playlists")
                .update(
                    PayloadWithoutCover(
                        playlist_id: playlist.playlistId,
                        user_id: userId,
                        name: playlist.name,
                        description: playlist.descriptionText,
                        system_type: playlist.systemType,
                        is_pinned: playlist.isPinned,
                        updated_at: isoString(from: playlist.updatedAt)
                    )
                )
                .eq("user_id", value: userId)
                .eq("playlist_id", value: playlist.playlistId)
                .execute()
        }
        return false
    }

    private func uploadLocalCover(
        client: SupabaseClient,
        userId: String,
        playlist: LibraryPlaylist
    ) async -> String? {
        guard let raw = playlist.coverUrlOrPath,
              PlaylistCoverStorage.isLocalPath(raw),
              let fileURL = PlaylistCoverStorage.resolveURL(raw),
              let data = try? Data(contentsOf: fileURL),
              !data.isEmpty
        else {
            return nil
        }

        let objectPath = Self.remoteCoverObjectPath(userId: userId, playlistId: playlist.playlistId)
        do {
            try await client.storage
                .from(Self.playlistCoversBucket)
                .upload(
                    objectPath,
                    data: data,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )
            let publicURL = try client.storage
                .from(Self.playlistCoversBucket)
                .getPublicURL(path: objectPath)
            return publicURL.absoluteString
        } catch {
            return nil
        }
    }

    private func removeRemoteCover(
        client: SupabaseClient,
        userId: String,
        playlistId: String
    ) async {
        let objectPath = Self.remoteCoverObjectPath(userId: userId, playlistId: playlistId)
        _ = try? await client.storage
            .from(Self.playlistCoversBucket)
            .remove(paths: [objectPath])
    }

    private static let playlistCoversBucket = "playlist-covers"

    private static func remoteCoverObjectPath(userId: String, playlistId: String) -> String {
        "\(userId.lowercased())/\(playlistId).jpg"
    }

    private func upsertTrack(client: SupabaseClient, track: LibraryTrack) async {
        struct Payload: Encodable {
            let track_id: String
            let title: String
            let duration_seconds: Int
            let duration_text: String?
            let thumbnail_low: String?
            let thumbnail_medium: String?
            let thumbnail_high: String?
            let view_count: Int64
            let view_count_text: String?
            let published_text: String?
            let primary_artist_id: String?
            let primary_artist_name: String?
        }
        _ = try? await client.from("tracks").upsert(
            Payload(
                track_id: track.trackId,
                title: track.title,
                duration_seconds: track.durationSeconds,
                duration_text: track.durationText,
                thumbnail_low: track.thumbnailLow,
                thumbnail_medium: track.thumbnailMedium,
                thumbnail_high: track.thumbnailHigh,
                view_count: track.viewCount,
                view_count_text: track.viewCountText,
                published_text: track.publishedText,
                primary_artist_id: track.primaryArtistId,
                primary_artist_name: track.primaryArtistName
            )
        ).execute()
    }

    private func upsertPlaylistTrack(
        client: SupabaseClient,
        playlistId: String,
        trackId: String,
        position: Int,
        createdAt: Date
    ) async {
        struct Payload: Encodable {
            let playlist_id: String
            let track_id: String
            let position: Int
            let created_at: String
        }
        _ = try? await client.from("playlist_track_cross_ref").upsert(
            Payload(
                playlist_id: playlistId,
                track_id: trackId,
                position: position,
                created_at: isoString(from: createdAt)
            )
        ).execute()
    }

    private func insertPlaybackHistory(
        client: SupabaseClient,
        userId: String,
        item: PlaybackHistoryItem
    ) async {
        struct Payload: Encodable {
            let history_id: String
            let user_id: String
            let track_id: String
            let played_at: String
            let progress_ms: Int64
        }
        _ = try? await client.from("playback_history").insert(
            Payload(
                history_id: item.historyId,
                user_id: userId,
                track_id: item.trackId,
                played_at: isoString(from: item.playedAt),
                progress_ms: item.progressMs
            )
        ).execute()
    }

    private func upsertLastPlayed(
        client: SupabaseClient,
        userId: String,
        row: UserTrackLastPlayed
    ) async {
        struct Payload: Encodable {
            let user_id: String
            let track_id: String
            let last_played_at: String
            let progress_ms: Int64
        }
        _ = try? await client.from("user_track_last_played").upsert(
            Payload(
                user_id: userId,
                track_id: row.trackId,
                last_played_at: isoString(from: row.lastPlayedAt),
                progress_ms: row.progressMs
            )
        ).execute()
    }

    private func upsertMetadata(
        client: SupabaseClient,
        userId: String,
        meta: UserTrackMetadata
    ) async {
        struct Payload: Encodable {
            let user_id: String
            let track_id: String
            let custom_title: String?
            let custom_artist_name: String?
            let custom_thumbnail_url: String?
            let custom_album: String?
            let custom_year: String?
            let updated_at: String
        }
        _ = try? await client.from("user_track_metadata").upsert(
            Payload(
                user_id: userId,
                track_id: meta.trackId,
                custom_title: meta.customTitle,
                custom_artist_name: meta.customArtistName,
                custom_thumbnail_url: meta.customThumbnailUrl,
                custom_album: meta.customAlbum,
                custom_year: meta.customYear,
                updated_at: isoString(from: meta.updatedAt)
            )
        ).execute()
    }

    private func upsertSubscribedChannel(
        client: SupabaseClient,
        userId: String,
        channel: UserSubscribedChannel
    ) async {
        struct Payload: Encodable {
            let user_id: String
            let channel_id: String
            let title: String
            let handle: String?
            let avatar_url: String?
            let subscriber_count_text: String?
            let description: String?
            let subscribed_at: String
        }
        _ = try? await client.from("user_subscribed_channels").upsert(
            Payload(
                user_id: userId,
                channel_id: channel.channelId,
                title: channel.title,
                handle: channel.handle,
                avatar_url: channel.avatarUrl,
                subscriber_count_text: channel.subscriberCountText,
                description: channel.descriptionText,
                subscribed_at: isoString(from: channel.subscribedAt)
            )
        ).execute()
    }

    private func isoString(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private func parseDate(_ value: String) -> Date? {
        isoFormatter.date(from: value) ?? isoFallback.date(from: value)
    }

    /// Keep device-local cover files when remote cover is empty.
    private static func applyRemoteCover(_ remote: String?, to playlist: LibraryPlaylist) {
        if let remote, !remote.isEmpty {
            playlist.coverUrlOrPath = remote
            return
        }
        if let local = playlist.coverUrlOrPath, PlaylistCoverStorage.isLocalPath(local) {
            return
        }
        playlist.coverUrlOrPath = remote
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<next]))
            index = next
        }
        return result
    }
}
