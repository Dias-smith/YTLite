import Foundation
import Combine

/// Global host for the track rich menu overlays (Android TrackActionHost).
@MainActor
final class TrackActionPresenter: ObservableObject {
    @Published var context: TrackActionContext?
    @Published var showActions = false
    @Published var showPlaylistPicker = false
    @Published var showEditInfo = false
    @Published var showLyrics = false
    @Published var toastMessage: String?
    /// Bumps when lists should drop not-interested / refresh after mutations.
    @Published private(set) var listEpoch: Int = 0

    private var toastTask: Task<Void, Never>?

    func present(_ context: TrackActionContext) {
        self.context = context
        showActions = true
    }

    func present(item: VideoItem, playlistId: String? = nil, canRemoveFromPlaylist: Bool = false) {
        present(
            TrackActionContext(
                item: item,
                playlistId: playlistId,
                canRemoveFromPlaylist: canRemoveFromPlaylist
            )
        )
    }

    func dismissActions() {
        showActions = false
    }

    func openPlaylistPicker() {
        showActions = false
        showPlaylistPicker = true
    }

    func openEditInfo() {
        showActions = false
        showEditInfo = true
    }

    func openLyrics() {
        showActions = false
        showLyrics = true
    }

    func notifyListsChanged() {
        listEpoch += 1
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }
}
