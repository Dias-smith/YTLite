import Foundation

#if DEBUG
/// Registry of debug actions that Mac-side MCP tools can trigger over the local debug server.
@MainActor
final class AppDebugActionRegistry {
    static let shared = AppDebugActionRegistry()

    private var actions: [String: () -> Void] = [:]

    private init() {}

    func register(id: String, action: @escaping () -> Void) {
        actions[id] = action
    }

    func unregister(id: String) {
        actions.removeValue(forKey: id)
    }

    func availableActions() -> [String] {
        Array(actions.keys).sorted()
    }

    @discardableResult
    func trigger(id: String) -> Bool {
        guard let action = actions[id] else { return false }
        action()
        return true
    }
}
#endif
