import Foundation
import FirebaseCore
import FirebaseCrashlytics

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
    }
}
