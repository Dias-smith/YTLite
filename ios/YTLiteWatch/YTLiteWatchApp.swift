import SwiftUI

@main
struct YTLiteWatchApp: App {
    init() {
        // Hydrate Now Playing before the first frame so home shows the current track immediately.
        WatchPlaybackClient.shared.preloadCachedNowPlaying()
        WatchConnectivityBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            root
        }
    }

    @ViewBuilder
    private var root: some View {
        let content = WatchRootView()
            // Avoid `@ObservedObject` on `App` — observing the shared bridge here
            // caused AttributeGraph cycles with EnvironmentObject descendants.
            .environmentObject(WatchConnectivityBridge.shared)
            .environmentObject(WatchPlaybackClient.shared)
            .onAppear {
                WatchPlaybackClient.shared.start()
                WatchLibraryClient.shared.start()
            }
        content
    }
}
