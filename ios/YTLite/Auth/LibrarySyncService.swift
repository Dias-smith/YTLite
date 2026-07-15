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
        await pushAll(store: store)
        await pullPlaylists(into: store)
        await pullLastPlayed(into: store)
        await pullMetadata(into: store)
        await pullSubscribedChannels(into: store)
        store.save()
    }

    func pushAll(store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }

        for playlist in store.allPlaylists() {
            await upsertPlaylist(client: client, userId: userId, playlist: playlist)
            for entry in playlist.entries {
                guard let track = entry.track else { continue }
                await upsertTrack(client: client, track: track)
                await upsertPlaylistTrack(
                    client: client,
                    playlistId: playlist.playlistId,
                    trackId: track.trackId,
                    position: entry.position,
                    createdAt: entry.createdAt
                )
                entry.isSynced = true
            }
            playlist.isSynced = true
        }

        for item in store.playbackHistory(limit: 100) where !item.isSynced {
            if let track = store.track(id: item.trackId) {
                await upsertTrack(client: client, track: track)
            }
            await insertPlaybackHistory(client: client, userId: userId, item: item)
            item.isSynced = true
        }

        for row in store.lastPlayed(limit: 100) where !row.isSynced {
            if let track = store.track(id: row.trackId) {
                await upsertTrack(client: client, track: track)
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

        store.save()
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
            for row in rows {
                if let system = row.system_type {
                    if let local = store.allPlaylists().first(where: { $0.systemType == system }) {
                        local.name = row.name
                        local.coverUrlOrPath = row.cover_url_or_path
                        local.descriptionText = row.description
                        local.isPinned = row.is_pinned ?? local.isPinned
                        local.isSynced = true
                        await pullTracks(client: client, store: store, remotePlaylistId: row.playlist_id, into: local)
                    }
                    continue
                }
                if let existing = store.allPlaylists().first(where: { $0.playlistId == row.playlist_id }) {
                    existing.name = row.name
                    existing.coverUrlOrPath = row.cover_url_or_path
                    existing.descriptionText = row.description
                    existing.isPinned = row.is_pinned ?? existing.isPinned
                    existing.isSynced = true
                    await pullTracks(client: client, store: store, remotePlaylistId: row.playlist_id, into: existing)
                    continue
                }
                let playlist = LibraryPlaylist(
                    playlistId: row.playlist_id,
                    name: row.name,
                    coverUrlOrPath: row.cover_url_or_path,
                    descriptionText: row.description,
                    systemType: nil,
                    isPinned: row.is_pinned ?? false,
                    isSynced: true
                )
                store.insertImportedPlaylist(playlist)
                await pullTracks(client: client, store: store, remotePlaylistId: row.playlist_id, into: playlist)
            }
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
            for row in rows {
                store.upsertSubscribedChannel(
                    UserSubscribedChannel(
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

    private func pullTracks(
        client: SupabaseClient,
        store: LibraryStore,
        remotePlaylistId: String,
        into playlist: LibraryPlaylist
    ) async {
        struct RemoteTrackRef: Decodable {
            let track_id: String
            let position: Int
        }
        do {
            let refs: [RemoteTrackRef] = try await client
                .from("playlist_track_cross_ref")
                .select()
                .eq("playlist_id", value: remotePlaylistId)
                .execute()
                .value
            let trackIds = refs.map(\.track_id)
            await pullTracksByIds(client: client, store: store, trackIds: trackIds)
            for ref in refs.sorted(by: { $0.position < $1.position }) {
                guard let track = store.track(id: ref.track_id) else { continue }
                store.add(item: track.asVideoItem, to: playlist)
            }
        } catch {}
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
        do {
            let tracks: [RemoteTrack] = try await client
                .from("tracks")
                .select()
                .in("track_id", values: trackIds)
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

    private func upsertPlaylist(client: SupabaseClient, userId: String, playlist: LibraryPlaylist) async {
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
        _ = try? await client.from("playlists").upsert(
            Payload(
                playlist_id: playlist.playlistId,
                user_id: userId,
                name: playlist.name,
                cover_url_or_path: playlist.coverUrlOrPath,
                description: playlist.descriptionText,
                system_type: playlist.systemType,
                is_pinned: playlist.isPinned,
                updated_at: isoString(from: playlist.updatedAt)
            )
        ).execute()
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
}
