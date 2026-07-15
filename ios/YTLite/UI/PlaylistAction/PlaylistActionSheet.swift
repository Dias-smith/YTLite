import SwiftUI

/// Playlist more menu — mirrors Android `PlaylistActionBottomSheet`.
struct PlaylistActionSheet: View {
    let context: PlaylistActionContext
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playlistActions: PlaylistActionPresenter
    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var trackCount: Int = 0
    @State private var totalDurationSeconds: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(YTLiteColor.onSurfaceVariant.opacity(0.45))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 12)

            header
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.bottom, YTLiteLayout.stackLoose)

            Divider().overlay(YTLiteColor.surfaceVariant)

            ScrollView {
                VStack(spacing: 0) {
                    actionRow(
                        systemImage: "shuffle",
                        title: "Shuffle play",
                        enabled: trackCount > 0
                    ) {
                        shufflePlay()
                    }

                    actionRow(
                        systemImage: "pencil",
                        title: "Edit",
                        enabled: context.canEdit
                    ) {
                        playlistActions.openRename()
                    }

                    ShareLink(item: shareText) {
                        actionRowLabel(systemImage: "square.and.arrow.up", title: "Share")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        playlistActions.showToast("Share")
                        dismiss()
                    })

                    Divider().overlay(YTLiteColor.surfaceVariant)
                        .padding(.vertical, 4)

                    actionRow(
                        systemImage: "trash",
                        title: "Delete",
                        enabled: context.canDelete
                    ) {
                        playlistActions.openDeleteConfirm()
                    }
                }
                .padding(.top, YTLiteLayout.stackDefault)
                .padding(.bottom, 28)
            }
        }
        .background(YTLiteColor.surfaceElevated)
        .onAppear { refreshStats() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            playlistCover
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(context.title)
                    .font(YTLiteType.rowTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(2)
                Text(statsSubtitle)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var playlistCover: some View {
        switch context.coverKind {
        case .liked:
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.2, green: 0.45, blue: 0.95), Color(red: 0.85, green: 0.3, blue: 0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "hand.thumbsup.fill").foregroundStyle(.white)
            }
        case .watchLater:
            ZStack {
                YTLiteColor.accent
                Image(systemName: "clock.fill").foregroundStyle(.white)
            }
        case .history:
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.25, green: 0.28, blue: 0.4), Color(red: 0.15, green: 0.16, blue: 0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.white)
            }
        case .custom:
            if let url = context.coverURL {
                RemoteImage(url: url)
            } else {
                ZStack {
                    YTLiteColor.surfaceVariant
                    Image(systemName: "music.note.list").foregroundStyle(YTLiteColor.onSurface)
                }
            }
        }
    }

    private var statsSubtitle: String {
        let songs = "\(trackCount) songs"
        guard totalDurationSeconds > 0 else { return songs }
        return "\(songs) · \(Self.formatDuration(totalDurationSeconds))"
    }

    private var shareText: String {
        context.title
    }

    private func actionRow(
        systemImage: String,
        title: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionRowLabel(systemImage: systemImage, title: title)
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func actionRowLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: YTLiteLayout.stackLoose) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(YTLiteColor.onSurface)
                .frame(width: 28, alignment: .center)
            Text(title)
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer()
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func refreshStats() {
        if context.isHistory {
            let history = store?.historyVideos() ?? []
            trackCount = history.count
            totalDurationSeconds = history
                .map { DurationFormat.seconds(from: $0.durationText) }
                .reduce(0, +)
            return
        }
        guard let playlist = store?.playlist(id: context.playlistId) else {
            trackCount = 0
            totalDurationSeconds = 0
            return
        }
        trackCount = playlist.trackCount
        totalDurationSeconds = playlist.entries
            .compactMap(\.track?.durationSeconds)
            .reduce(0, +)
    }

    private func shufflePlay() {
        let items: [VideoItem]
        if context.isHistory {
            items = store?.historyVideos() ?? []
        } else if let playlist = store?.playlist(id: context.playlistId) {
            items = playlist.entries
                .sorted { $0.position < $1.position }
                .compactMap { $0.track?.asVideoItem }
        } else {
            items = []
        }
        guard !items.isEmpty else { return }
        playback.play(
            items: items.shuffled(),
            startAt: 0,
            sourcePlaylistId: context.isHistory ? nil : context.playlistId
        )
        playlistActions.showToast("Shuffle play")
        dismiss()
    }

    private static func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }
        return "\(max(minutes, 1)) min"
    }
}
