import SwiftUI
import UIKit

/// Bottom mini player — aligned with Android `MiniPlayerBar`.
struct MiniPlayerBar: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var progressClock: PlaybackProgressModel
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.displayScale) private var displayScale
    @State private var swipeOffset: CGFloat = 0

    private var progress: CGFloat {
        guard progressClock.durationSeconds > 0 else { return 0 }
        return CGFloat(progressClock.positionSeconds / progressClock.durationSeconds).clamped(to: 0...1)
    }

    var body: some View {
        if let item = playback.nowPlaying {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(YTLiteColor.chromeDivider)
                    .frame(height: YTLiteLayout.hairlineHeight(displayScale: displayScale))
                progressBar
                contentRow(item: item)
            }
            .background(YTLiteColor.miniPlayer)
            .onChange(of: item.videoId) { _, _ in
                swipeOffset = 0
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(YTLiteColor.miniProgressTrack)
                Rectangle()
                    .fill(YTLiteColor.accent)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: YTLiteLayout.miniProgressHeight)
        .allowsHitTesting(false)
    }

    private func contentRow(item: NowPlayingItem) -> some View {
        HStack(spacing: 0) {
            // Thumbnail + title: tap opens player; horizontal swipe skips tracks.
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
            .offset(x: swipeOffset)
            .gesture(trackSwipeGesture)
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard abs(swipeOffset) < 8 else { return }
                    BubbleGuideStore.shared.dismiss(.miniPlayerSwipe)
                    playerPresentation.present()
                }
            )
            .bubbleGuideTarget(.miniPlayerSwipe)
            .clipped()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(item.title)

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
        .contentShape(Rectangle())
    }

    /// Left → next, right → previous. Vertical pans ignored so parent scroll still works.
    private var trackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) * 1.1 else {
                    if abs(swipeOffset) > 0 {
                        swipeOffset = 0
                    }
                    return
                }
                var x = dx
                // Soft rubber-band when there is no neighbor track.
                if dx > 0 && !playback.hasPreviousInQueue {
                    x = dx * 0.22
                } else if dx < 0 && !playback.hasNextInQueue {
                    x = dx * 0.22
                } else {
                    x = max(-120, min(120, dx))
                }
                swipeOffset = x
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let predicted = value.predictedEndTranslation.width
                let primary = abs(predicted) > abs(dx) ? predicted : dx
                let shouldSkip = abs(dx) > abs(dy) * 1.1 && abs(primary) > 52

                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    swipeOffset = 0
                }

                // Any clear horizontal swipe dismisses the coach mark (user discovered the gesture).
                if abs(dx) > abs(dy) * 1.1, abs(primary) > 28 {
                    BubbleGuideStore.shared.dismiss(.miniPlayerSwipe)
                }

                guard shouldSkip else { return }
                if primary < 0, playback.hasNextInQueue {
                    playback.playNext()
                } else if primary > 0, playback.hasPreviousInQueue {
                    playback.playPrevious()
                }
            }
    }

    @ViewBuilder
    private func mediaSlot(item: NowPlayingItem) -> some View {
        ZStack {
            Color.black
            // Prefer live surface when stream exists and detail is not covering
            // (AVPlayerLayer can only attach to one view at a time).
            if !playerPresentation.isPresented, let player = playback.player {
                PipPlayerView(
                    player: player,
                    videoGravity: .resizeAspectFill,
                    pictureInPictureEnabled: appModel.pictureInPictureEnabled
                )
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
