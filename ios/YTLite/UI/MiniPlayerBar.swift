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
                        AsyncImage(url: item.thumbnailURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                YTLiteColor.surfaceVariant
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(item.channelName)
                                .font(.caption)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .disabled(playback.isBuffering || playback.player == nil)

                Button {
                    playback.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .disabled(playback.queueIndex + 1 >= playback.queue.count)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(YTLiteColor.miniPlayer)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
            }
            .sheet(isPresented: $showPlayer) {
                NavigationStack {
                    PlayerDetailView()
                        .preferredColorScheme(.dark)
                }
            }
        }
    }
}
