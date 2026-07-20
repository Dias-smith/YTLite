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

        let t0 = SyncProbe.now()
        SyncProbe.logTrace("bidirectional.begin")

        // Pull first so Library can refresh quickly; push only dirty rows after.
        await pullRemote(into: store)

        let tSave1 = SyncProbe.now()
        store.saveLocalOnly()
        SyncProbe.logTrace("save.local", "phase=after_pull ms=\(SyncProbe.ms(since: tSave1))")

        await pushDirty(store: store)

        let tSave2 = SyncProbe.now()
        store.saveLocalOnly()
        SyncProbe.logTrace("save.local", "phase=after_push ms=\(SyncProbe.ms(since: tSave2))")

        SyncProbe.logTrace("bidirectional.end", "total_ms=\(SyncProbe.ms(since: t0))")
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

        let t0 = SyncProbe.now()
        SyncProbe.logTrace(
            "merge.begin",
            "guest=\(guestKey.prefix(12)) user=\(userKey.prefix(12))"
        )
        store.mergeGuestIntoUser(guestKey: guestKey, userKey: userKey)
        store.setOwnerKey(userKey)
        SyncProbe.logTrace("merge.end", "ms=\(SyncProbe.ms(since: t0))")
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

        let t0 = SyncProbe.now()

        // Collect dirty work first — only these rows are pushed.
        var playlistsToUpsert: [LibraryPlaylist] = []
        var playlistsToMarkSynced: [LibraryPlaylist] = []
        var dirtyEntries: [(playlistId: String, entry: LibraryPlaylistEntry)] = []
        var tracksById: [String: LibraryTrack] = [:]

        for playlist in store.allPlaylists() {
            let entries = playlist.entries.filter { !$0.isSynced }
            let needsPlaylistUpsert = !playlist.isSynced
            guard needsPlaylistUpsert || !entries.isEmpty else { continue }

            playlistsToMarkSynced.append(playlist)
            if needsPlaylistUpsert {
                playlistsToUpsert.append(playlist)
            }
            for entry in entries {
                guard let track = entry.track else { continue }
                dirtyEntries.append((playlist.playlistId, entry))
                tracksById[track.trackId] = track
            }
        }

        let dirtyHistory = store.playbackHistory(limit: 100).filter { !$0.isSynced }
        let dirtyLastPlayed = store.lastPlayed(limit: 100).filter { !$0.isSynced }
        let dirtyMeta = store.allMetadata().filter { !$0.isSynced }
        let dirtyChannels = store.allSubscribedChannels().filter { !$0.isSynced }

        for item in dirtyHistory {
            if let track = store.track(id: item.trackId) {
                tracksById[track.trackId] = track
            }
        }
        for row in dirtyLastPlayed {
            if let track = store.track(id: row.trackId) {
                tracksById[track.trackId] = track
            }
        }

        SyncProbe.logTrace(
            "push.begin",
            "dirty playlist=\(playlistsToUpsert.count) entry=\(dirtyEntries.count) history=\(dirtyHistory.count) lastPlayed=\(dirtyLastPlayed.count) meta=\(dirtyMeta.count) channel=\(dirtyChannels.count)"
        )

        var playlistUpsertN = 0
        var playlistUpsertMs = 0
        var trackUpsertN = 0
        var trackUpsertMs = 0
        var entryUpsertN = 0
        var entryUpsertMs = 0
        var historyMs = 0
        var lastPlayedMs = 0
        var metaMs = 0
        var channelMs = 0

        // Playlists stay per-row (cover upload / local-path handling).
        var playlistUpsertFailed = Set<String>()
        for playlist in playlistsToUpsert {
            let tP = SyncProbe.now()
            let ok = await upsertPlaylist(client: client, userId: userId, playlist: playlist)
            let pMs = SyncProbe.ms(since: tP)
            playlistUpsertN += 1
            playlistUpsertMs += pMs
            SyncProbe.logTrace("push.playlist", "ms=\(pMs) id=\(playlist.playlistId.prefix(8)) ok=\(ok ? 1 : 0)")
            if !ok {
                playlistUpsertFailed.insert(playlist.playlistId)
            }
        }

        // Batch tracks then cross-refs (FK: tracks must exist before entries).
        let tracks = Array(tracksById.values)
        if !tracks.isEmpty {
            let tT = SyncProbe.now()
            await upsertTracks(client: client, tracks: tracks)
            trackUpsertN = tracks.count
            trackUpsertMs = SyncProbe.ms(since: tT)
            SyncProbe.logTrace("push.tracks_batch", "n=\(trackUpsertN) ms=\(trackUpsertMs)")
        }

        if !dirtyEntries.isEmpty {
            let tE = SyncProbe.now()
            let entryRows: [(playlistId: String, trackId: String, position: Int, createdAt: Date)] = dirtyEntries.compactMap { item in
                guard let trackId = item.entry.track?.trackId else { return nil }
                return (
                    playlistId: item.playlistId,
                    trackId: trackId,
                    position: item.entry.position,
                    createdAt: item.entry.createdAt
                )
            }
            await upsertPlaylistTracks(client: client, rows: entryRows)
            entryUpsertN = entryRows.count
            entryUpsertMs = SyncProbe.ms(since: tE)
            SyncProbe.logTrace("push.entries_batch", "n=\(entryUpsertN) ms=\(entryUpsertMs)")
            for item in dirtyEntries {
                item.entry.isSynced = true
            }
        }

        for playlist in playlistsToMarkSynced where !playlistUpsertFailed.contains(playlist.playlistId) {
            playlist.isSynced = true
        }

        for item in dirtyHistory {
            let tH = SyncProbe.now()
            await insertPlaybackHistory(client: client, userId: userId, item: item)
            historyMs += SyncProbe.ms(since: tH)
            item.isSynced = true
        }

        for row in dirtyLastPlayed {
            let tL = SyncProbe.now()
            await upsertLastPlayed(client: client, userId: userId, row: row)
            lastPlayedMs += SyncProbe.ms(since: tL)
            row.isSynced = true
        }

        for meta in dirtyMeta {
            let tM = SyncProbe.now()
            await upsertMetadata(client: client, userId: userId, meta: meta)
            metaMs += SyncProbe.ms(since: tM)
            meta.isSynced = true
        }

        for channel in dirtyChannels {
            let tC = SyncProbe.now()
            await upsertSubscribedChannel(client: client, userId: userId, channel: channel)
            channelMs += SyncProbe.ms(since: tC)
            channel.isSynced = true
        }

        SyncProbe.logTrace(
            "push.summary",
            "playlists_ms=\(playlistUpsertMs) playlists_n=\(playlistUpsertN) tracks_ms=\(trackUpsertMs) tracks_n=\(trackUpsertN) entries_ms=\(entryUpsertMs) entries_n=\(entryUpsertN) history_ms=\(historyMs) lastPlayed_ms=\(lastPlayedMs) meta_ms=\(metaMs) channel_ms=\(channelMs)"
        )
        SyncProbe.logTrace("push.end", "total_ms=\(SyncProbe.ms(since: t0))")
    }

    private func pullRemote(into store: LibraryStore) async {
        guard auth.supabaseClient() != nil, auth.userId != nil else { return }

        let t0 = SyncProbe.now()
        SyncProbe.logTrace("pull.begin")

        // Playlists first (owns the heavy track fetch); then lighter tables in parallel.
        await pullPlaylists(into: store)
        async let lastPlayedDone: Void = pullLastPlayed(into: store)
        async let metadataDone: Void = pullMetadata(into: store)
        async let channelsDone: Void = pullSubscribedChannels(into: store)
        _ = await (lastPlayedDone, metadataDone, channelsDone)

        SyncProbe.logTrace("pull.end", "total_ms=\(SyncProbe.ms(since: t0))")
    }

    func pullPlaylists(into store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }
        let t0 = SyncProbe.now()
        SyncProbe.logTrace("pull.playlists.begin")
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
            SyncProbe.logTrace(
                "pull.playlists.end",
                "playlists=\(rows.count) targets=\(targets.count) ms=\(SyncProbe.ms(since: t0))"
            )
        } catch {
            // Soft-fail
            SyncProbe.logTrace("pull.playlists.end", "error=1 ms=\(SyncProbe.ms(since: t0))")
        }
    }

    private func pullLastPlayed(into store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }
        let t0 = SyncProbe.now()
        SyncProbe.logTrace("pull.last_played.begin")
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
            SyncProbe.logTrace("pull.last_played.end", "rows=\(rows.count) ms=\(SyncProbe.ms(since: t0))")
        } catch {
            SyncProbe.logTrace("pull.last_played.end", "error=1 ms=\(SyncProbe.ms(since: t0))")
        }
    }

    private func pullMetadata(into store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }
        let t0 = SyncProbe.now()
        SyncProbe.logTrace("pull.metadata.begin")
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
            SyncProbe.logTrace("pull.metadata.end", "rows=\(rows.count) ms=\(SyncProbe.ms(since: t0))")
        } catch {
            SyncProbe.logTrace("pull.metadata.end", "error=1 ms=\(SyncProbe.ms(since: t0))")
        }
    }

    private func pullSubscribedChannels(into store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }
        let t0 = SyncProbe.now()
        SyncProbe.logTrace("pull.channels.begin")
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
            SyncProbe.logTrace("pull.channels.end", "rows=\(rows.count) ms=\(SyncProbe.ms(since: t0))")
        } catch {
            SyncProbe.logTrace("pull.channels.end", "error=1 ms=\(SyncProbe.ms(since: t0))")
        }
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
        var crossRefChunks = 0
        let tRefs = SyncProbe.now()
        for chunk in remoteIds.chunked(into: 80) {
            crossRefChunks += 1
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
        SyncProbe.logTrace(
            "pull.playlists.cross_ref",
            "chunks=\(crossRefChunks) refs=\(refs.count) ms=\(SyncProbe.ms(since: tRefs))"
        )

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
            let tChunk = SyncProbe.now()
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
                SyncProbe.logTrace(
                    "pull.tracks_batch",
                    "chunk_size=\(chunk.count) fetched=\(tracks.count) ms=\(SyncProbe.ms(since: tChunk))"
                )
            } catch {
                SyncProbe.logTrace(
                    "pull.tracks_batch",
                    "chunk_size=\(chunk.count) error=1 ms=\(SyncProbe.ms(since: tChunk))"
                )
            }
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

        let t0 = SyncProbe.now()
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
            SyncProbe.logTrace(
                "push.cover",
                "ms=\(SyncProbe.ms(since: t0)) bytes=\(data.count) id=\(playlist.playlistId.prefix(8)) ok=1"
            )
            return publicURL.absoluteString
        } catch {
            SyncProbe.logTrace(
                "push.cover",
                "ms=\(SyncProbe.ms(since: t0)) bytes=\(data.count) id=\(playlist.playlistId.prefix(8)) ok=0"
            )
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
        await upsertTracks(client: client, tracks: [track])
    }

    private func upsertTracks(client: SupabaseClient, tracks: [LibraryTrack]) async {
        guard !tracks.isEmpty else { return }
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
        for chunk in tracks.chunked(into: 100) {
            let payloads = chunk.map {
                Payload(
                    track_id: $0.trackId,
                    title: $0.title,
                    duration_seconds: $0.durationSeconds,
                    duration_text: $0.durationText,
                    thumbnail_low: $0.thumbnailLow,
                    thumbnail_medium: $0.thumbnailMedium,
                    thumbnail_high: $0.thumbnailHigh,
                    view_count: $0.viewCount,
                    view_count_text: $0.viewCountText,
                    published_text: $0.publishedText,
                    primary_artist_id: $0.primaryArtistId,
                    primary_artist_name: $0.primaryArtistName
                )
            }
            _ = try? await client.from("tracks").upsert(payloads).execute()
        }
    }

    private func upsertPlaylistTrack(
        client: SupabaseClient,
        playlistId: String,
        trackId: String,
        position: Int,
        createdAt: Date
    ) async {
        await upsertPlaylistTracks(
            client: client,
            rows: [(playlistId: playlistId, trackId: trackId, position: position, createdAt: createdAt)]
        )
    }

    private func upsertPlaylistTracks(
        client: SupabaseClient,
        rows: [(playlistId: String, trackId: String, position: Int, createdAt: Date)]
    ) async {
        guard !rows.isEmpty else { return }
        struct Payload: Encodable {
            let playlist_id: String
            let track_id: String
            let position: Int
            let created_at: String
        }
        for chunk in rows.chunked(into: 100) {
            let payloads = chunk.map {
                Payload(
                    playlist_id: $0.playlistId,
                    track_id: $0.trackId,
                    position: $0.position,
                    created_at: isoString(from: $0.createdAt)
                )
            }
            _ = try? await client.from("playlist_track_cross_ref").upsert(payloads).execute()
        }
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
