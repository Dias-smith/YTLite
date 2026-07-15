import SwiftUI

/// Attaches global track-action + playlist-action sheets + toast to any root content.
struct TrackActionHost<Content: View>: View {
    var libraryStore: LibraryStore?
    @StateObject private var presenter = TrackActionPresenter()
    @StateObject private var playlistPresenter = PlaylistActionPresenter()
    @ViewBuilder var content: () -> Content

    @State private var renameText = ""

    var body: some View {
        content()
            .environmentObject(presenter)
            .environmentObject(playlistPresenter)
            .environment(\.libraryStore, libraryStore)
            .sheet(isPresented: $presenter.showActions) {
                if let context = presenter.context {
                    TrackActionSheet(context: context)
                        .environmentObject(presenter)
                        .environment(\.libraryStore, libraryStore)
                        .presentationDetents([.fraction(0.72), .large])
                        .presentationDragIndicator(.hidden)
                        .presentationContentInteraction(.scrolls)
                }
            }
            .sheet(isPresented: $playlistPresenter.showActions) {
                if let context = playlistPresenter.context {
                    PlaylistActionSheet(context: context)
                        .environmentObject(playlistPresenter)
                        .environment(\.libraryStore, libraryStore)
                        .presentationDetents([.fraction(0.55), .large])
                        .presentationDragIndicator(.hidden)
                        .presentationContentInteraction(.scrolls)
                }
            }
            .sheet(isPresented: $playlistPresenter.showRename) {
                NavigationStack {
                    Form {
                        TextField("Name", text: $renameText)
                            .foregroundStyle(YTLiteColor.onSurface)
                    }
                    .scrollContentBackground(.hidden)
                    .background(YTLiteColor.background)
                    .navigationTitle("Edit playlist")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { playlistPresenter.showRename = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { commitRename() }
                                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .preferredColorScheme(.dark)
                .presentationDetents([.medium])
            }
            .onChange(of: playlistPresenter.showRename) { _, isPresented in
                if isPresented {
                    renameText = playlistPresenter.context?.title ?? ""
                }
            }
            .sheet(isPresented: $playlistPresenter.showDeleteConfirm) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: YTLiteLayout.stackLoose) {
                        Text("Delete \"\(playlistPresenter.context?.title ?? "playlist")\"? This can't be undone.")
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        Spacer()
                        Button(role: .destructive) {
                            commitDelete()
                        } label: {
                            Text("Delete")
                                .font(YTLiteType.labelEmphasized)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(YTLiteColor.danger)
                        Button {
                            playlistPresenter.showDeleteConfirm = false
                        } label: {
                            Text("Cancel")
                                .font(YTLiteType.labelEmphasized)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(YTLiteLayout.screenPadding)
                    .background(YTLiteColor.background)
                    .navigationTitle("Delete playlist?")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .preferredColorScheme(.dark)
                .presentationDetents([.medium])
            }
            .overlay(alignment: .bottom) {
                if let message = presenter.toastMessage ?? playlistPresenter.toastMessage {
                    Text(message)
                        .font(YTLiteType.meta.weight(.semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(YTLiteColor.surfaceElevated, in: Capsule())
                        .padding(.bottom, 88)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeOut(duration: 0.2), value: message)
                }
            }
    }

    private func commitRename() {
        guard let context = playlistPresenter.context,
              context.canEdit,
              let playlist = libraryStore?.playlist(id: context.playlistId)
        else { return }
        libraryStore?.renamePlaylist(playlist, name: renameText)
        playlistPresenter.showToast("Playlist updated")
        playlistPresenter.notifyListsChanged()
    }

    private func commitDelete() {
        guard let context = playlistPresenter.context,
              context.canDelete,
              let playlist = libraryStore?.playlist(id: context.playlistId)
        else { return }
        libraryStore?.deletePlaylist(playlist)
        playlistPresenter.showToast("Playlist deleted")
        playlistPresenter.notifyListsChanged()
    }
}
