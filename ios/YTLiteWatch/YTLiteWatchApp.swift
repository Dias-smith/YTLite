import SwiftUI

@main
struct YTLiteWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
                // Avoid `@ObservedObject` on `App` — observing the shared bridge here
                // caused AttributeGraph cycles with EnvironmentObject descendants.
                .environmentObject(WatchConnectivityBridge.shared)
                .onAppear {
                    WatchPlaybackClient.shared.start()
                    WatchLibraryClient.shared.start()
                }
        }
    }
}
