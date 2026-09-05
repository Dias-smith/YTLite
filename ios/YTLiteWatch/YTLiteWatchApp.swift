import SwiftUI

@main
struct YTLiteWatchApp: App {
    @ObservedObject private var bridge = WatchConnectivityBridge.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(bridge)
                .onAppear {
                    WatchPlaybackClient.shared.start()
                    WatchLibraryClient.shared.start()
                }
        }
    }
}
