import SwiftUI
import UIKit

/// Bottom mini player — aligned with Android `MiniPlayerBar`.
struct MiniPlayerBar: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.displayScale) private var displayScale
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeWidth: CGFloat = 0
    @State private var settleTask: Task<Void, Never>?

    var body: some View {
        if let item = playback.nowPlaying {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(YTLiteColor.chromeDivider)
                    .frame(height: YTLiteLayout.hairlineHeight(displayScale: displayScale))
                MiniPlayerProgressBar()
                contentRow(item: item)
            }
            .background(YTLiteColor.miniPlayer)
        }
    }

    private func contentRow(item: NowPlayingItem) -> some View {
        HStack(spacing: 0) {
            // Thumbnail + title: tap opens player; horizontal swipe skips tracks.
            HStack(spacing: 0) {
                mediaSlot(item: item, showsLiveVideo: abs(swipeOffset) < 0.5)
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
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { swipeWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in
                            swipeWidth = width
                        }
                }
            }
            .offset(x: swipeOffset)
            .gesture(trackSwipeGesture)
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard abs(swipeOffset) < 8 else { return }
                    dismissSwipeGuide()
                    playerPresentation.present()
                }
            )
            .bubbleGuideTarget(.miniPlayerSwipe)
            .clipped()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(item.title)

            transportControls
        }
        .frame(height: YTLiteLayout.miniBarHeight)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var transportControls: some View {
        #if targetEnvironment(macCatalyst)
        if let item = playback.nowPlaying {
            MacSongCacheButton(
                videoId: item.videoId,
                thumbnailURL: item.thumbnailURL,
                isLive: currentItemIsLive,
                side: YTLiteLayout.miniControlSize,
                iconPointSize: 20
            )
        }
        #endif
        transportButton(
            systemName: playback.isPlaying ? "pause.fill" : "play.fill",
            label: playback.isPlaying ? L("common.pause") : L("common.play"),
            disabled: playback.isBuffering
        ) {
            playback.togglePlayPause()
        }
        transportButton(
            systemName: "forward.fill",
            label: L("common.next"),
            disabled: !playback.hasNextInQueue
        ) {
            playback.playNext()
        }
    }

    #if targetEnvironment(macCatalyst)
    private var currentItemIsLive: Bool {
        guard let videoId = playback.nowPlaying?.videoId,
              playback.queue.indices.contains(playback.queueIndex) else { return false }
        let item = playback.queue[playback.queueIndex]
        return item.videoId == videoId && item.isLive
    }
    #endif

    private func transportButton(
        systemName: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismissSwipeGuide()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(YTLiteColor.onSurface)
                .frame(width: YTLiteLayout.miniControlSize, height: YTLiteLayout.miniControlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    /// Left → next, right → previous. Vertical pans ignored so parent scroll still works.
    private var trackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                settleTask?.cancel()
                settleTask = nil
                let dx = value.translation.width
                let dy = value.translation.height
                let x: CGFloat
                if abs(dx) <= abs(dy) * 1.1 {
                    x = 0
                } else if dx > 0 && !playback.hasPreviousInQueue {
                    x = dx * 0.22
                } else if dx < 0 && !playback.hasNextInQueue {
                    x = dx * 0.22
                } else {
                    x = max(-swipeTravel, min(swipeTravel, dx))
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    swipeOffset = x
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let predicted = value.predictedEndTranslation.width
                let primary = abs(predicted) > abs(dx) ? predicted : dx
                let horizontal = abs(dx) > abs(dy) * 1.1
                if horizontal, abs(primary) > 28 {
                    dismissSwipeGuide()
                }
                let skipNext = horizontal && primary < -52 && playback.hasNextInQueue
                let skipPrevious = horizontal && primary > 52 && playback.hasPreviousInQueue
                guard skipNext || skipPrevious else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        swipeOffset = 0
                    }
                    return
                }
                let travel = swipeTravel
                let outgoing: CGFloat = skipNext ? -travel : travel
                withAnimation(.easeOut(duration: 0.16)) {
                    swipeOffset = outgoing
                }
                settleTask?.cancel()
                settleTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        swipeOffset = -outgoing
                    }
                    if skipNext {
                        playback.playNext(reason: "mini_swipe")
                    } else {
                        playback.playPrevious()
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        swipeOffset = 0
                    }
                }
            }
    }

    private var swipeTravel: CGFloat {
        swipeWidth > 1 ? swipeWidth : 160
    }

    private func dismissSwipeGuide() {
        BubbleGuideStore.shared.dismiss(.miniPlayerSwipe)
    }

    @ViewBuilder
    private func mediaSlot(item: NowPlayingItem, showsLiveVideo: Bool) -> some View {
        ZStack {
            Color.black
            // The live layer stays put while the finger is down. Moving AVPlayerLayer each frame stutters the swipe.
            if showsLiveVideo, !playerPresentation.isPresented, let player = playback.player {
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
        #if targetEnvironment(macCatalyst)
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.leading, 16)
        #else
        .frame(height: YTLiteLayout.miniBarHeight)
        .aspectRatio(YTLiteLayout.miniMediaAspect, contentMode: .fit)
        .clipped()
        #endif
    }
}

