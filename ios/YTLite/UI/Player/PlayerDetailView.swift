import SwiftUI
import AVKit

private enum PlayerTab: String, CaseIterable {
    case upNext
    // Lyrics tab temporarily hidden.
    case related

    var title: String {
        switch self {
        case .upNext: return L("player.up_next")
        case .related: return L("player.related")
        }
    }
}

private enum PlayerListSort: String, CaseIterable {
    case original
    case titleAsc
    case titleDesc
    case artistAsc

    var title: String {
        switch self {
        case .original: return "Original order"
        case .titleAsc: return L("library.sort.title_asc")
        case .titleDesc: return L("library.sort.title_desc")
        case .artistAsc: return "Artist A–Z"
        }
    }
}

private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .white
        picker.activeTintColor = .systemOrange
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = .white
        uiView.activeTintColor = .systemOrange
    }
}

struct PlayerDetailView: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var progressClock: PlaybackProgressModel
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showSpeedSheet = false
    @State private var showEqualizerSheet = false
    @State private var showHLSQualitySheet = false
    @State private var showSleepTimerSheet = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showAddPlaylist = false
    @State private var showSaveList = false
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var tab: PlayerTab = .upNext
    @State private var pipRequestID = 0
    @State private var fullscreenRequestID = 0
    @State private var related: [VideoItem] = []
    @State private var relatedOriginal: [VideoItem] = []
    /// Video id that `related` / `relatedOriginal` were fetched for (nil while stale / loading).
    @State private var relatedSourceVideoId: String?
    @State private var relatedLoading = false
    @State private var relatedError: String?
    @State private var relatedVersion: Int = 0
    /// In-player toast (root `TrackActionHost` toast sits behind this sheet).
    @State private var playerToast: String?

    @State private var showSortMenu = false
    @State private var listSort: PlayerListSort = .original
    @State private var isSelectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var showBatchAdd = false
    /// Local rich-menu presentation — must be on this sheet, not Root's TrackActionHost.
    @State private var playerTrackMenu: TrackActionContext?
    /// Channel uploads browser opened from the channel row.
    @State private var channelSheetItem: ChannelItem?
    /// Interactive dismiss offset for regular-width fullScreenCover (follows the finger).
    @State private var dismissDragOffset: CGFloat = 0
    /// Latest player canvas height from GeometryReader (avoids `UIScreen.main` on Duo).
    @State private var canvasHeight: CGFloat = 0

    private let overlayAutoHideSeconds: UInt64 = 5_000_000_000
    private let dismissDistanceThreshold: CGFloat = 96
    private let dismissVelocityThreshold: CGFloat = 650

    private var isPresentingAdBlockingSheet: Bool {
        showSpeedSheet
            || showEqualizerSheet
            || showHLSQualitySheet
            || showSleepTimerSheet
            || showShareSheet
            || showAddPlaylist
            || showSaveList
            || showBatchAdd
            || showSortMenu
            || playerTrackMenu != nil
            || channelSheetItem != nil
    }

    var body: some View {
        playerDetailRoot
            .background(PlayerDetailOrientationLockRepresentable())
            .onAppear {
                playback.libraryStore = store ?? playback.libraryStore
                playback.refreshFavoriteState()
                if !playback.isBuffering {
                    bumpOverlayAutoHide()
                }
            }
            .onChange(of: isPresentingAdBlockingSheet) { _, blocked in
                AdSceneLifecycle.setUIBlocked("player_detail_sheet", blocked: blocked)
            }
            .onDisappear {
                // leave_player is owned by the presenting host onDismiss —
                // do not fire it here (nested sheets / host rebuilds can disappear briefly).
                AdSceneLifecycle.setUIBlocked("player_detail_sheet", blocked: false)
            }
    }

    /// Title, controls, and queue/related — shared by portrait stack and landscape split.
    private var playerSecondaryColumn: some View {
        VStack(spacing: 0) {
            PlaybackLoginBanner()
            LibrarySavePromptBanner()
            pinnedTitleRow
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.top, YTLiteLayout.stackLoose)
                .padding(.bottom, YTLiteLayout.stackDefault)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(YTLiteColor.surface)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: YTLiteLayout.screenPadding) {
                        Color.clear
                            .frame(height: 0)
                            .id("playerSecondaryTop")
                        channelRow
                        if let error = playback.lastError,
                           !playback.isPlaying,
                           !playback.needsLoginForPlayback
                        {
                            Text(error)
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.danger)
                        }
                        actionBar
                        transportControls
                        tabHeader
                        if isSelectionMode {
                            selectionToolbar
                        } else {
                            listToolbar
                        }
                        // Isolate queue/related rows from buffering-only playback publishes.
                        // Row-level Equatable keeps isCurrent updates from rebuilding every cell.
                        // Taps pass video id. Equality also includes the row offset so shuffle
                        // or a mid-queue insert refreshes the tap closure instead of keeping
                        // the offset captured before the reorder.
                        PlayerQueueTabPane(
                            token: playerQueueTabToken,
                            tab: tab,
                            queue: playback.queue,
                            queueIndex: playback.queueIndex,
                            related: related,
                            relatedLoading: relatedLoading,
                            relatedError: relatedError,
                            isSelectionMode: isSelectionMode,
                            selectedIds: selectedIds,
                            onSelectQueueVideoId: { playback.playQueueVideoId($0) },
                            onToggleSelection: { toggleSelection($0) },
                            onPlayRelatedVideoId: { playRelated(videoId: $0) },
                            onRetryRelated: { Task { await loadRelated() } },
                            onOpenTrackMenu: { openTrackMenu($0) }
                        )
                        .equatable()
                    }
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .padding(.top, YTLiteLayout.stackDefault)
                    .padding(.bottom, 32)
                }
                // Related taps shrink the list while keeping scroll offset → blank black area.
                // Up Next stays put so the queue doesn't jump when skipping within it.
                .onChange(of: playback.nowPlaying?.videoId) { _, _ in
                    guard tab == .related else { return }
                    proxy.scrollTo("playerSecondaryTop", anchor: .top)
                }
            }
        }
    }

    private var playerQueueTabToken: Int {
        var hasher = Hasher()
        hasher.combine(tab)
        hasher.combine(playback.queue.count)
        hasher.combine(playback.queueIndex)
        // Include display fields so Edit Info refreshes Equatable Up Next rows.
        for item in playback.queue {
            hasher.combine(item.videoId)
            hasher.combine(item.title)
            hasher.combine(item.channelName)
            hasher.combine(item.thumbnailURL?.absoluteString)
        }
        hasher.combine(relatedVersion)
        hasher.combine(relatedLoading)
        hasher.combine(relatedError)
        hasher.combine(isSelectionMode)
        hasher.combine(selectedIds)
        return hasher.finalize()
    }

    private var playerDetailRoot: some View {
        GeometryReader { geo in
            let split = YTLiteAdaptive.playerUsesSplitLayout(
                size: geo.size,
                sizeClass: horizontalSizeClass
            )
            Group {
                if split {
                    HStack(spacing: 0) {
                        playerCanvas
                            .frame(maxWidth: geo.size.width * 0.58)
                            .frame(maxHeight: .infinity)
                        playerSecondaryColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        playerCanvas
                            .ytLiteContentWidth(
                                min(geo.size.width, 900),
                                enabled: YTLiteAdaptive.isRegularWidth(horizontalSizeClass)
                            )
                        playerSecondaryColumn
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: max(0, dismissDragOffset))
            .scaleEffect(dismissScale, anchor: .top)
            .opacity(dismissOpacity)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: dismissCornerRadius,
                    style: .continuous
                )
            )
            .animation(
                dismissDragOffset == 0 ? .spring(response: 0.35, dampingFraction: 0.86) : nil,
                value: dismissDragOffset
            )
            .onChange(of: geo.size.height) { _, height in
                canvasHeight = height
            }
            .onAppear { canvasHeight = geo.size.height }
        }
        .background(
            YTLiteColor.surface
                .opacity(dismissBackgroundOpacity)
                .ignoresSafeArea()
        )
        .navigationBarHidden(true)
        .sheet(isPresented: $showSpeedSheet) {
            SpeedPickerSheet(selected: $playback.playbackSpeed)
                .presentationDetents([.medium])
                .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .sheet(isPresented: $showEqualizerSheet) {
            EqualizerSheet()
                .environmentObject(playback)
                .environmentObject(playback.equalizerStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .sheet(isPresented: $showHLSQualitySheet) {
            HLSQualityPickerSheet()
                .environmentObject(playback)
                .presentationDetents([.medium])
                .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
                .environmentObject(playback)
                .presentationDetents([.medium])
                .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareURL = nil }) {
            if let shareURL {
                SystemShareSheet(items: [shareURL])
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showAddPlaylist) {
            AddToPlaylistSheet(items: currentTrackItems)
                .environmentObject(trackActions)
                .environmentObject(playback)
        }
        .sheet(isPresented: $showSaveList) {
            AddToPlaylistSheet(items: playlistSaveItems)
                .environmentObject(trackActions)
                .environmentObject(playback)
        }
        .sheet(isPresented: $showBatchAdd) {
            AddToPlaylistSheet(
                items: selectedPlaylistSaveItems,
                offersCurrentQueue: true
            ) {
                exitSelectionMode()
            }
            .environmentObject(trackActions)
            .environmentObject(playback)
        }
        .sheet(isPresented: $showSortMenu) {
            PlayerListSortSheet(selected: listSort) { option in
                applySort(option)
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .sheet(item: $playerTrackMenu, onDismiss: {
            trackActions.dismissAllOverlays()
        }) { context in
            TrackActionSheet(context: context)
                .environmentObject(trackActions)
                .environmentObject(playback)
                .environment(\.libraryStore, store)
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.hidden)
                .presentationContentInteraction(.scrolls)
                .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .sheet(item: $channelSheetItem) { channel in
            NavigationStack {
                ChannelVideosView(channel: channel, usesAppWallpaper: false)
                    .environmentObject(playback)
                    .environmentObject(trackActions)
                    .environmentObject(playerPresentation)
                    .environment(\.libraryStore, store)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("common.close")) { channelSheetItem = nil }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .onChange(of: playback.isPlaying) { _, playing in
            if playing, !playback.isBuffering { bumpOverlayAutoHide() }
        }
        .onChange(of: playback.isBuffering) { _, buffering in
            if buffering {
                hideTask?.cancel()
                // ***
                withAnimation(.easeInOut(duration: 0.15)) {
                    overlayVisible = false
                }
            } else if overlayVisible {
                bumpOverlayAutoHide()
            }
            // Keep the previous Related list while resolving; refresh only after open.
            if !buffering {
                scheduleRelatedLoadIfNeeded()
            }
        }
        .onChange(of: playback.nowPlaying?.videoId) { _, _ in
            listSort = .original
            exitSelectionMode()
            // Do not clear Related yet — wait until isBuffering == false.
            scheduleRelatedLoadIfNeeded()
        }
        .onChange(of: tab) { _, newValue in
            exitSelectionMode()
            listSort = .original
            if newValue == .related {
                scheduleRelatedLoadIfNeeded()
            }
        }
        .onChange(of: trackActions.menuCloseToken) { _, _ in
            playerTrackMenu = nil
        }
        .onChange(of: playback.playbackNotice) { _, message in
            if let message, !message.isEmpty {
                showPlayerToast(message)
            }
        }
        .onChange(of: trackActions.toastMessage) { _, message in
            // Mirror host toasts (save-to-playlist, track menu) onto this sheet.
            if let message, !message.isEmpty {
                showPlayerToast(message)
            }
        }
        .onChange(of: appModel.contentLocaleRevision) { _, _ in
            // Related / radio queue is region-sensitive via InnerTube `gl`.
            related = []
            relatedOriginal = []
            relatedVersion &+= 1
            relatedError = nil
            relatedSourceVideoId = nil
            if tab == .related {
                Task { await loadRelated() }
            }
        }
        .ytLiteToast($playerToast, bottomPadding: 40)
    }

    private func showPlayerToast(_ message: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            playerToast = message
        }
    }

    // MARK: - 16:9 canvas + overlay

    private var playerCanvas: some View {
        ZStack {
            Color.black

            if let player = playback.player {
                PipPlayerView(
                    player: player,
                    pipRequestID: pipRequestID,
                    fullscreenRequestID: fullscreenRequestID,
                    isPlaying: playback.isPlaying,
                    playbackSpeed: playback.playbackSpeed,
                    pictureInPictureEnabled: appModel.pictureInPictureEnabled
                )
                .allowsHitTesting(false)
            } else if let url = playback.nowPlaying?.thumbnailURL {
                RemoteImage(url: url, contentMode: .fit)
            }

            if playback.isBuffering, playback.lastError == nil {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .tint(.white)
                    .padding(20)
                    .background(.black.opacity(0.45), in: Circle())
            }

            // Always keep a dismiss control — buffering / auto-hide hide the full overlay.
            VStack {
                HStack {
                    overlayIconButton(systemName: "chevron.down") {
                        dismiss()
                    }
                    Spacer()
                }
                .padding(.horizontal, YTLiteLayout.stackLoose)
                .padding(.top, YTLiteLayout.stackLoose)
                Spacer()
            }
            .zIndex(3)
            .allowsHitTesting(true)

            // Tap catcher under overlay so control buttons keep priority.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleOverlay() }

            // Hide controls while the loading spinner is up; reveal after buffering ends.
            if overlayVisible && !playback.isBuffering {
                canvasOverlay
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
        // fullScreenCover (regular width) has no system pull-down — canvas swipe dismisses.
        // Compact sheets use system interactive dismiss (grabber stays hidden).
        .modifier(OptionalHighPriorityDrag(enabled: supportsInteractiveDismiss, gesture: interactiveDismissGesture))
    }

    private var supportsInteractiveDismiss: Bool {
        YTLiteAdaptive.isRegularWidth(horizontalSizeClass) && !isPresentingAdBlockingSheet
    }

    private var dismissScale: CGFloat {
        1 - min(max(0, dismissDragOffset), 420) / 2800
    }

    private var dismissOpacity: CGFloat {
        1 - min(max(0, dismissDragOffset), 520) / 1100
    }

    private var dismissBackgroundOpacity: CGFloat {
        1 - min(max(0, dismissDragOffset), 420) / 520
    }

    private var dismissCornerRadius: CGFloat {
        min(28, max(0, dismissDragOffset) / 10)
    }

    /// Swipe down on the video canvas — page follows the finger, then dismisses or springs back.
    private var interactiveDismissGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard supportsInteractiveDismiss else { return }
                let dy = value.translation.height
                let dx = abs(value.translation.width)
                // Prefer downward pulls; allow a wider angle so dismiss is easier to start.
                guard dy > 0, dy > dx * 0.4 else {
                    if dismissDragOffset != 0 { dismissDragOffset = 0 }
                    return
                }
                // Rubber-band a bit past the midpoint for a natural feel.
                let resistance = dy > 280 ? 0.55 : 1
                dismissDragOffset = dy * resistance
                if overlayVisible {
                    hideTask?.cancel()
                    withAnimation(.easeInOut(duration: 0.12)) { overlayVisible = false }
                }
            }
            .onEnded { value in
                guard supportsInteractiveDismiss else { return }
                let dy = max(0, value.translation.height)
                let predicted = value.predictedEndTranslation.height
                let velocityY = value.velocity.height
                let shouldDismiss = dy > dismissDistanceThreshold
                    || predicted > dismissDistanceThreshold * 1.35
                    || velocityY > dismissVelocityThreshold
                if shouldDismiss {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dismissDragOffset = max(canvasHeight, dy + 240)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        dismiss()
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        dismissDragOffset = 0
                    }
                }
            }
    }

    private func toggleOverlay() {
        guard !playback.isBuffering else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            overlayVisible.toggle()
        }
        if overlayVisible {
            bumpOverlayAutoHide()
        } else {
            hideTask?.cancel()
        }
    }

    private var canvasOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.78), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                overlayTopBar
                    .padding(.horizontal, YTLiteLayout.stackDefault)
                    .padding(.top, YTLiteLayout.stackDefault)

                Spacer()

                overlayTransport
                    .padding(.bottom, YTLiteLayout.stackDefault)

                Spacer()

                if playback.isPlayingHLS {
                    // Live: no seekable progress; quality picker sits bottom-left instead.
                    overlayQualityButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, YTLiteLayout.stackLoose)
                        .padding(.bottom, 10)
                } else {
                    overlayProgress
                        .padding(.horizontal, YTLiteLayout.stackLoose)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private var overlayTopBar: some View {
        HStack(spacing: YTLiteLayout.stackDefault) {
            // Dismiss lives outside canvasOverlay so it stays available during login / auto-hide.
            Spacer(minLength: 44)
            HStack(spacing: 0) {
                Button {
                    showSleepTimerSheet = true
                    bumpOverlayAutoHide()
                } label: {
                    Group {
                        if playback.sleepTimerEndsAt != nil {
                            let _ = progressClock.sleepTimerTick
                            if let remaining = playback.sleepTimerRemaining {
                                Text(SleepTimerOptions.formatRemaining(remaining))
                                    .font(YTLiteType.badge)
                                    .foregroundStyle(YTLiteColor.accent)
                                    .frame(minWidth: 36)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, YTLiteLayout.rowVertical)
                            } else {
                                Image(systemName: "moon.zzz")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(YTLiteColor.onMedia)
                                    .frame(width: 36, height: 36)
                            }
                        } else {
                            Image(systemName: "moon.zzz")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(YTLiteColor.onMedia)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("player.sleep_timer"))

                Button {
                    showSpeedSheet = true
                    bumpOverlayAutoHide()
                } label: {
                    Text(PlaybackSpeeds.formatLabel(playback.playbackSpeed))
                        .font(YTLiteType.badge)
                        .foregroundStyle(YTLiteColor.onMedia)
                        .frame(minWidth: 36)
                        .padding(.horizontal, 10)
                        .padding(.vertical, YTLiteLayout.rowVertical)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("player.playback_speed"))

                Button {
                    showEqualizerSheet = true
                    bumpOverlayAutoHide()
                } label: {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            playback.equalizerStore.isEnabled ? YTLiteColor.accent : YTLiteColor.onMedia
                        )
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("equalizer.title"))

                AirPlayRoutePicker()
                    .frame(width: 36, height: 36)
                    .accessibilityLabel(L("player.airplay"))

                if appModel.pictureInPictureEnabled {
                    overlayPlainIcon("pip.enter") {
                        pipRequestID += 1
                        bumpOverlayAutoHide()
                    }
                }
                overlayPlainIcon("arrow.up.left.and.arrow.down.right") {
                    fullscreenRequestID += 1
                    bumpOverlayAutoHide()
                }
            }
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var overlayTransport: some View {
        HStack(spacing: YTLiteLayout.stackTight) {
            if !playback.isPlayingHLS {
                overlayPlainIcon("gobackward.15", size: 20) {
                    playback.seekRelative(by: -15)
                    bumpOverlayAutoHide()
                }
            }
            overlayPlainIcon("backward.fill", size: 20) {
                playback.playPrevious()
                bumpOverlayAutoHide()
            }
            overlayPlainIcon(playback.isPlaying ? "pause.fill" : "play.fill", size: 26) {
                playback.togglePlayPause()
                bumpOverlayAutoHide()
            }
            overlayPlainIcon("forward.fill", size: 20) {
                playback.playNext()
                bumpOverlayAutoHide()
            }
            if !playback.isPlayingHLS {
                overlayPlainIcon("goforward.30", size: 20) {
                    playback.seekRelative(by: 30)
                    bumpOverlayAutoHide()
                }
            }
        }
        .padding(.horizontal, YTLiteLayout.stackDefault)
        .padding(.vertical, YTLiteLayout.stackTight)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
    }

    /// Live HLS quality entry, shown bottom-left in place of the progress bar.
    private var overlayQualityButton: some View {
        Button {
            showHLSQualitySheet = true
            bumpOverlayAutoHide()
        } label: {
            HStack(spacing: 6) {
                if playback.isLoadingHLSVariants && playback.hlsVariants.isEmpty {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(YTLiteColor.onMedia)
                } else {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onMedia)
                    Text(playback.selectedHLSQualityLabel)
                        .font(YTLiteType.badge)
                        .foregroundStyle(YTLiteColor.onMedia)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, YTLiteLayout.rowVertical)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("player.quality"))
    }

    private var overlayProgress: some View {
        HStack(spacing: 10) {
            Text(formatTime(progressClock.positionSeconds))
                .font(YTLiteType.tabLabel.monospacedDigit())
                .foregroundStyle(YTLiteColor.onMedia)
                .frame(minWidth: 36, alignment: .leading)

            OrangeProgressBar(
                value: progressClock.positionSeconds,
                total: max(progressClock.durationSeconds, 1),
                trackColor: YTLiteColor.onMedia.opacity(0.35)
            ) { seconds in
                playback.seek(to: seconds)
                bumpOverlayAutoHide()
            }

            Text(formatTime(progressClock.durationSeconds))
                .font(YTLiteType.tabLabel.monospacedDigit())
                .foregroundStyle(YTLiteColor.onMedia)
                .frame(minWidth: 36, alignment: .trailing)
        }
    }

    private func overlayIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(YTLiteColor.onMedia)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func overlayPlainIcon(
        _ systemName: String,
        size: CGFloat = 18,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(YTLiteColor.onMedia)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bumpOverlayAutoHide() {
        hideTask?.cancel()
        guard playback.isPlaying, !playback.isBuffering else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: overlayAutoHideSeconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !playback.isBuffering else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    overlayVisible = false
                }
            }
        }
    }

    // MARK: - Metadata

    private var pinnedTitleRow: some View {
        HStack(spacing: YTLiteLayout.stackDefault) {
            Text(playback.nowPlaying?.title ?? "")
                .font(YTLiteType.rowTitle)
                .foregroundStyle(YTLiteColor.onSurface)
                .lineLimit(1)
            Spacer(minLength: YTLiteLayout.stackDefault)
            Button {
                if let item = playback.nowPlaying {
                    openTrackMenu(from: item)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var channelRow: some View {
        HStack(spacing: 10) {
            let canOpenChannel = playback.nowPlaying?.canSubscribeChannel == true
            Button {
                openChannelVideosIfPossible()
            } label: {
                HStack(spacing: 10) {
                    channelAvatar
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())

                    Text(playback.nowPlaying?.channelName ?? "")
                        .font(YTLiteType.body)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canOpenChannel)
            .opacity(canOpenChannel ? 1 : 0.55)

            Spacer(minLength: 8)

            let canSubscribe = canOpenChannel
            let subscribed = playback.isChannelSubscribed
            Button {
                guard canSubscribe else { return }
                let nowSubscribed = playback.toggleChannelSubscribe()
                showPlayerToast(nowSubscribed ? L("player.subscribed") : L("player.unsubscribed"))
            } label: {
                Text(subscribed ? L("player.subscribed") : L("player.subscribe"))
                    .font(YTLiteType.badge)
                    .foregroundStyle(subscribed ? YTLiteColor.onSurface : YTLiteColor.onMedia)
                    .padding(.horizontal, YTLiteLayout.stackLoose)
                    .padding(.vertical, 6)
                    .background(
                        subscribed ? YTLiteColor.surfaceVariant : YTLiteColor.accent,
                        in: Capsule()
                    )
                    .opacity(canSubscribe ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canSubscribe)
        }
        .task(id: playback.nowPlaying?.channelId) {
            await resolveChannelAvatarIfNeeded()
        }
    }

    private func openChannelVideosIfPossible() {
        guard let item = playback.nowPlaying,
              item.canSubscribeChannel,
              let channelId = item.channelId
        else { return }
        channelSheetItem = ChannelItem(
            channelId: channelId,
            title: item.channelName.isEmpty ? L("common.channel") : item.channelName,
            subtitle: L("common.channel"),
            thumbnailURL: item.channelAvatarURL ?? item.thumbnailURL
        )
    }

    @ViewBuilder
    private var channelAvatar: some View {
        if let url = playback.nowPlaying?.channelAvatarURL {
            RemoteImage(url: url)
        } else {
            ZStack {
                YTLiteColor.surfaceVariant
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
        }
    }

    private func resolveChannelAvatarIfNeeded() async {
        guard let channelId = playback.nowPlaying?.channelId,
              ChannelID.isBrowsable(channelId),
              playback.nowPlaying?.channelAvatarURL == nil
        else { return }
        if let stored = store?.subscribedChannel(id: channelId)?.avatarUrl.flatMap(URL.init(string:)) {
            playback.updateChannelAvatar(stored)
            return
        }
        let apiKey = appModel.config.catalogDataAPIKey
        if let url = await ChannelAvatarFetcher.fetch(channelId: channelId, apiKey: apiKey) {
            playback.updateChannelAvatar(url)
            if let channel = store?.subscribedChannel(id: channelId) {
                channel.avatarUrl = url.absoluteString
                store?.save()
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            actionItem(
                title: L("player.like"),
                icon: playback.isFavorite ? "hand.thumbsup.fill" : "hand.thumbsup",
                tint: playback.isFavorite ? YTLiteColor.accent : YTLiteColor.onSurface
            ) {
                playback.toggleFavorite()
                showPlayerToast(playback.isFavorite ? L("toast.liked") : L("toast.unliked"))
            }
            actionItem(
                title: L("player.dislike"),
                icon: playback.isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                tint: playback.isDisliked ? YTLiteColor.accent : YTLiteColor.onSurface
            ) {
                playback.toggleDislike()
                showPlayerToast(
                    playback.isDisliked ? L("toast.not_interested") : L("toast.remove_not_interested")
                )
            }
            actionItem(title: L("common.share"), icon: "arrowshape.turn.up.right") {
                if let item = playback.nowPlaying {
                    shareURL = item.watchShareURL
                    showShareSheet = true
                    showPlayerToast(L("toast.share_ready"))
                }
            }
            actionItem(title: L("common.save"), icon: "bookmark") {
                showAddPlaylist = true
            }
        }
        .padding(.vertical, YTLiteLayout.stackLoose)
        .background(
            YTLiteColor.surfaceVariant.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 28)
        )
    }

    private func actionItem(
        title: String,
        icon: String,
        tint: Color = YTLiteColor.onSurface,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).font(YTLiteType.iconCaption)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var transportControls: some View {
        HStack {
            Button {
                let enabled = playback.toggleShuffle()
                showPlayerToast(enabled ? L("toast.shuffle_on") : L("toast.shuffle_off"))
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(playback.shuffleEnabled ? YTLiteColor.accent : YTLiteColor.onSurface)
            }
            .accessibilityLabel(playback.shuffleEnabled ? L("toast.shuffle_on") : L("toast.shuffle_off"))
            Spacer()
            Button { playback.playPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundStyle(YTLiteColor.onSurface)
            }
            Spacer()
            Button { playback.togglePlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(YTLiteColor.onSurface)
                        .frame(width: 64, height: 64)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(YTLiteColor.background)
                        .offset(x: playback.isPlaying ? 0 : 2)
                }
            }
            Spacer()
            Button { playback.playNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundStyle(
                        playback.hasNextInQueue
                            ? YTLiteColor.onSurface
                            : YTLiteColor.onSurfaceVariant.opacity(0.45)
                    )
            }
            .disabled(!playback.hasNextInQueue)
            Spacer()
            Button {
                let mode = playback.cycleRepeatMode()
                showPlayerToast(repeatModeToast(mode))
            } label: {
                Image(systemName: playback.repeatMode.systemImage)
                    .font(.title3)
                    .foregroundStyle(playback.repeatMode.isActive ? YTLiteColor.accent : YTLiteColor.onSurface)
            }
            .accessibilityLabel(repeatAccessibilityLabel)
        }
        .buttonStyle(.plain)
        .padding(.vertical, YTLiteLayout.stackTight)
    }

    private func repeatModeToast(_ mode: QueueRepeatMode) -> String {
        switch mode {
        case .off: return L("toast.repeat_off")
        case .all: return L("toast.repeat_all")
        case .one: return L("toast.repeat_one")
        }
    }

    private var repeatAccessibilityLabel: String {
        switch playback.repeatMode {
        case .off: return L("toast.repeat_off")
        case .all: return L("toast.repeat_all")
        case .one: return L("toast.repeat_one")
        }
    }

    // MARK: - Tabs

    private var tabHeader: some View {
        HStack(spacing: YTLiteLayout.stackDefault) {
            ForEach(PlayerTab.allCases, id: \.self) { item in
                YTLiteChip(title: item.title, selected: tab == item) {
                    tab = item
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var listToolbar: some View {
        HStack(spacing: 10) {
            Text(toolbarTitle)
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Spacer()
            toolbarCircleButton(
                systemName: "arrow.up.arrow.down",
                filledAccent: false,
                enabled: !currentListItems.isEmpty
            ) {
                showSortMenu = true
            }
            toolbarCircleButton(
                systemName: "checkmark.circle",
                filledAccent: false,
                enabled: !currentListItems.isEmpty
            ) {
                enterSelectionMode()
            }
            toolbarCircleButton(
                systemName: "plus",
                filledAccent: true,
                enabled: canSaveList
            ) {
                showSaveList = true
            }
        }
    }

    private func toolbarCircleButton(
        systemName: String,
        filledAccent: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(
                    filledAccent
                        ? (enabled ? YTLiteColor.onSurface : YTLiteColor.onSurface.opacity(0.35))
                        : (enabled ? YTLiteColor.onSurface : YTLiteColor.onSurface.opacity(0.35))
                )
                .frame(width: 36, height: 36)
                .background(
                    filledAccent
                        ? (enabled ? YTLiteColor.accent : YTLiteColor.surfaceVariant)
                        : YTLiteColor.surfaceVariant,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || filledAccent ? 1 : 0.55)
    }

    private var selectionToolbar: some View {
        HStack(spacing: 8) {
            Button {
                exitSelectionMode()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .frame(width: 36, height: 36)
                    .background(YTLiteColor.surfaceVariant, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Text(Lf("common.n_selected", selectedIds.count))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            // Match Android Library selection TopAppBar: icon-only actions.
            Button {
                selectedIds = Set(currentListItems.map(\.videoId))
            } label: {
                Image(systemName: "checklist")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(allSelected ? YTLiteColor.onSurface.opacity(0.35) : YTLiteColor.onSurface)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(allSelected)
            .accessibilityLabel(L("common.select_all"))

            Button {
                selectedIds.removeAll()
            } label: {
                Image(systemName: "checklist.unchecked")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selectedIds.isEmpty ? YTLiteColor.onSurface.opacity(0.35) : YTLiteColor.onSurface)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selectedIds.isEmpty)
            .accessibilityLabel(L("common.deselect_all"))

            Button {
                showBatchAdd = true
            } label: {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selectedIds.isEmpty ? YTLiteColor.onSurface.opacity(0.35) : YTLiteColor.onSurface)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selectedIds.isEmpty)
            .accessibilityLabel(L("player.add_to_playlist"))

            if tab == .upNext {
                Button {
                    playback.removeFromQueue(videoIds: selectedIds)
                    exitSelectionMode()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selectedIds.isEmpty ? YTLiteColor.onSurface.opacity(0.35) : YTLiteColor.onSurface)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selectedIds.isEmpty)
                .accessibilityLabel(L("player.remove_from_queue"))
            }
        }
    }

    private var allSelected: Bool {
        let ids = currentListItems.map(\.videoId)
        return !ids.isEmpty && ids.allSatisfy { selectedIds.contains($0) }
    }

    private var toolbarTitle: String {
        switch tab {
        case .upNext: return "\(playback.queue.count) Songs"
        case .related: return relatedLoading ? "Loading…" : "\(related.count) videos"
        }
    }

    private var canSaveList: Bool { !playlistSaveItems.isEmpty }

    private var currentListItems: [VideoItem] {
        switch tab {
        case .upNext: return playback.queue
        case .related: return related
        }
    }

    /// Items written when saving the whole list — Related includes the current track (excluded from UI list).
    private var playlistSaveItems: [VideoItem] {
        var items = currentListItems
        if tab == .related, let current = currentTrackItems.first,
           !items.contains(where: { $0.videoId == current.videoId }) {
            items.insert(current, at: 0)
        }
        return items
    }

    private var currentTrackItems: [VideoItem] {
        guard let item = playback.nowPlaying else { return [] }
        return [
            VideoItem(
                videoId: item.videoId,
                title: item.title,
                channelName: item.channelName,
                thumbnailURL: item.thumbnailURL,
                durationText: item.durationText
            ),
        ]
    }

    private var selectedListItems: [VideoItem] {
        currentListItems.filter { selectedIds.contains($0.videoId) }
    }

    private var selectedPlaylistSaveItems: [VideoItem] {
        var items = selectedListItems
        if tab == .related, let current = currentTrackItems.first,
           !items.contains(where: { $0.videoId == current.videoId }) {
            items.insert(current, at: 0)
        }
        return items
    }

    private func openTrackMenu(from item: NowPlayingItem) {
        openTrackMenu(
            VideoItem(
                videoId: item.videoId,
                title: item.title,
                channelName: item.channelName,
                thumbnailURL: item.thumbnailURL,
                durationText: item.durationText
            ),
            canRemoveFromQueue: false
        )
    }

    private func openTrackMenu(_ item: VideoItem, canRemoveFromQueue: Bool? = nil) {
        let ctx = TrackActionContext(
            item: item,
            canRemoveFromQueue: canRemoveFromQueue ?? (tab == .upNext)
        )
        trackActions.context = ctx
        playerTrackMenu = ctx
    }

    private func loadRelated() async {
        guard let videoId = playback.nowPlaying?.videoId, !videoId.isEmpty else { return }
        relatedLoading = true
        relatedError = nil
        defer { relatedLoading = false }
        do {
            let results = try await InnerTubeClient.fetchMusicRelatedVideos(videoId: videoId)
            // Drop stale results if the user already switched tracks.
            guard playback.nowPlaying?.videoId == videoId else { return }
            let items = store?.filterNotInterested(results) ?? results
            relatedOriginal = items
            related = sortedItems(items, by: listSort)
            relatedVersion &+= 1
            relatedSourceVideoId = videoId
        } catch {
            guard playback.nowPlaying?.videoId == videoId else { return }
            relatedError = error.localizedDescription
            relatedSourceVideoId = nil
        }
    }

    /// After resolve/open (`!isBuffering`), clear the previous Related list and fetch for the new track.
    private func scheduleRelatedLoadIfNeeded() {
        guard tab == .related else { return }
        guard let videoId = playback.nowPlaying?.videoId, !videoId.isEmpty else { return }
        guard !playback.isBuffering else { return }
        guard !relatedLoading else { return }
        guard relatedSourceVideoId != videoId else { return }

        related = []
        relatedOriginal = []
        relatedVersion &+= 1
        relatedError = nil
        relatedSourceVideoId = nil
        Task { await loadRelated() }
    }

    private func enterSelectionMode() {
        guard !currentListItems.isEmpty else { return }
        isSelectionMode = true
        selectedIds = []
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedIds = []
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    /// Related rows are reused by video id. Resolve the tapped id against the
    /// current list so a sort cannot start the track that used to sit at that offset.
    private func playRelated(videoId: String) {
        guard let index = related.firstIndex(where: { $0.videoId == videoId }) else { return }
        playback.play(items: related, startAt: index, analyticsSource: "related")
        AppAnalytics.relatedTap()
    }

    private func applySort(_ sort: PlayerListSort) {
        listSort = sort
        switch tab {
        case .upNext:
            if sort == .original {
                // Keep current queue order for Up next "original" (no pre-shuffle snapshot).
                return
            }
            playback.reorderQueue { a, b in compare(a, b, sort: sort) }
        case .related:
            related = sortedItems(relatedOriginal, by: sort)
            relatedVersion &+= 1
        }
    }

    private func sortedItems(_ items: [VideoItem], by sort: PlayerListSort) -> [VideoItem] {
        guard sort != .original else { return items }
        return items.sorted { compare($0, $1, sort: sort) }
    }

    private func compare(_ a: VideoItem, _ b: VideoItem, sort: PlayerListSort) -> Bool {
        switch sort {
        case .original:
            return true
        case .titleAsc:
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        case .titleDesc:
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedDescending
        case .artistAsc:
            return a.channelName.localizedCaseInsensitiveCompare(b.channelName) == .orderedAscending
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Subviews

private struct OrangeProgressBar: View {
    let value: Double
    let total: Double
    var trackColor: Color = YTLiteColor.onSurface.opacity(0.35)
    var onSeek: (Double) -> Void

    @State private var dragFraction: CGFloat?

    private var fraction: CGFloat {
        if let dragFraction { return dragFraction }
        guard total > 0 else { return 0 }
        return CGFloat(value / total).clamped(to: 0...1)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumb: CGFloat = 10
            let trackH: CGFloat = 3
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                    .frame(height: trackH)
                Capsule()
                    .fill(YTLiteColor.accent)
                    .frame(width: max(0, width * fraction), height: trackH)
                Circle()
                    .fill(YTLiteColor.accent)
                    .frame(width: thumb, height: thumb)
                    .offset(x: (width * fraction - thumb / 2).clamped(to: 0...(width - thumb)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            // Beat parent canvas dismiss drag so scrubbing always receives the gesture.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        // Preview only while dragging — seeking on every move floods
                        // AVPlayer and leaves currentTime stuck behind the scrub target.
                        let f = CGFloat(drag.location.x / max(width, 1)).clamped(to: 0...1)
                        dragFraction = f
                    }
                    .onEnded { drag in
                        let f = Double(drag.location.x / max(width, 1)).clamped(to: 0...1)
                        // Seek first so `value` already reflects the target when preview clears.
                        onSeek(f * total)
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 28)
    }
}

/// Applies `highPriorityGesture` only when `enabled` — avoids stealing child drags.
private struct OptionalHighPriorityDrag<G: Gesture>: ViewModifier {
    let enabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

private struct PlayerQueueTabPane: View, Equatable {
    let token: Int
    let tab: PlayerTab
    let queue: [VideoItem]
    let queueIndex: Int
    let related: [VideoItem]
    let relatedLoading: Bool
    let relatedError: String?
    let isSelectionMode: Bool
    let selectedIds: Set<String>
    let onSelectQueueVideoId: (String) -> Void
    let onToggleSelection: (String) -> Void
    let onPlayRelatedVideoId: (String) -> Void
    let onRetryRelated: () -> Void
    let onOpenTrackMenu: (VideoItem) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.token == rhs.token
    }

    var body: some View {
        switch tab {
        case .upNext:
            // LazyVStack parent already virtualizes; Equatable rows skip non-current rebuilds.
            ForEach(Array(queue.enumerated()), id: \.element.videoId) { index, item in
                PlayerQueueRowView(
                    item: item,
                    index: index,
                    isCurrent: index == queueIndex,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedIds.contains(item.videoId),
                    onSelect: {
                        if isSelectionMode {
                            onToggleSelection(item.videoId)
                        } else {
                            onSelectQueueVideoId(item.videoId)
                        }
                    },
                    onMore: { onOpenTrackMenu(item) }
                )
                    .equatable()
            }
            if !queue.isEmpty {
                queueEndCaption(L("player.list_end"))
            }
        case .related:
            if relatedLoading && related.isEmpty {
                ProgressView()
                    .tint(YTLiteColor.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, YTLiteLayout.sectionGap)
            } else if let relatedError, related.isEmpty {
                VStack(spacing: YTLiteLayout.stackLoose) {
                    Text(relatedError)
                        .font(YTLiteType.body)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Button(action: onRetryRelated) {
                        Text(L("common.retry"))
                            .font(YTLiteType.body.weight(.semibold))
                            .foregroundStyle(YTLiteColor.accent)
                            .padding(.horizontal, YTLiteLayout.stackLoose)
                            .padding(.vertical, YTLiteLayout.rowVertical)
                            .background(YTLiteColor.surfaceVariant, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, YTLiteLayout.screenPadding)
                .padding(.horizontal, YTLiteLayout.screenPadding)
            } else if related.isEmpty {
                Text(L("player.no_related"))
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .padding(.vertical, YTLiteLayout.screenPadding)
            } else {
                ForEach(Array(related.enumerated()), id: \.element.videoId) { index, item in
                    PlayerQueueRowView(
                        item: item,
                        index: index,
                        isCurrent: false,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedIds.contains(item.videoId),
                        onSelect: {
                            if isSelectionMode {
                                onToggleSelection(item.videoId)
                            } else {
                                onPlayRelatedVideoId(item.videoId)
                            }
                        },
                        onMore: { onOpenTrackMenu(item) }
                    )
                    .equatable()
                }
                queueEndCaption(L("player.list_end"))
            }
        }
    }

    private func queueEndCaption(_ text: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(YTLiteColor.onSurfaceVariant.opacity(0.35))
                .frame(height: 1)
            Text(text)
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Rectangle()
                .fill(YTLiteColor.onSurfaceVariant.opacity(0.35))
                .frame(height: 1)
        }
        .padding(.top, YTLiteLayout.stackLoose)
        .padding(.bottom, YTLiteLayout.sectionGap)
    }
}

/// Equatable Up Next / Related row — only the current + previous current rows rebuild on skip.
/// `index` is part of equality so a shuffle/append that moves the row refreshes its tap
/// closure. The closure itself plays `item.videoId`, not the captured offset.
private struct PlayerQueueRowView: View, Equatable {
    let item: VideoItem
    let index: Int
    let isCurrent: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onMore: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index
            && lhs.item.videoId == rhs.item.videoId
            && lhs.item.title == rhs.item.title
            && lhs.item.channelName == rhs.item.channelName
            && lhs.item.durationText == rhs.item.durationText
            && lhs.item.thumbnailURL == rhs.item.thumbnailURL
            && lhs.isCurrent == rhs.isCurrent
            && lhs.isSelectionMode == rhs.isSelectionMode
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        HStack(spacing: YTLiteLayout.stackLoose) {
            if isSelectionMode {
                Button(action: onSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? YTLiteColor.accent : YTLiteColor.onSurfaceVariant)
                        .frame(width: 28, height: 56)
                }
                .buttonStyle(.plain)
            }
            Button(action: onSelect) {
                HStack(spacing: YTLiteLayout.stackLoose) {
                    VideoThumbnail(
                        url: item.thumbnailURL,
                        durationText: item.durationText,
                        width: 56,
                        height: 56,
                        cornerRadius: 6,
                        badgePadding: 2
                    )

                    VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                        Text(item.title)
                            .font(YTLiteType.rowTitle)
                            .foregroundStyle(isCurrent ? YTLiteColor.accent : YTLiteColor.onSurface)
                            .lineLimit(1)
                        Text(item.channelName)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isSelectionMode {
                Button(action: onMore) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(width: 36, height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, YTLiteLayout.stackDefault)
        .padding(.vertical, YTLiteLayout.rowVertical)
        .background(
            isCurrent
                ? YTLiteColor.accent.opacity(0.14)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: YTLiteLayout.thumbRadius)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension NowPlayingItem {
    var watchShareURL: URL {
        URL(string: CatalogURL.watchURL(videoId: videoId))!
    }
}

/// System share sheet (`UIActivityViewController`) — reliable inside presented sheets
/// where SwiftUI `ShareLink` often fails to present.
struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad requires a popover source; anchor to the key window center.
        if let popover = controller.popoverPresentationController {
            let anchor = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            popover.sourceView = anchor
            popover.sourceRect = anchor.map {
                CGRect(x: $0.bounds.midX, y: $0.bounds.midY, width: 1, height: 1)
            } ?? .zero
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
                                ? Lf("player.normal_speed", PlaybackSpeeds.formatLabel(speed))
                                : PlaybackSpeeds.formatLabel(speed)
                        )
                        .foregroundStyle(YTLiteColor.onSurface)
                        Spacer()
                        if abs(speed - selected) < 0.001 {
                            Image(systemName: "checkmark")
                                .foregroundStyle(YTLiteColor.accent)
                        }
                    }
                }
                .listRowBackground(YTLiteColor.surfaceElevated)
            }
            .scrollContentBackground(.hidden)
            .background(YTLiteColor.surfaceElevated)
            .navigationTitle(L("player.playback_speed"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
            }
        }
    }
}

struct HLSQualityPickerSheet: View {
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if playback.hlsVariantsLoadFailed {
                    Text(L("player.quality.load_failed"))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.danger)
                        .listRowBackground(YTLiteColor.surfaceElevated)
                }
                qualityRow(id: nil, title: L("player.quality.auto"))
                ForEach(playback.hlsVariants) { variant in
                    qualityRow(id: variant.id, title: variant.displayLabel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(YTLiteColor.surfaceElevated)
            .navigationTitle(L("player.quality"))
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if playback.isLoadingHLSVariants && playback.hlsVariants.isEmpty {
                    ProgressView()
                        .tint(YTLiteColor.accent)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
            }
        }
    }

    private func qualityRow(id: String?, title: String) -> some View {
        Button {
            playback.selectHLSVariant(id)
            dismiss()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(YTLiteColor.onSurface)
                Spacer()
                if playback.selectedHLSVariantID == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(YTLiteColor.accent)
                }
            }
        }
        .listRowBackground(YTLiteColor.surfaceElevated)
    }
}

struct SleepTimerSheet: View {
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    private var options: [Int?] { [nil] + SleepTimerOptions.minutesOptions.map { Optional($0) } }

    var body: some View {
        NavigationStack {
            List(options, id: \.self) { minutes in
                Button {
                    playback.setSleepTimer(minutes: minutes)
                    dismiss()
                } label: {
                    HStack {
                        Text(SleepTimerOptions.formatLabel(minutes: minutes))
                            .foregroundStyle(YTLiteColor.onSurface)
                        Spacer()
                        if minutes == playback.sleepTimerMinutes {
                            Image(systemName: "checkmark")
                                .foregroundStyle(YTLiteColor.accent)
                        }
                    }
                }
                .listRowBackground(YTLiteColor.surfaceElevated)
            }
            .scrollContentBackground(.hidden)
            .background(YTLiteColor.surfaceElevated)
            .navigationTitle(L("player.sleep_timer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
            }
        }
    }
}

private struct PlayerListSortSheet: View {
    let selected: PlayerListSort
    var onSelect: (PlayerListSort) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: L("library.sort_by"))
            Divider().overlay(YTLiteColor.surfaceVariant)

            ForEach(PlayerListSort.allCases, id: \.self) { option in
                YTLiteSheetActionRow(
                    systemImage: "arrow.up.arrow.down",
                    title: option.title,
                    isSelected: option == selected
                ) {
                    onSelect(option)
                    dismiss()
                }
            }
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(YTLiteColor.surfaceElevated)
    }
}

struct AddToPlaylistSheet: View {
    var items: [VideoItem]
    /// Batch selection from player — first row adds to Up next only (no Library mutation).
    var offersCurrentQueue: Bool = false
    var onDone: (() -> Void)? = nil

    @Environment(\.libraryStore) private var store
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    /// Inline create form (avoid nested sheet + keyboard dismissing the player stack on device).
    @State private var showCreate = false
    @State private var newName = ""

    private var title: String {
        items.count > 1 ? Lf("common.n_songs", items.count) : L("library.save_to")
    }

    var body: some View {
        Group {
            if showCreate {
                createPlaylistContent
            } else {
                playlistPickerContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(YTLiteColor.surfaceElevated)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(YTLiteColor.surfaceElevated)
        .interactiveDismissDisabled(showCreate)
    }

    private var playlistPickerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: title)
            Divider().overlay(YTLiteColor.surfaceVariant)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if offersCurrentQueue {
                        YTLiteSheetActionRow(
                            systemImage: "text.append",
                            title: L("player.add_to_current_queue")
                        ) {
                            addToCurrentQueue()
                        }
                    }
                    ForEach(store?.allPlaylists() ?? [], id: \.playlistId) { playlist in
                        YTLiteSheetActionRow(
                            systemImage: playlistRowIcon(for: playlist),
                            title: displayName(playlist)
                        ) {
                            save(to: playlist)
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            YTLiteSheetPrimaryButton(title: L("player.new_playlist")) {
                newName = ""
                showCreate = true
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private var createPlaylistContent: some View {
        VStack(spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: L("player.new_playlist"))

            Text(L("common.name"))
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.bottom, 6)

            YTLiteSheetField(placeholder: L("common.name"), text: $newName)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                YTLiteSheetPrimaryButton(
                    title: L("common.create"),
                    enabled: !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, let store else { return }
                    let playlist = store.createPlaylist(name: name)
                    showCreate = false
                    save(to: playlist)
                }
                YTLiteSheetSecondaryButton(title: L("common.cancel")) {
                    newName = ""
                    showCreate = false
                }
            }
            .padding(.bottom, 28)
        }
    }

    private func addToCurrentQueue() {
        // Up next only — never writes Library playlists / SwiftData.
        playback.appendToQueue(items)
        trackActions.showToast(L("toast.added_to_queue"))
        onDone?()
        dismiss()
    }

    private func save(to playlist: LibraryPlaylist) {
        guard let store else { return }
        for item in items {
            store.add(item: item, to: playlist)
        }
        trackActions.notifyListsChanged()
        let name = displayName(playlist)
        trackActions.completePlaylistSave(toast: Lf("toast.saved_to", name))
        onDone?()
        dismiss()
    }

    private func displayName(_ playlist: LibraryPlaylist) -> String {
        switch playlist.systemType {
        case SystemPlaylistType.favorites: return L("library.liked")
        case SystemPlaylistType.watchLater: return L("library.watch_later")
        default: return playlist.name
        }
    }

    private func playlistRowIcon(for playlist: LibraryPlaylist) -> String {
        switch playlist.systemType {
        case SystemPlaylistType.favorites: return "hand.thumbsup"
        case SystemPlaylistType.watchLater: return "clock"
        default: return "music.note.list"
        }
    }
}
