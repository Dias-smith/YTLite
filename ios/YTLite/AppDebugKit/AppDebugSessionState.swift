import Foundation

#if DEBUG
/// Tracks the current UI node and a dismiss stack so MCP exploration can DFS + `system.back`.
@MainActor
final class AppDebugSessionState {
    static let shared = AppDebugSessionState()

    private struct Frame {
        let id: String
        let dismiss: () -> Void
    }

    private(set) var viewID: String = "app.root"
    private(set) var tab: String = "home"
    private var stack: [Frame] = []
    /// Called when the stack is empty: typically return to Home tab / dismiss root sheets.
    var returnToRoot: (() -> Void)?
    /// Optional app-specific fields merged into `/state` (playback, auth, etc.).
    var extraSnapshot: (() -> [String: Any])?

    private init() {}

    func setTab(_ tab: String, viewID: String) {
        self.tab = tab
        if stack.isEmpty {
            self.viewID = viewID
        }
    }

    func setView(_ viewID: String) {
        self.viewID = viewID
    }

    func push(id: String, dismiss: @escaping () -> Void) {
        if stack.last?.id == id { return }
        stack.append(Frame(id: id, dismiss: dismiss))
        viewID = id
    }

    func removeIfPresent(id: String) {
        guard let index = stack.lastIndex(where: { $0.id == id }) else { return }
        stack.remove(at: index)
        viewID = stack.last?.id ?? rootViewID
    }

    @discardableResult
    func back() -> Bool {
        if let top = stack.popLast() {
            viewID = stack.last?.id ?? rootViewID
            top.dismiss()
            return true
        }
        returnToRoot?()
        return true
    }

    private var rootViewID: String {
        "tab.\(tab)"
    }

    func snapshot() -> [String: Any] {
        var payload: [String: Any] = [
            "status": "ok",
            "view_id": viewID,
            "tab": tab,
            "presented": stack.map(\.id),
            "actions": AppDebugActionRegistry.shared.availableActions(),
        ]
        if let extra = extraSnapshot?() {
            for (key, value) in extra {
                payload[key] = value
            }
        }
        return payload
    }
}
#endif
