import Foundation
import Supabase

@MainActor
final class LibrarySyncService {
    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
    }

    func syncBidirectional(store: LibraryStore) async {
        await pushAll(store: store)
        await pullPlaylists(into: store)
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
                    trackId: track.videoId,
                    position: entry.position
                )
            }
        }
        for item in store.history(limit: 50) {
            await upsertLastPlayed(client: client, userId: userId, item: item)
        }
    }

    func pullPlaylists(into store: LibraryStore) async {
        guard let client = auth.supabaseClient(), let userId = auth.userId else { return }
        struct RemotePlaylist: Decodable {
            let playlist_id: String
            let name: String
            let system_type: String?
            let is_pinned: Bool?
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
                    // Merge remote system playlist tracks into local system playlist.
                    if let local = store.allPlaylists().first(where: { $0.systemType == system }) {
                        await pullTracks(client: client, store: store, remotePlaylistId: row.playlist_id, into: local)
                    }
                    continue
                }
                if let existing = store.allPlaylists().first(where: { $0.playlistId == row.playlist_id }) {
                    await pullTracks(client: client, store: store, remotePlaylistId: row.playlist_id, into: existing)
                    continue
                }
                let playlist = LibraryPlaylist(
                    playlistId: row.playlist_id,
                    name: row.name,
                    systemType: nil,
                    isPinned: row.is_pinned ?? false
                )
                store.insertImportedPlaylist(playlist)
                await pullTracks(client: client, store: store, remotePlaylistId: row.playlist_id, into: playlist)
            }
        } catch {
            // Soft-fail
        }
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
        struct RemoteTrack: Decodable {
            let track_id: String
            let title: String
            let primary_artist_name: String?
            let thumbnail_high: String?
        }
        do {
            let refs: [RemoteTrackRef] = try await client
                .from("playlist_track_cross_ref")
                .select()
                .eq("playlist_id", value: remotePlaylistId)
                .execute()
                .value
            for ref in refs.sorted(by: { $0.position < $1.position }) {
                let tracks: [RemoteTrack] = try await client
                    .from("tracks")
                    .select()
                    .eq("track_id", value: ref.track_id)
                    .limit(1)
                    .execute()
                    .value
                guard let t = tracks.first else { continue }
                store.add(
                    item: VideoItem(
                        videoId: t.track_id,
                        title: t.title,
                        channelName: t.primary_artist_name ?? "",
                        thumbnailURL: t.thumbnail_high.flatMap(URL.init(string:))
                    ),
                    to: playlist
                )
            }
        } catch {}
    }

    private func upsertPlaylist(client: SupabaseClient, userId: String, playlist: LibraryPlaylist) async {
        struct Payload: Encodable {
            let playlist_id: String
            let user_id: String
            let name: String
            let system_type: String?
            let is_pinned: Bool
        }
        _ = try? await client.from("playlists").upsert(
            Payload(
                playlist_id: playlist.playlistId,
                user_id: userId,
                name: playlist.name,
                system_type: playlist.systemType,
                is_pinned: playlist.isPinned
            )
        ).execute()
    }

    private func upsertTrack(client: SupabaseClient, track: LibraryTrack) async {
        struct Payload: Encodable {
            let track_id: String
            let title: String
            let duration_seconds: Int
            let thumbnail_high: String?
            let primary_artist_name: String?
        }
        _ = try? await client.from("tracks").upsert(
            Payload(
                track_id: track.videoId,
                title: track.title,
                duration_seconds: track.durationSeconds,
                thumbnail_high: track.thumbnailURLString,
                primary_artist_name: track.channelName
            )
        ).execute()
    }

    private func upsertPlaylistTrack(
        client: SupabaseClient,
        playlistId: String,
        trackId: String,
        position: Int
    ) async {
        struct Payload: Encodable {
            let playlist_id: String
            let track_id: String
            let position: Int
        }
        _ = try? await client.from("playlist_track_cross_ref").upsert(
            Payload(playlist_id: playlistId, track_id: trackId, position: position)
        ).execute()
    }

    private func upsertLastPlayed(client: SupabaseClient, userId: String, item: PlayHistoryItem) async {
        struct Payload: Encodable {
            let user_id: String
            let track_id: String
            let last_played_at: String
            let progress_ms: Int
        }
        let iso = ISO8601DateFormatter().string(from: item.playedAt)
        _ = try? await client.from("user_track_last_played").upsert(
            Payload(user_id: userId, track_id: item.videoId, last_played_at: iso, progress_ms: 0)
        ).execute()
        struct TrackPayload: Encodable {
            let track_id: String
            let title: String
            let primary_artist_name: String?
            let thumbnail_high: String?
        }
        let video = item.asVideoItem
        _ = try? await client.from("tracks").upsert(
            TrackPayload(
                track_id: video.videoId,
                title: video.title,
                primary_artist_name: video.channelName,
                thumbnail_high: video.thumbnailURL?.absoluteString
            )
        ).execute()
    }
}
