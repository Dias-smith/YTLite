import SwiftUI
import AVKit

private enum PlayerTab: String, CaseIterable {
    case upNext = "Up next"
    case lyrics = "Lyrics"
    case related = "Related"
}

struct PlayerDetailView: View {
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showSpeedSheet = false
    @State private var showAddPlaylist = false
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var shuffleOn = false
    @State private var repeatOn = false
    @State private var tab: PlayerTab = .upNext
    @State private var pipRequestID = 0
    @State private var fullscreenRequestID = 0
    @State private var related: [VideoItem] = []
    @State private var relatedLoading = false
    @State private var relatedError: String?

    private let overlayAutoHideSeconds: UInt64 = 5_000_000_000

    var body: some View {
        VStack(spacing: 0) {
            playerCanvas
            ScrollView {
                VStack(alignment: .leading, spacing: YTLiteLayout.screenPadding) {
                    titleBlock
                    if let error = playback.lastError {
                        Text(error)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.danger)
                    }
                    actionBar
                    transportControls
                    tabHeader
                    listToolbar
                    tabContent
                }
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.top, YTLiteLayout.stackLoose)
                .padding(.bottom, 32)
            }
        }
        .background(YTLiteColor.surface.ignoresSafeArea())
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSpeedSheet) {
            SpeedPickerSheet(selected: $playback.playbackSpeed)
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAddPlaylist) {
            AddToPlaylistSheet()
                .preferredColorScheme(.dark)
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
            if tab == .related {
                Task { await loadRelated() }
            }
        }
        .onChange(of: tab) { _, newValue in
            if newValue == .related, related.isEmpty {
                Task { await loadRelated() }
            }
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
                    fullscreenRequestID: fullscreenRequestID
                )
                .allowsHitTesting(false)
            } else if let url = playback.nowPlaying?.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        YTLiteColor.surfaceVariant
                    }
                }
            }

            if playback.isBuffering {
                ProgressView("Extracting…")
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

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: YTLiteLayout.stackDefault) {
            HStack(spacing: YTLiteLayout.stackDefault) {
                Text(playback.nowPlaying?.title ?? "")
                    .font(YTLiteType.rowTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)
                Spacer(minLength: YTLiteLayout.stackDefault)
                Image(systemName: "ellipsis")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
            HStack(spacing: 10) {
                Text(playback.nowPlaying?.channelName ?? "")
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
                Text("Subscribe")
                    .font(YTLiteType.badge)
                    .foregroundStyle(.black)
                    .padding(.horizontal, YTLiteLayout.stackLoose)
                    .padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            actionItem(
                title: "Like",
                icon: playback.isFavorite ? "hand.thumbsup.fill" : "hand.thumbsup",
                tint: playback.isFavorite ? YTLiteColor.accent : YTLiteColor.onSurface
            ) {
                playback.toggleFavorite()
            }
            actionItem(title: "Dislike", icon: "hand.thumbsdown") {}
            if let item = playback.nowPlaying {
                ShareLink(item: item.watchShareURL) {
                    VStack(spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.right")
                        Text("Share").font(YTLiteType.iconCaption)
                    }
                    .foregroundStyle(YTLiteColor.onSurface)
                    .frame(maxWidth: .infinity)
                }
            }
            actionItem(title: "Save", icon: "bookmark") {
                showAddPlaylist = true
            }
            actionItem(title: "Download", icon: "arrow.down.to.line") {}
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
            Button { shuffleOn.toggle() } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(shuffleOn ? YTLiteColor.accent : YTLiteColor.onSurface)
            }
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
                    .foregroundStyle(YTLiteColor.onSurface)
            }
            Spacer()
            Button { repeatOn.toggle() } label: {
                Image(systemName: "repeat")
                    .font(.title3)
                    .foregroundStyle(repeatOn ? YTLiteColor.accent : YTLiteColor.onSurface)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, YTLiteLayout.stackTight)
    }

    // MARK: - Tabs

    private var tabHeader: some View {
        HStack(spacing: 20) {
            ForEach(PlayerTab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: YTLiteLayout.stackDefault) {
                        Text(item.rawValue)
                            .font(tab == item ? YTLiteType.labelEmphasized : YTLiteType.label)
                            .foregroundStyle(tab == item ? YTLiteColor.onSurface : YTLiteColor.onSurfaceVariant)
                        Rectangle()
                            .fill(tab == item ? YTLiteColor.onSurface : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var listToolbar: some View {
        HStack(spacing: YTLiteLayout.stackLoose) {
            Text(toolbarTitle)
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Spacer()
            if tab == .upNext {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                Button {
                    showAddPlaylist = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(width: 36, height: 36)
                        .background(YTLiteColor.accent, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var toolbarTitle: String {
        switch tab {
        case .upNext: return "\(playback.queue.count) Songs"
        case .lyrics: return "Lyrics"
        case .related: return relatedLoading ? "Loading…" : "\(related.count) videos"
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .upNext:
            ForEach(Array(playback.queue.enumerated()), id: \.element.id) { index, item in
                Button {
                    playback.play(items: playback.queue, startAt: index)
                } label: {
                    UpNextRow(item: item, isCurrent: index == playback.queueIndex)
                }
                .buttonStyle(.plain)
            }
        case .lyrics:
            LyricsPanel()
                .padding(.top, YTLiteLayout.stackTight)
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
                Text("No related videos")
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .padding(.vertical, YTLiteLayout.screenPadding)
            } else {
                ForEach(Array(related.enumerated()), id: \.element.id) { index, item in
                    Button {
                        playback.play(items: related, startAt: index)
                    } label: {
                        UpNextRow(item: item, isCurrent: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadRelated() async {
        let seed = playback.nowPlaying?.title
            ?? playback.nowPlaying?.channelName
            ?? ""
        guard !seed.isEmpty else { return }
        relatedLoading = true
        relatedError = nil
        defer { relatedLoading = false }
        do {
            let results = try await InnerTubeClient.searchVideos(query: seed)
            related = results.filter { $0.videoId != playback.nowPlaying?.videoId }
        } catch {
            relatedError = error.localizedDescription
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

private struct UpNextRow: View {
    let item: VideoItem
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: YTLiteLayout.stackLoose) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: item.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        YTLiteColor.surfaceVariant
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                if let d = item.durationText {
                    DurationBadge(text: d)
                        .scaleEffect(0.85)
                        .padding(2)
                }
            }

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
            Spacer()
            Image(systemName: "arrow.down.to.line")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Image(systemName: "ellipsis")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
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
                .foregroundStyle(YTLiteColor.onSurface)
                .listRowBackground(YTLiteColor.surfaceElevated)
            }
            .scrollContentBackground(.hidden)
            .background(YTLiteColor.background)
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
