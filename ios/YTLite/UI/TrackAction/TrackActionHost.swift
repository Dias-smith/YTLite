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
                EditPlaylistNameSheet(
                    name: $renameText,
                    onCancel: { playlistPresenter.showRename = false },
                    onSave: { commitRename() }
                )
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(YTLiteColor.surfaceElevated)
            }
            .onChange(of: playlistPresenter.showRename) { _, isPresented in
                if isPresented {
                    renameText = playlistPresenter.context?.title ?? ""
                }
            }
            .sheet(isPresented: $playlistPresenter.showDeleteConfirm) {
                PlaylistDeleteConfirmSheet()
                    .environmentObject(playlistPresenter)
                    .environment(\.libraryStore, libraryStore)
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
        else {
            playlistPresenter.showRename = false
            return
        }
        libraryStore?.renamePlaylist(playlist, name: renameText)
        playlistPresenter.showRename = false
        playlistPresenter.showToast("Playlist updated")
        playlistPresenter.notifyListsChanged()
    }
}

private struct EditPlaylistNameSheet: View {
    @Binding var name: String
    var onCancel: () -> Void
    var onSave: () -> Void

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: "Edit playlist")

            Text("Name")
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.bottom, 6)

            YTLiteSheetField(placeholder: "Name", text: $name)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                YTLiteSheetPrimaryButton(title: "Save", enabled: canSave, action: onSave)
                YTLiteSheetSecondaryButton(title: "Cancel", action: onCancel)
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(YTLiteColor.surfaceElevated)
        .preferredColorScheme(.dark)
    }
}

/// Isolated sheet so delete uses `libraryStore` from the environment (not a stale capture).
private struct PlaylistDeleteConfirmSheet: View {
    @Environment(\.libraryStore) private var store
    @EnvironmentObject private var playlistPresenter: PlaylistActionPresenter

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: YTLiteLayout.stackLoose) {
                Text("Delete \"\(playlistPresenter.context?.title ?? "playlist")\"? This can't be undone.")
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                Spacer()
                Button {
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
    }

    private func commitDelete() {
        defer {
            playlistPresenter.showDeleteConfirm = false
        }
        guard let context = playlistPresenter.context, context.canDelete else { return }
        let deleted = store?.deletePlaylist(id: context.playlistId) ?? false
        guard deleted else { return }
        playlistPresenter.showToast("Playlist deleted")
        playlistPresenter.notifyListsChanged()
    }
}
