import SwiftUI
import UIKit

/// Bottom mini player — aligned with Android `MiniPlayerBar`.
struct MiniPlayerBar: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var progressClock: PlaybackProgressModel
    @State private var showPlayer = false

    private var progress: CGFloat {
        guard progressClock.durationSeconds > 0 else { return 0 }
        return CGFloat(progressClock.positionSeconds / progressClock.durationSeconds).clamped(to: 0...1)
    }

    var body: some View {
        if let item = playback.nowPlaying {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(YTLiteColor.chromeDivider)
                    .frame(height: 1 / UIScreen.main.scale)
                progressBar
                contentRow(item: item)
            }
            .background(YTLiteColor.miniPlayer)
            .sheet(isPresented: $showPlayer) {
                NavigationStack {
                    PlayerDetailView()
                }
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(YTLiteColor.miniProgressTrack)
                Rectangle()
                    .fill(YTLiteColor.miniProgress)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: YTLiteLayout.miniProgressHeight)
        .allowsHitTesting(false)
    }

    private func contentRow(item: NowPlayingItem) -> some View {
        HStack(spacing: 0) {
            // Thumbnail + title: opens player (Android weighted clickable Row).
            Button {
                showPlayer = true
            } label: {
                HStack(spacing: 0) {
                    mediaSlot(item: item)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.onSurface)
                            .lineLimit(1)
                        Text(item.channelName)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.miniMeta)
                            .lineLimit(1)
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Independent controls — do not open player.
            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .frame(width: YTLiteLayout.miniControlSize, height: YTLiteLayout.miniControlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(playback.isBuffering)
            .accessibilityLabel(playback.isPlaying ? L("common.pause") : L("common.play"))

            Button {
                playback.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .frame(width: YTLiteLayout.miniControlSize, height: YTLiteLayout.miniControlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!playback.hasNextInQueue)
            .accessibilityLabel(L("common.next"))
        }
        .frame(height: YTLiteLayout.miniBarHeight)
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private func mediaSlot(item: NowPlayingItem) -> some View {
        ZStack {
            Color.black
            // Prefer live surface when stream exists and detail sheet is not covering
            // (AVPlayerLayer can only attach to one view at a time).
            if !showPlayer, let player = playback.player {
                PipPlayerView(player: player, videoGravity: .resizeAspectFill)
                    .allowsHitTesting(false)
            } else {
                RemoteImage(url: item.thumbnailURL, contentMode: .fill)
            }
        }
        .frame(height: YTLiteLayout.miniBarHeight)
        .aspectRatio(YTLiteLayout.miniMediaAspect, contentMode: .fit)
        .clipped()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
