import Foundation

/// Persisted counters / cooldowns for in-app review prompting.
enum ReviewPromptStore {
    private static let completedPlaysKey = "review.completedPlays"
    private static let activeDaysKey = "review.activeDays"
    private static let lastPromptAtKey = "review.lastPromptAt"
    private static let outcomeKey = "review.promptOutcome"
    private static let youShelfPromptedKey = "review.youShelfPrompted"
    private static let positiveActionPromptedKey = "review.positiveActionPrompted"
    private static let processStart = Date()

    enum Outcome: String {
        case none
        case loved
        case feedback
        case later
    }

    static var completedPlays: Int {
        get { UserDefaults.standard.integer(forKey: completedPlaysKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedPlaysKey) }
    }

    static var activeDays: [String] {
        get { UserDefaults.standard.stringArray(forKey: activeDaysKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: activeDaysKey) }
    }

    static var lastPromptAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: lastPromptAtKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: lastPromptAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastPromptAtKey)
            }
        }
    }

    static var outcome: Outcome {
        get { Outcome(rawValue: UserDefaults.standard.string(forKey: outcomeKey) ?? "") ?? .none }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: outcomeKey) }
    }

    static var youShelfPrompted: Bool {
        get { UserDefaults.standard.bool(forKey: youShelfPromptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: youShelfPromptedKey) }
    }

    static var positiveActionPrompted: Bool {
        get { UserDefaults.standard.bool(forKey: positiveActionPromptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: positiveActionPromptedKey) }
    }

    static var secondsSinceProcessStart: TimeInterval {
        Date().timeIntervalSince(processStart)
    }

    static func dayStamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