/// Progress ticks stay in this view so they do not redraw the swiping row.
private struct MiniPlayerProgressBar: View {
    @EnvironmentObject private var progressClock: PlaybackProgressModel

    private var progress: CGFloat {
        guard progressClock.durationSeconds > 0 else { return 0 }
        return CGFloat(progressClock.positionSeconds / progressClock.durationSeconds).clamped(to: 0...1)
    }

    var body: some View {
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
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#if targetEnvironment(macCatalyst)
struct MacMiniPlayerHost<Content: View>: View {
    @ObservedObject private var chrome = MacWindowChrome.shared
    @EnvironmentObject private var playback: PlaybackController
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if chrome.isMinimizedToPlayer {
                MacShrunkMiniPlayer()
                    .ignoresSafeArea()
            } else {
                content()
            }
        }
        .onAppear {
            chrome.hasNowPlaying = playback.nowPlaying != nil
        }
        .onChange(of: playback.nowPlaying?.videoId) { _, _ in
            chrome.hasNowPlaying = playback.nowPlaying != nil
        }
    }
}

/// Window contents after the yellow button shrinks Mixtube to an on-screen player.
private struct MacShrunkMiniPlayer: View {
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        VStack(spacing: 0) {
            MiniPlayerProgressBar()
            HStack(spacing: 8) {
                if let item = playback.nowPlaying {
                    HStack(spacing: 10) {
                        RemoteImage(url: item.thumbnailURL, contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                        Spacer(minLength: 8)
                    }
                    shrunkTransport
                } else {
                    Text(L("common.no_videos"))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    Spacer(minLength: 8)
                }
                Button {
                    MacAppLifetime.restoreShrunkWindow()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("mac.mini_player.restore"))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(YTLiteColor.miniPlayer)
        .contentShape(Rectangle())
        .simultaneousGesture(windowDrag)
    }

    private var currentItemIsLive: Bool {
        guard let videoId = playback.nowPlaying?.videoId,
              playback.queue.indices.contains(playback.queueIndex) else { return false }
        let item = playback.queue[playback.queueIndex]
        return item.videoId == videoId && item.isLive
    }

    private var windowDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                MacAppLifetime.beginMiniPlayerDrag()
            }
            .onEnded { _ in
                MacAppLifetime.endMiniDrag()
            }
    }

    @ViewBuilder
    private var shrunkTransport: some View {
        if let item = playback.nowPlaying {
            MacSongCacheButton(
                videoId: item.videoId,
                thumbnailURL: item.thumbnailURL,
                isLive: currentItemIsLive,
                side: 32,
                iconPointSize: 18
            )
        }

        Button {
            playback.togglePlayPause()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(playback.isBuffering)
        .accessibilityLabel(playback.isPlaying ? L("common.pause") : L("common.play"))

        Button {
            playback.playNext()
        } label: {
            Image(systemName: "forward.fill")
                .frame(width: 32, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!playback.hasNextInQueue)
        .accessibilityLabel(L("common.next"))
    }
}
#endif

/// Slim offer above the mini player, and under the video when the full player is open.
struct LibrarySavePromptBanner: View {
    static let reservedHeight: CGFloat = 44

    @ObservedObject private var prompt = LibrarySavePromptStore.shared
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.displayScale) private var displayScale

    private var isOffering: Bool {
        guard let offer = prompt.offerVideoId, offer == playback.nowPlaying?.videoId else { return false }
        return !playback.isFavorite
    }

    var body: some View {
        if isOffering {
            HStack(spacing: 8) {
                Text(L("library_save_prompt.message"))
                    .font(YTLiteType.meta.weight(.semibold))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: addToLiked) {
                    Text(L("library_save_prompt.add"))
                        .font(YTLiteType.meta.weight(.semibold))
                        .foregroundStyle(YTLiteColor.accent)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                Button(action: { prompt.dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("common.close"))
            }
            .padding(.leading, YTLiteLayout.screenPadding)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity)
            .frame(height: Self.reservedHeight)
            .background(YTLiteColor.surfaceElevated)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(YTLiteColor.chromeDivider)
                    .frame(height: YTLiteLayout.hairlineHeight(displayScale: displayScale))
            }
            .gesture(dismissSwipe)
            .accessibilityElement(children: .contain)
        }
    }

