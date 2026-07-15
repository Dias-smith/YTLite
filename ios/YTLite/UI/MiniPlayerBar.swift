import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var playback: PlaybackController
    @State private var showPlayer = false

    var body: some View {
        if let item = playback.nowPlaying {
            HStack(spacing: 12) {
                Button {
                    showPlayer = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.25))
                                .frame(width: 44, height: 44)
                            if playback.isBuffering {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Text(item.channelName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                Button { playback.playPrevious() } label: {
                    Image(systemName: "backward.fill")
                }
                .disabled(playback.queue.count <= 1 && playback.positionSeconds <= 3)

                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .disabled(playback.isBuffering || playback.player == nil)

                Button { playback.playNext() } label: {
                    Image(systemName: "forward.fill")
                }
                .disabled(playback.queueIndex + 1 >= playback.queue.count)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .sheet(isPresented: $showPlayer) {
                NavigationStack { PlayerDetailView() }
            }
        }
    }
}
