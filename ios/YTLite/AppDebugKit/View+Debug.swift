import SwiftUI

extension View {
    /// Registers a debug action while the view is on screen. No-op in Release builds.
    func debugAction(_ id: String, action: @escaping () -> Void) -> some View {
        #if DEBUG
        modifier(DebugActionModifier(id: id, action: action))
        #else
        self
        #endif
    }

    /// Publishes the current view node id for `/state` while the view is visible.
    func debugView(_ id: String) -> some View {
        #if DEBUG
        modifier(DebugViewModifier(id: id))
        #else
        self
        #endif
    }

    /// Pushes a presentation frame so `system.back` can dismiss this UI layer.
    func debugPresentation(_ id: String, dismiss: @escaping () -> Void) -> some View {
        #if DEBUG
        modifier(DebugPresentationModifier(id: id, dismiss: dismiss))
        #else
        self
        #endif
    }
}

#if DEBUG
private struct DebugActionModifier: ViewModifier {
    let id: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppDebugActionRegistry.shared.register(id: id, action: action)
            }
            .onDisappear {
                AppDebugActionRegistry.shared.unregister(id: id)
            }
    }
}

private struct DebugViewModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppDebugSessionState.shared.setView(id)
            }
    }
}

private struct DebugPresentationModifier: ViewModifier {
    let id: String
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppDebugSessionState.shared.push(id: id, dismiss: dismiss)
            }
            .onDisappear {
                AppDebugSessionState.shared.removeIfPresent(id: id)
            }
    }
}
#endif
