import SwiftUI
import AVKit

struct PlayerDetailView: View {
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showSpeedSheet = false
    @State private var showAddPlaylist = false
    @State private var showLyrics = false

    var body: some View {
        VStack(spacing: 0) {
            videoSurface
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let item = playback.nowPlaying {
                        Text(item.title)
                            .font(.title3.weight(.semibold))
                        Text(item.channelName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let error = playback.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    actionRow
                    transport
                    speedRow

                    if playback.queue.count > 1 {
                        Text("Up Next")
                            .font(.headline)
                        ForEach(Array(playback.queue.enumerated()), id: \.element.id) { index, item in
                            HStack {
                                Text(item.title)
                                    .lineLimit(1)
                                Spacer()
                                if index == playback.queueIndex {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(index == playback.queueIndex ? .primary : .secondary)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let item = playback.nowPlaying {
                    ShareLink(item: item.watchShareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showSpeedSheet) {
            SpeedPickerSheet(selected: $playback.playbackSpeed)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddPlaylist) {
            AddToPlaylistSheet()
        }
        .sheet(isPresented: $showLyrics) {
            LyricsSheet()
        }
        .onAppear {
            playback.libraryStore = store ?? playback.libraryStore
            playback.refreshFavoriteState()
        }
    }

    @ViewBuilder
    private var videoSurface: some View {
        ZStack {
            if let player = playback.player {
                // System PiP is available from the player chrome (top-trailing) and auto-start on background.
                PipPlayerView(player: player)
            } else {
                Color.black
            }
            if playback.isBuffering {
                ProgressView("Extracting…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 20) {
            Button {
                playback.toggleFavorite()
            } label: {
                Label(
                    playback.isFavorite ? "Liked" : "Like",
                    systemImage: playback.isFavorite ? "heart.fill" : "heart"
                )
            }
            Button {
                showAddPlaylist = true
            } label: {
                Label("Save", systemImage: "bookmark")
            }
            Button {
                showLyrics = true
            } label: {
                Label("Lyrics", systemImage: "text.bubble")
            }
            if let item = playback.nowPlaying {
                ShareLink(item: item.watchShareURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Spacer()
        }
        .labelStyle(.iconOnly)
        .font(.title3)
    }

    private var transport: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { playback.positionSeconds },
                    set: { playback.seek(to: $0) }
                ),
                in: 0...max(playback.durationSeconds, 1)
            )
            HStack {
                Text(formatTime(playback.positionSeconds))
                    .font(.caption.monospacedDigit())
                Spacer()
                Text(formatTime(playback.durationSeconds))
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 36) {
                Button { playback.playPrevious() } label: {
                    Image(systemName: "backward.fill").font(.title2)
                }
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
                Button { playback.playNext() } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var speedRow: some View {
        Button { showSpeedSheet = true } label: {
            HStack {
                Text("Playback speed")
                Spacer()
                Text(PlaybackSpeeds.formatLabel(playback.playbackSpeed))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private extension NowPlayingItem {
    var watchShareURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }
}

struct SpeedPickerSheet: View {
    @Binding var selected: Float
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(PlaybackSpeeds.options, id: \.self) { speed in
                Button {
                    selected = speed
                    dismiss()
                } label: {
                    HStack {
                        Text(
                            speed == 1
                                ? "Normal (\(PlaybackSpeeds.formatLabel(speed)))"
                                : PlaybackSpeeds.formatLabel(speed)
                        )
                        Spacer()
                        if abs(speed - selected) < 0.001 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .navigationTitle("Playback speed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AddToPlaylistSheet: View {
    @Environment(\.libraryStore) private var store
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store?.allPlaylists() ?? [], id: \.playlistId) { playlist in
                Button(playlist.name) {
                    guard let current = playback.nowPlaying else { return }
                    store?.add(
                        item: VideoItem(
                            videoId: current.videoId,
                            title: current.title,
                            channelName: current.channelName,
                            thumbnailURL: current.thumbnailURL
                        ),
                        to: playlist
                    )
                    dismiss()
                }
            }
            .navigationTitle("Save to playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
