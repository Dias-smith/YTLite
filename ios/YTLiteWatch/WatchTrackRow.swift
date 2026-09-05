import SwiftUI

/// Track row with context actions + sheets hosted on the row (not inside the menu).
struct WatchTrackRow: View {
    @ObservedObject private var library = WatchLibraryClient.shared

    let track: WatchConnectivityProtocol.LibraryTrackDTO
    var playlistId: String? = nil
    var historyIndex: Int? = nil
    var canRemoveFromPlaylist: Bool = false
    var onPlay: () -> Void

    @State private var showEdit = false
    @State private var showSavePicker = false

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.caption)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(track.artist)
                        .lineLimit(1)
                    if let duration = track.durationText, !duration.isEmpty {
                        Text("·")
                        Text(duration)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                guard library.requireConnected() else { return }
                library.playNext(videoId: track.videoId)
            } label: {
                Label(String(localized: "watch.play_next", defaultValue: "Play next"), systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                guard library.requireConnected() else { return }
                library.addToQueue(videoId: track.videoId)
            } label: {
                Label(String(localized: "watch.add_to_queue", defaultValue: "Add to queue"), systemImage: "text.append")
            }

            Button {
                guard library.requireConnected() else { return }
                if library.isFavorite(videoId: track.videoId) {
                    library.unlike(videoId: track.videoId)
                } else {
                    library.like(videoId: track.videoId)
                }
            } label: {
                Label(
                    library.isFavorite(videoId: track.videoId)
                        ? String(localized: "watch.unlike", defaultValue: "Unlike")
                        : String(localized: "watch.like", defaultValue: "Like"),
                    systemImage: library.isFavorite(videoId: track.videoId) ? "heart.slash" : "heart"
                )
            }

            Button {
                guard library.requireConnected() else { return }
                showSavePicker = true
            } label: {
                Label(String(localized: "watch.save_to_playlist", defaultValue: "Save to playlist"), systemImage: "plus.rectangle.on.folder")
            }

            Button {
                guard library.requireConnected() else { return }
                showEdit = true
            } label: {
                Label(String(localized: "watch.edit_info", defaultValue: "Edit info"), systemImage: "pencil")
            }

            Button {
                guard library.requireConnected() else { return }
                library.share(videoId: track.videoId)
            } label: {
                Label(String(localized: "watch.share", defaultValue: "Share"), systemImage: "square.and.arrow.up")
            }

            Button {
                guard library.requireConnected() else { return }
                library.notInterested(videoId: track.videoId)
            } label: {
                Label(String(localized: "watch.not_interested", defaultValue: "Not interested"), systemImage: "hand.thumbsdown")
            }

            if canRemoveFromPlaylist, let playlistId {
                Button(role: .destructive) {
                    guard library.requireConnected() else { return }
                    library.removeFromPlaylist(videoId: track.videoId, playlistId: playlistId)
                } label: {
                    Label(String(localized: "watch.remove", defaultValue: "Remove"), systemImage: "trash")
                }
            }

            if historyIndex != nil {
                Button(role: .destructive) {
                    guard library.requireConnected() else { return }
                    library.removeFromHistory(videoIds: [track.videoId])
                } label: {
                    Label(String(localized: "watch.remove_from_history", defaultValue: "Remove from history"), systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            WatchEditMetadataSheet(track: track)
        }
        .sheet(isPresented: $showSavePicker) {
            WatchSaveToPlaylistSheet(videoId: track.videoId)
        }
    }
}
