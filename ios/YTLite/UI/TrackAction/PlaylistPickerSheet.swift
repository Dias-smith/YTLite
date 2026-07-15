import SwiftUI

struct PlaylistPickerSheet: View {
    let item: VideoItem
    @Environment(\.libraryStore) private var store
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.dismiss) private var dismiss
    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showCreate = true
                    } label: {
                        Label("New playlist", systemImage: "plus")
                            .foregroundStyle(YTLiteColor.accent)
                    }
                    .listRowBackground(YTLiteColor.surfaceElevated)
                }

                Section {
                    ForEach(store?.allPlaylists() ?? [], id: \.playlistId) { playlist in
                        Button {
                            store?.add(item: item, to: playlist)
                            trackActions.showToast("Saved to \(displayName(playlist))")
                            trackActions.notifyListsChanged()
                            dismiss()
                        } label: {
                            HStack {
                                Text(displayName(playlist))
                                    .foregroundStyle(YTLiteColor.onSurface)
                                Spacer()
                            }
                        }
                        .listRowBackground(YTLiteColor.surfaceElevated)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(YTLiteColor.background)
            .navigationTitle("Save to library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("New playlist", isPresented: $showCreate) {
                TextField("Playlist name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, let store else { return }
                    let playlist = store.createPlaylist(name: name)
                    store.add(item: item, to: playlist)
                    trackActions.showToast("Saved to \(name)")
                    trackActions.notifyListsChanged()
                    newName = ""
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func displayName(_ playlist: LibraryPlaylist) -> String {
        switch playlist.systemType {
        case SystemPlaylistType.favorites: return "Liked videos"
        case SystemPlaylistType.watchLater: return "Watch later"
        default: return playlist.name
        }
    }
}
