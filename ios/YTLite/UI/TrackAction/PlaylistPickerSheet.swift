import SwiftUI

struct PlaylistPickerSheet: View {
    let item: VideoItem
    @Environment(\.libraryStore) private var store
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [LibraryPlaylist] = []
    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: "Save to library")
            Divider().overlay(YTLiteColor.surfaceVariant)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(playlists, id: \.playlistId) { playlist in
                        YTLiteSheetActionRow(
                            systemImage: playlistRowIcon(for: playlist),
                            title: displayName(playlist)
                        ) {
                            store?.add(item: item, to: playlist)
                            trackActions.notifyListsChanged()
                            trackActions.completePlaylistSave(toast: "Saved to \(displayName(playlist))")
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            YTLiteSheetPrimaryButton(title: "New playlist") {
                newName = ""
                showCreate = true
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(YTLiteColor.surfaceElevated)
        .onAppear { reloadPlaylists() }
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
            YTLiteSheetTitle(title: "New playlist")

            Text("Name")
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.bottom, 6)

            YTLiteSheetField(placeholder: "Playlist name", text: $newName)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                YTLiteSheetPrimaryButton(
                    title: "Create",
                    enabled: !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, let store else { return }
                    let playlist = store.createPlaylist(name: name)
                    store.add(item: item, to: playlist)
                    trackActions.notifyListsChanged()
                    newName = ""
                    showCreate = false
                    trackActions.completePlaylistSave(toast: "Saved to \(name)")
                }
                YTLiteSheetSecondaryButton(title: "Cancel") {
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

    private func reloadPlaylists() {
        playlists = store?.playlistsInLibraryOrder() ?? []
    }

    private func displayName(_ playlist: LibraryPlaylist) -> String {
        switch playlist.systemType {
        case SystemPlaylistType.favorites: return "Liked videos"
        case SystemPlaylistType.watchLater: return "Watch later"
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
