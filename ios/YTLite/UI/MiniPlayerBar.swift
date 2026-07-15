import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var playback: PlaybackController
    @State private var showPlayer = false

    var body: some View {
        if let item = playback.nowPlaying {
            HStack(spacing: YTLiteLayout.stackLoose) {
                Button {
                    showPlayer = true
                } label: {
                    HStack(spacing: YTLiteLayout.stackLoose) {
                        RemoteImage(url: item.thumbnailURL)
                            .frame(width: YTLiteLayout.miniThumb, height: YTLiteLayout.miniThumb)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(YTLiteType.rowTitleMedium)
                                .foregroundStyle(YTLiteColor.onSurface)
                                .lineLimit(1)
                            Text(item.channelName)
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                .lineLimit(1)
                        }
                        Spacer(minLength: YTLiteLayout.stackDefault)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(width: 36, height: 36)
                }
                .disabled(playback.isBuffering || playback.player == nil)

                Button {
                    playback.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(width: 36, height: 36)
                }
                .disabled(playback.queueIndex + 1 >= playback.queue.count)
            }
            .padding(.horizontal, YTLiteLayout.stackLoose)
            .padding(.vertical, YTLiteLayout.rowVertical)
            .background(YTLiteColor.miniPlayer)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(YTLiteColor.onSurface.opacity(0.08))
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
