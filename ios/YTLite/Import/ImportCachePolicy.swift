import Foundation

/// Budget for NAS/cloud auto-cache copies (`cacheEligible == true`). User file imports are never LRU-evicted.
enum ImportCachePolicy {
    private static let budgetKey = "import.cache.budget.bytes"
    /// Default 2 GiB.
    static var budgetBytes: Int64 {
        get {
            let stored = UserDefaults.standard.object(forKey: budgetKey) as? NSNumber
            return stored?.int64Value ?? (2 * 1024 * 1024 * 1024)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: budgetKey)
        }
    }

    static var wifiOnlyAutoCache: Bool {
        get { UserDefaults.standard.object(forKey: "import.cache.wifiOnly") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "import.cache.wifiOnly") }
    }
}
