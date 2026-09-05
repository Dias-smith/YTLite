import SwiftUI

struct WatchEditMetadataSheet: View {
    @ObservedObject private var library = WatchLibraryClient.shared
    @Environment(\.dismiss) private var dismiss

    let track: WatchConnectivityProtocol.LibraryTrackDTO

    @State private var titleText: String = ""
    @State private var artistText: String = ""
    @State private var albumText: String = ""
    @State private var yearText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "watch.field_title", defaultValue: "Title"), text: $titleText)
                TextField(String(localized: "watch.field_artist", defaultValue: "Artist"), text: $artistText)
                TextField(String(localized: "watch.field_album", defaultValue: "Album"), text: $albumText)
                TextField(String(localized: "watch.field_year", defaultValue: "Year"), text: $yearText)
            }
            .navigationTitle(String(localized: "watch.edit_info", defaultValue: "Edit info"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "watch.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "watch.save", defaultValue: "Save")) {
                        guard library.requireConnected() else { return }
                        library.editMetadata(
                            WatchConnectivityProtocol.EditMetadataBody(
                                videoId: track.videoId,
                                title: titleText,
                                artist: artistText,
                                album: albumText,
                                year: yearText,
                                thumbnailURL: track.thumbnailURL
                            )
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                titleText = track.title
                artistText = track.artist
            }
        }
    }
}

struct WatchSaveToPlaylistSheet: View {
    @ObservedObject private var library = WatchLibraryClient.shared
    @Environment(\.dismiss) private var dismiss

    let videoId: String

    private var writablePlaylists: [WatchConnectivityProtocol.LibraryPlaylistDTO] {
        (library.snapshot?.playlists ?? []).filter {
            $0.canEdit || $0.systemType == "favorites" || $0.systemType == "watch_later"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(writablePlaylists) { playlist in
                    Button {
                        guard library.requireConnected() else { return }
                        library.addToPlaylist(videoId: videoId, playlistId: playlist.playlistId)
                        dismiss()
                    } label: {
                        Text(playlist.name)
                    }
                }
            }
            .navigationTitle(String(localized: "watch.save_to_playlist", defaultValue: "Save to playlist"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "watch.cancel", defaultValue: "Cancel")) { dismiss() }
                }
            }
        }
    }
}
