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
            sheetHeader(title: "Save to library") {
                dismiss()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Button {
                        showCreate = true
                    } label: {
                        Label("New playlist", systemImage: "plus")
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, YTLiteLayout.screenPadding)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    ForEach(playlists, id: \.playlistId) { playlist in
                        Button {
                            store?.add(item: item, to: playlist)
                            trackActions.notifyListsChanged()
                            trackActions.completePlaylistSave(toast: "Saved to \(displayName(playlist))")
                        } label: {
                            Text(displayName(playlist))
                                .font(YTLiteType.body)
                                .foregroundStyle(YTLiteColor.onSurface)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, YTLiteLayout.screenPadding)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(YTLiteColor.surfaceElevated)
        .onAppear { reloadPlaylists() }
        .sheet(isPresented: $showCreate) {
            createPlaylistSheet
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(YTLiteColor.surfaceElevated)
        .preferredColorScheme(.dark)
    }

    private var createPlaylistSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader(title: "New playlist") {
                newName = ""
                showCreate = false
            }
            TextField("Playlist name", text: $newName)
                .textFieldStyle(.plain)
                .foregroundStyle(YTLiteColor.onSurface)
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.vertical, 12)
                .background(YTLiteColor.surfaceVariant, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, YTLiteLayout.screenPadding)

            Button {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, let store else { return }
                let playlist = store.createPlaylist(name: name)
                store.add(item: item, to: playlist)
                trackActions.notifyListsChanged()
                newName = ""
                showCreate = false
                trackActions.completePlaylistSave(toast: "Saved to \(name)")
            } label: {
                Text("Create")
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(YTLiteColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(YTLiteColor.accent, in: Capsule())
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .padding(.horizontal, YTLiteLayout.screenPadding)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(YTLiteColor.surfaceElevated)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(YTLiteColor.surfaceElevated)
        .preferredColorScheme(.dark)
    }

    private func sheetHeader(title: String, close: @escaping () -> Void) -> some View {
        HStack {
            Button("Close", action: close)
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer()
            Text(title)
                .font(YTLiteType.sectionTitle)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer()
            Button("Close", action: close)
                .font(YTLiteType.body)
                .foregroundStyle(.clear)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.top, 18)
        .padding(.bottom, 10)
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
}
