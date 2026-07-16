import Foundation

/// Stable local ownership keys — Android `guest:{id}` / `user:{supabaseUserId}`.
enum OwnerKeyStore {
    private static let guestIdKey = "ytlite.stable_guest_id"

    static var stableGuestOwnerKey: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: guestIdKey), !existing.isEmpty {
            return "guest:\(existing)"
        }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: guestIdKey)
        return "guest:\(id)"
    }

    static func userOwnerKey(userId: String) -> String {
        "user:\(userId.lowercased())"
    }

    @MainActor
    static func current(auth: AuthService) -> String {
        if let userId = auth.userId {
            return userOwnerKey(userId: userId)
        }
        return stableGuestOwnerKey
    }

    static func isGuest(_ ownerKey: String) -> Bool {
        ownerKey.hasPrefix("guest:")
    }

    static func isUser(_ ownerKey: String) -> Bool {
        ownerKey.hasPrefix("user:")
    }
}
