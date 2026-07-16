import SwiftUI

struct TrackActionSheet: View {
    let context: TrackActionContext
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isLiked = false
    @State private var isNotInterested = false
    @State private var showShareSheet = false

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
                        systemImage: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                        title: isLiked ? "Unlike" : L("player.like")
                    ) { toggleLike() }

                    actionRow(systemImage: "text.insert", title: L("action.play_next")) {
                        playback.insertNext(context.asVideoItem)
                        trackActions.showToast(L("toast.playing_next"))
                        dismiss()
                    }

                    actionRow(systemImage: "plus.rectangle.on.rectangle", title: L("action.add_to_queue")) {
                        playback.appendToQueue(context.asVideoItem)
                        trackActions.showToast(L("toast.added_to_queue"))
                        dismiss()
                    }

                    actionRow(systemImage: "bookmark", title: L("action.save_to_library")) {
                        trackActions.openPlaylistPicker()
                    }

                    actionRow(systemImage: "pencil", title: L("action.edit_info")) {
                        trackActions.openEditInfo()
                    }

                    actionRow(systemImage: "text.alignleft", title: L("action.view_lyrics")) {
                        trackActions.openLyrics()
                    }

                    actionRow(systemImage: "square.and.arrow.up", title: L("common.share")) {
                        showShareSheet = true
                    }

                    actionRow(
                        systemImage: isNotInterested ? "eye" : "eye.slash",
                        title: isNotInterested ? "Undo not interested" : "Not interested"
                    ) { toggleNotInterested() }

                    if context.canRemoveFromPlaylist, let playlistId = context.playlistId {
                        Divider().overlay(YTLiteColor.surfaceVariant)
                            .padding(.vertical, 4)
                        actionRow(systemImage: "trash", title: L("action.remove_from_playlist")) {
                            if let playlist = store?.playlist(id: playlistId) {
                                store?.remove(trackId: context.videoId, from: playlist)
                                trackActions.notifyListsChanged()
                                trackActions.showToast(L("toast.removed_from_playlist"))
                            }
                            dismiss()
                        }
                    }
                }
                .padding(.top, YTLiteLayout.stackDefault)
                // Extra bottom inset so the last row clears the sheet corner / home indicator.
                .padding(.bottom, 28)
            }
        }
        .background(YTLiteColor.surfaceElevated)
        .onAppear { refreshState() }
        .sheet(isPresented: $showShareSheet) {
            SystemShareSheet(items: [context.watchURL])
                .ignoresSafeArea()
        }
        .sheet(isPresented: $trackActions.showPlaylistPicker) {
            PlaylistPickerSheet(item: context.asVideoItem)
                .environmentObject(trackActions)
                .environment(\.libraryStore, store)
        }
        .sheet(isPresented: $trackActions.showEditInfo) {
            EditTrackMetadataSheet(context: context)
                .environmentObject(trackActions)
                .environment(\.libraryStore, store)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .sheet(isPresented: $trackActions.showLyrics) {
            TrackLyricsSheet(videoId: context.videoId)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: YTLiteLayout.stackLoose) {
            RemoteImage(url: context.thumbnailURL)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(YTLiteType.rowTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)
                Text(displayChannel)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var displayTitle: String {
        store?.metadata(for: context.videoId)?.customTitle ?? context.title
    }

    private var displayChannel: String {
        store?.metadata(for: context.videoId)?.customArtistName ?? context.channelName
    }

    private func actionRow(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionRowLabel(systemImage: systemImage, title: title)
        }
        .buttonStyle(.plain)
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

    private func refreshState() {
        isLiked = store?.isFavorite(videoId: context.videoId) ?? false
        isNotInterested = store?.isNotInterested(videoId: context.videoId) ?? false
    }

    private func toggleLike() {
        guard let store else { return }
        if store.isNotInterested(videoId: context.videoId) {
            store.removeNotInterested(videoId: context.videoId)
        }
        store.toggleFavorite(item: context.asVideoItem)
        if context.videoId == playback.nowPlaying?.videoId {
            playback.refreshFavoriteState()
        }
        let liked = store.isFavorite(videoId: context.videoId)
        isLiked = liked
        trackActions.showToast(liked ? "Liked" : "Removed from Liked videos")
        trackActions.notifyListsChanged()
        dismiss()
    }

    private func toggleNotInterested() {
        guard let store else { return }
        if store.isFavorite(videoId: context.videoId) {
            store.toggleFavorite(item: context.asVideoItem)
        }
        let nowBlocked = store.toggleNotInterested(videoId: context.videoId)
        isNotInterested = nowBlocked
        if context.videoId == playback.nowPlaying?.videoId {
            playback.refreshFavoriteState()
        }
        trackActions.showToast(nowBlocked ? "Got it, we'll show fewer videos like this" : "Removed from Not interested")
        trackActions.notifyListsChanged()
        dismiss()
    }
}
