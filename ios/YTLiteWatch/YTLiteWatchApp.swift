import SwiftUI

@main
struct YTLiteWatchApp: App {
    init() {
        WatchL10n.configureAtLaunch()
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
        #if DEBUG
        content.environment(\.locale, Locale(identifier: "en"))
        #else
        content
        #endif
    }
}
