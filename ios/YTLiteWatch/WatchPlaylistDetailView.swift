import SwiftUI

struct WatchPlaylistDetailView: View {
    @EnvironmentObject private var bridge: WatchConnectivityBridge
    @ObservedObject private var library = WatchLibraryClient.shared

    let playlistId: String

    private var playlist: WatchConnectivityProtocol.LibraryPlaylistDTO? {
        library.snapshot?.playlists.first(where: { $0.playlistId == playlistId })
    }

    var body: some View {
        Group {
            if let playlist {
                List {
                    if !bridge.isReachable {
                        Text(String(localized: "watch.phone_disconnected_readonly", defaultValue: "Phone disconnected · Read only"))
                            .font(WatchType.metaSemibold)
                            .foregroundStyle(.orange)
                            .listRowBackground(Color.clear)
                    }

                    if bridge.isReachable, !playlist.tracks.isEmpty {
                        Button {
                            library.shufflePlay(playlistId: playlist.playlistId)
                        } label: {
                            Label(
                                String(localized: "watch.shuffle_play", defaultValue: "Shuffle play"),
                                systemImage: "shuffle"
                            )
                            .font(WatchType.title)
                        }
                    }

                    if playlist.tracks.isEmpty {
                        Text(String(localized: "watch.playlist_empty", defaultValue: "No tracks"))
                            .font(WatchType.title)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { index, track in
                            WatchTrackRow(
                                track: track,
                                playlistId: playlist.playlistId,
                                canRemoveFromPlaylist: playlist.canEdit
                                    || playlist.systemType == "favorites"
                                    || playlist.systemType == "watch_later"
                            ) {
                                play(index: index)
                            }
                        }
                    }

                    if playlist.trackCount > playlist.tracks.count {
                        Text("Showing \(playlist.tracks.count) of \(playlist.trackCount)")
                            .font(WatchType.meta)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle(playlist.name)
            } else {
                ContentUnavailableView(
                    String(localized: "watch.playlist_missing", defaultValue: "Playlist unavailable"),
                    systemImage: "music.note.list"
                )
            }
        }
    }

    private func play(index: Int) {
        guard library.requireConnected() else { return }
        library.playPlaylist(playlistId: playlistId, index: index)
    }
}
