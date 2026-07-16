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

struct PlayerDetailView: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showSpeedSheet = false
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
    @State private var relatedLoading = false
    @State private var relatedError: String?
    @State private var subscribeToast: String?

    @State private var showSortMenu = false
    @State private var listSort: PlayerListSort = .original
    @State private var isSelectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var showBatchAdd = false
    /// Local rich-menu presentation — must be on this sheet, not Root's TrackActionHost.
    @State private var playerTrackMenu: TrackActionContext?

    private let overlayAutoHideSeconds: UInt64 = 5_000_000_000

    var body: some View {
        VStack(spacing: 0) {
            playerCanvas
            // Title + more stay pinned under the canvas while the rest scrolls (matches player detail UX).
            pinnedTitleRow
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.top, YTLiteLayout.stackLoose)
                .padding(.bottom, YTLiteLayout.stackDefault)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(YTLiteColor.surface)
            ScrollView {
                VStack(alignment: .leading, spacing: YTLiteLayout.screenPadding) {
                    channelRow
                    if let error = playback.lastError, !playback.isPlaying {
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
                    tabContent
                }
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.top, YTLiteLayout.stackDefault)
                .padding(.bottom, 32)
            }
        }
        .background(YTLiteColor.surface.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showSpeedSheet) {
            SpeedPickerSheet(selected: $playback.playbackSpeed)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
                .environmentObject(playback)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareURL = nil }) {
            if let shareURL {
                SystemShareSheet(items: [shareURL])
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showAddPlaylist) {
            AddToPlaylistSheet(items: currentTrackItems)
        }
        .sheet(isPresented: $showSaveList) {
            AddToPlaylistSheet(items: currentListItems)
        }
        .sheet(isPresented: $showBatchAdd) {
            AddToPlaylistSheet(items: selectedListItems) {
                exitSelectionMode()
            }
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
        }
        .onAppear {
            playback.libraryStore = store ?? playback.libraryStore
            playback.refreshFavoriteState()
            bumpOverlayAutoHide()
        }
        .onChange(of: playback.isPlaying) { _, playing in
            if playing { bumpOverlayAutoHide() }
        }
        .onChange(of: playback.nowPlaying?.videoId) { _, _ in
            related = []
            relatedOriginal = []
            listSort = .original
            exitSelectionMode()
            if tab == .related {
                Task { await loadRelated() }
            }
        }
        .onChange(of: tab) { _, newValue in
            exitSelectionMode()
            listSort = .original
            if newValue == .related, related.isEmpty {
                Task { await loadRelated() }
            }
        }
        .onChange(of: trackActions.menuCloseToken) { _, _ in
            playerTrackMenu = nil
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
                    playbackSpeed: playback.playbackSpeed
                )
                .allowsHitTesting(false)
            } else if let url = playback.nowPlaying?.thumbnailURL {
                RemoteImage(url: url, contentMode: .fit)
            }

            if playback.isBuffering {
                ProgressView()
                    .tint(YTLiteColor.onSurface)
                    .padding(YTLiteLayout.screenPadding)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: YTLiteLayout.stackLoose))
            }

            // Tap catcher under overlay so control buttons keep priority.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleOverlay() }

            if overlayVisible {
                canvasOverlay
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
    }

    private func toggleOverlay() {
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

                overlayProgress
                    .padding(.horizontal, YTLiteLayout.stackLoose)
                    .padding(.bottom, 10)
            }
        }
    }

    private var overlayTopBar: some View {
        HStack(spacing: YTLiteLayout.stackDefault) {
            overlayIconButton(systemName: "chevron.down") {
                dismiss()
            }
            Spacer()
            HStack(spacing: 0) {
                Button {
                    showSleepTimerSheet = true
                    bumpOverlayAutoHide()
                } label: {
                    Group {
                        if let remaining = playback.sleepTimerRemaining,
                           playback.sleepTimerEndsAt != nil
                        {
                            Text(SleepTimerOptions.formatRemaining(remaining))
                                .font(YTLiteType.badge)
                                .foregroundStyle(YTLiteColor.accent)
                                .frame(minWidth: 36)
                                .padding(.horizontal, 10)
                                .padding(.vertical, YTLiteLayout.rowVertical)
                        } else {
                            Image(systemName: "moon.zzz")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(YTLiteColor.onSurface)
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
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(minWidth: 36)
                        .padding(.horizontal, 10)
                        .padding(.vertical, YTLiteLayout.rowVertical)
                }
                .buttonStyle(.plain)

                overlayPlainIcon("pip.enter") {
                    pipRequestID += 1
                    bumpOverlayAutoHide()
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
        HStack(spacing: YTLiteLayout.stackDefault) {
            overlayPlainIcon("backward.fill", size: 22) {
                playback.playPrevious()
                bumpOverlayAutoHide()
            }
            overlayPlainIcon(playback.isPlaying ? "pause.fill" : "play.fill", size: 26) {
                playback.togglePlayPause()
                bumpOverlayAutoHide()
            }
            overlayPlainIcon("forward.fill", size: 22) {
                playback.playNext()
                bumpOverlayAutoHide()
            }
        }
        .padding(.horizontal, YTLiteLayout.stackDefault)
        .padding(.vertical, YTLiteLayout.stackTight)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
    }

    private var overlayProgress: some View {
        HStack(spacing: 10) {
            Text(formatTime(playback.positionSeconds))
                .font(YTLiteType.tabLabel.monospacedDigit())
                .foregroundStyle(YTLiteColor.onSurface)
                .frame(minWidth: 36, alignment: .leading)

            OrangeProgressBar(
                value: playback.positionSeconds,
                total: max(playback.durationSeconds, 1)
            ) { seconds in
                playback.seek(to: seconds)
                bumpOverlayAutoHide()
            }

            Text(formatTime(playback.durationSeconds))
                .font(YTLiteType.tabLabel.monospacedDigit())
                .foregroundStyle(YTLiteColor.onSurface)
                .frame(minWidth: 36, alignment: .trailing)
        }
    }

    private func overlayIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(YTLiteColor.onSurface)
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
                .foregroundStyle(YTLiteColor.onSurface)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bumpOverlayAutoHide() {
        hideTask?.cancel()
        guard playback.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: overlayAutoHideSeconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
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
            channelAvatar
                .frame(width: 28, height: 28)
                .clipShape(Circle())

            Text(playback.nowPlaying?.channelName ?? "")
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .lineLimit(1)

            Spacer(minLength: 8)

            let canSubscribe = playback.nowPlaying?.canSubscribeChannel == true
            let subscribed = playback.isChannelSubscribed
            Button {
                guard canSubscribe else { return }
                let nowSubscribed = playback.toggleChannelSubscribe()
                subscribeToast = nowSubscribed ? L("player.subscribed") : L("player.unsubscribed")
            } label: {
                Text(subscribed ? L("player.subscribed") : L("player.subscribe"))
                    .font(YTLiteType.badge)
                    .foregroundStyle(subscribed ? YTLiteColor.onSurfaceVariant : YTLiteColor.onSurface)
                    .padding(.horizontal, YTLiteLayout.stackLoose)
                    .padding(.vertical, 6)
                    .background(
                        subscribed ? YTLiteColor.surfaceVariant : YTLiteColor.surfaceElevated,
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            subscribed ? Color.clear : YTLiteColor.chromeDivider,
                            lineWidth: 1
                        )
                    )
                    .opacity(canSubscribe ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canSubscribe)
        }
        .task(id: playback.nowPlaying?.channelId) {
            await resolveChannelAvatarIfNeeded()
        }
        .overlay(alignment: .bottom) {
            if let subscribeToast {
                Text(subscribeToast)
                    .font(YTLiteType.meta.weight(.semibold))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(YTLiteColor.surfaceElevated, in: Capsule())
                    .offset(y: 36)
                    .transition(.opacity)
                    .task(id: subscribeToast) {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        self.subscribeToast = nil
                    }
            }
        }
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
        if let cached = store?.subscribedChannel(id: channelId)?.avatarUrl.flatMap(URL.init(string:)) {
            playback.updateChannelAvatar(cached)
            return
        }
        let apiKey = appModel.config.youtubeDataAPIKey
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
            }
            actionItem(
                title: L("player.dislike"),
                icon: playback.isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                tint: playback.isDisliked ? YTLiteColor.accent : YTLiteColor.onSurface
            ) {
                playback.toggleDislike()
            }
            actionItem(title: L("common.share"), icon: "arrowshape.turn.up.right") {
                if let item = playback.nowPlaying {
                    shareURL = item.watchShareURL
                    showShareSheet = true
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
                playback.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(playback.shuffleEnabled ? YTLiteColor.accent : YTLiteColor.onSurface)
            }
            .accessibilityLabel(playback.shuffleEnabled ? "Shuffle on" : "Sequential")
            Spacer()
            Button { playback.playPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundStyle(YTLiteColor.onSurface)
            }
            Spacer()
            Button { playback.togglePlayPause() } label: {
                ZStack {
                    Circle().fill(Color.white).frame(width: 64, height: 64)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(YTLiteColor.surface)
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
                playback.cycleRepeatMode()
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

    private var repeatAccessibilityLabel: String {
        switch playback.repeatMode {
        case .off: return "Repeat off"
        case .all: return "Repeat all"
        case .one: return "Repeat one"
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

    private var canSaveList: Bool { !currentListItems.isEmpty }

    private var currentListItems: [VideoItem] {
        switch tab {
        case .upNext: return playback.queue
        case .related: return related
        }
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

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .upNext:
            ForEach(Array(playback.queue.enumerated()), id: \.element.id) { index, item in
                listRow(item: item, isCurrent: index == playback.queueIndex) {
                    if isSelectionMode {
                        toggleSelection(item.videoId)
                    } else {
                        playback.play(items: playback.queue, startAt: index)
                    }
                }
            }
        case .related:
            if relatedLoading && related.isEmpty {
                ProgressView()
                    .tint(YTLiteColor.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, YTLiteLayout.sectionGap)
            } else if let relatedError, related.isEmpty {
                Text(relatedError)
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .padding(.vertical, YTLiteLayout.screenPadding)
            } else if related.isEmpty {
                Text(L("player.no_related"))
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .padding(.vertical, YTLiteLayout.screenPadding)
            } else {
                ForEach(Array(related.enumerated()), id: \.element.id) { index, item in
                    listRow(item: item, isCurrent: false) {
                        if isSelectionMode {
                            toggleSelection(item.videoId)
                        } else {
                            playback.play(items: related, startAt: index)
                        }
                    }
                }
            }
        }
    }

    private func listRow(item: VideoItem, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        let selected = selectedIds.contains(item.videoId)
        return HStack(spacing: YTLiteLayout.stackLoose) {
            if isSelectionMode {
                Button(action: action) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? YTLiteColor.accent : YTLiteColor.onSurfaceVariant)
                        .frame(width: 28, height: 56)
                }
                .buttonStyle(.plain)
            }
            Button(action: action) {
                UpNextRowContent(item: item, isCurrent: isCurrent)
            }
            .buttonStyle(.plain)
            if !isSelectionMode {
                Button {
                    openTrackMenu(item)
                } label: {
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

    private func openTrackMenu(from item: NowPlayingItem) {
        openTrackMenu(
            VideoItem(
                videoId: item.videoId,
                title: item.title,
                channelName: item.channelName,
                thumbnailURL: item.thumbnailURL,
                durationText: item.durationText
            )
        )
    }

    private func openTrackMenu(_ item: VideoItem) {
        let ctx = TrackActionContext(item: item)
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
            let items = store?.filterNotInterested(results) ?? results
            relatedOriginal = items
            related = sortedItems(items, by: listSort)
        } catch {
            relatedError = error.localizedDescription
        }
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
    var onSeek: (Double) -> Void

    private var fraction: CGFloat {
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
                    .fill(YTLiteColor.onSurface.opacity(0.35))
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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let f = Double(drag.location.x / max(width, 1)).clamped(to: 0...1)
                        onSeek(f * total)
                    }
            )
        }
        .frame(height: 20)
    }
}

private struct UpNextRowContent: View {
    let item: VideoItem
    let isCurrent: Bool

    var body: some View {
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
}

private struct UpNextRow: View {
    let item: VideoItem
    let isCurrent: Bool
    var onMore: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            UpNextRowContent(item: item, isCurrent: isCurrent)
            if let onMore {
                Button(action: onMore) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
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
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }
}

/// System share sheet (`UIActivityViewController`) — reliable inside presented sheets
/// where SwiftUI `ShareLink` often fails to present.
struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad requires a popover anchor; approximate to avoid crash.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView()
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
            .background(YTLiteColor.background)
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
            .background(YTLiteColor.background)
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
    var onDone: (() -> Void)? = nil

    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showCreate = false
    @State private var newName = ""

    private var title: String {
        items.count > 1 ? Lf("common.n_songs", items.count) : L("library.save_to")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: title)
            Divider().overlay(YTLiteColor.surfaceVariant)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(YTLiteColor.surfaceElevated)
        .sheet(isPresented: $showCreate) {
            createPlaylistSheet
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(YTLiteColor.surfaceElevated)
    }

    private var createPlaylistSheet: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(YTLiteColor.surfaceElevated)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(YTLiteColor.surfaceElevated)
    }

    private func save(to playlist: LibraryPlaylist) {
        guard let store else { return }
        for item in items {
            store.add(item: item, to: playlist)
        }
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
