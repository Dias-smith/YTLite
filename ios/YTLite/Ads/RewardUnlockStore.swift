import Foundation

/// Local daily entitlements granted only after the rewarded callback fires.
@MainActor
final class RewardUnlockStore: ObservableObject {
    enum Feature: String {
        case editInfo = "edit_info"
        case themes
    }

    static let shared = RewardUnlockStore()

    @Published private(set) var revision = 0

    private init() {}

    func isUnlockedToday(_ feature: Feature) -> Bool {
        guard let date = UserDefaults.standard.object(forKey: key(for: feature)) as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(date)
    }

    func unlockToday(_ feature: Feature) {
        UserDefaults.standard.set(Date(), forKey: key(for: feature))
        revision += 1
        AdProbe.log("reward.unlock", "feature=\(feature.rawValue) scope=today")
    }

    private func key(for feature: Feature) -> String {
        "ad_reward_unlock_\(feature.rawValue)_date"
    }
}