    private func addToLiked() {
        guard prompt.offerVideoId == playback.nowPlaying?.videoId, playback.libraryStore != nil else {
            prompt.dismiss()
            return
        }
        playback.toggleFavorite()
        guard playback.isFavorite else { return }
        prompt.accept()
        trackActions.showToast(L("toast.liked"))
    }

    private var dismissSwipe: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onEnded { value in
                let travel = abs(value.translation.height) > 20 || abs(value.translation.width) > 48
                if travel {
                    prompt.dismiss()
                }
            }
    }
}

/// Dismissible sign-in offer. Shown only while nothing is playing, so it does not cover the current song.
struct PlaybackLoginBanner: View {
    static let reservedHeight: CGFloat = 44

    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.displayScale) private var displayScale
    @State private var showSignIn = false

    private var isVisible: Bool {
        playback.needsLoginForPlayback && !playback.isPlaying && !playback.isBuffering
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                Text(L("player.sign_in_to_play"))
                    .font(YTLiteType.meta.weight(.semibold))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    showSignIn = true
                } label: {
                    Text(L("common.sign_in"))
                        .font(YTLiteType.meta.weight(.semibold))
                        .foregroundStyle(YTLiteColor.accent)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                Button {
                    playback.dismissPlaybackLoginPrompt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("common.close"))
            }
            .padding(.leading, YTLiteLayout.screenPadding)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity)
            .frame(height: Self.reservedHeight)
            .background(YTLiteColor.surfaceElevated)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(YTLiteColor.chromeDivider)
                    .frame(height: YTLiteLayout.hairlineHeight(displayScale: displayScale))
            }
            .onAppear {
                LibrarySavePromptStore.shared.setBusy("playback_login", true)
                AppAnalytics.playbackLoginPrompt(hasGoogle: auth.googleAccessToken != nil)
            }
            .onDisappear {
                LibrarySavePromptStore.shared.setBusy("playback_login", false)
            }
            .sheet(isPresented: $showSignIn) {
                PlaybackSignInSheet(showSignIn: $showSignIn)
            }
        }
    }
}

private struct PlaybackSignInSheet: View {
    @Binding var showSignIn: Bool
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(L("player.sign_in_to_play"))
                    .font(YTLiteType.sectionTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .padding(.top, 8)
                Text(L("player.sign_in_to_play_desc"))
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                Button {
                    Task {
                        AppAnalytics.playbackLoginContinue()
                        await auth.signInWithGoogle(source: "player")
                        if auth.isAuthenticated {
                            appModel.syncAuth(auth)
                            showSignIn = false
                            playback.retryPlaybackAfterLogin()
                        }
                    }
                } label: {
                    Text(auth.isBusy ? L("common.signing_in") : L("auth.continue_with_google"))
                        .font(YTLiteType.labelEmphasized)
                        .foregroundStyle(YTLiteColor.onAccent)
                        .frame(maxWidth: 280)
                        .frame(height: 44)
                        .background(YTLiteColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(auth.isBusy || !auth.isConfigured)
                if let err = auth.lastError, !err.isEmpty {
                    Text(err)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                }
                Spacer(minLength: 0)
            }
            .background(YTLiteColor.surfaceElevated)
            .navigationTitle(L("common.sign_in"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) { showSignIn = false }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(YTLiteColor.surfaceElevated)
    }
}
