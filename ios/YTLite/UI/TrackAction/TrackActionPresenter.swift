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
    /// Bumps when all menu sheets should close (e.g. after save-to-playlist).
    @Published private(set) var menuCloseToken: Int = 0

    private var toastTask: Task<Void, Never>?
    private var dismissThenToastTask: Task<Void, Never>?

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

    /// Closes rich menu + playlist picker / edit / lyrics overlays.
    func dismissAllOverlays() {
        showActions = false
        showPlaylistPicker = false
        showEditInfo = false
        showLyrics = false
    }

    func openPlaylistPicker() {
        showPlaylistPicker = true
    }

    func openEditInfo() {
        showEditInfo = true
    }

    func openLyrics() {
        showLyrics = true
    }

    func notifyListsChanged() {
        listEpoch += 1
    }

    /// Dismiss every overlay first, then show toast after the sheet animation.
    func completePlaylistSave(toast message: String) {
        dismissAllOverlays()
        menuCloseToken += 1
        dismissThenToastTask?.cancel()
        toastTask?.cancel()
        toastMessage = nil
        dismissThenToastTask = Task {
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled else { return }
            showToast(message)
        }
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
