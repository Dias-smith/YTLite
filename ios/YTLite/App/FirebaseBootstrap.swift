import Foundation
import FirebaseCore
import FirebaseCrashlytics
import FirebaseRemoteConfig

enum FirebaseBootstrap {
    static func configure() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        // GoogleService-Info may ship with IS_ANALYTICS_ENABLED=false; enable collection for product analytics.
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
        RemoteConfigStore.configure()
    }
}

/// Thin wrapper around Firebase Remote Config (parity with Android `RemoteConfigRepository`).
enum RemoteConfigStore {
    private static let allowOfflineKey = "allow_offline"

    static func configure() {
        guard isFirebaseAvailable else { return }
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 12 * 60 * 60
        #endif
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults([
            allowOfflineKey: NSNumber(value: false),
        ])
    }

    /// Fetch and activate latest values. Safe to call repeatedly from app launch.
    @discardableResult
    static func fetchAndActivate() async -> Bool {
        guard isFirebaseAvailable else { return false }
        do {
            let status = try await RemoteConfig.remoteConfig().fetchAndActivate()
            return status != .error
        } catch {
            return false
        }
    }

    /// When true, play local media store without re-resolving stream URLs.
    static var allowOffline: Bool {
        guard isFirebaseAvailable else { return false }
        return RemoteConfig.remoteConfig().configValue(forKey: allowOfflineKey).boolValue
    }

    private static var isFirebaseAvailable: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
            && FirebaseApp.app() != nil
    }
}
