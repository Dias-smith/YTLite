import Foundation
import Combine

/// Global host for playlist rich-menu overlays (Android `PlaylistActionHost`).
@MainActor
final class PlaylistActionPresenter: ObservableObject {
    @Published var context: PlaylistActionContext?
    @Published var showActions = false
    @Published var showRename = false
    @Published var showDeleteConfirm = false
    @Published var toastMessage: String?
    @Published private(set) var listEpoch: Int = 0

    private var toastTask: Task<Void, Never>?

    func present(_ context: PlaylistActionContext) {
        self.context = context
        showActions = true
    }

    func dismissActions() {
        showActions = false
    }

    func openRename() {
        showActions = false
        showRename = true
    }

    /// Open rename alert without flashing the action sheet.
    func presentRename(_ context: PlaylistActionContext) {
        self.context = context
        showActions = false
        showRename = true
    }

    func openDeleteConfirm() {
        showActions = false
        showDeleteConfirm = true
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
