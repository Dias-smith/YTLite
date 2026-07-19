import SwiftUI

/// Single app-wide host for PlayerDetail (sheet on all size classes so swipe-down dismiss works).
@MainActor
final class PlayerPresentation: ObservableObject {
    @Published var isPresented = false

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}
