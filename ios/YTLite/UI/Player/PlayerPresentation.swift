import SwiftUI

/// Single app-wide host for PlayerDetail (sheet on all size classes so swipe-down dismiss works).
@MainActor
final class PlayerPresentation: ObservableObject {
    @Published var isPresented = false

    func present() {
        // Geometry updates after video fullscreen can dismiss the SwiftUI sheet
        // while leaving `isPresented == true`, so a second tap would no-op.
        if isPresented {
            isPresented = false
            Task { @MainActor in
                self.isPresented = true
            }
        } else {
            isPresented = true
        }
    }

    func dismiss() {
        isPresented = false
    }
}
