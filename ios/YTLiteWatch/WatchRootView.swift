import SwiftUI

/// Phase 5 shell: Now Playing + Queue + Library.
struct WatchRootView: View {
    @EnvironmentObject private var bridge: WatchConnectivityBridge

    var body: some View {
        TabView {
            WatchNowPlayingView()
                .tag(0)
            WatchQueueView()
                .tag(1)
            WatchLibraryView()
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}

#Preview {
    WatchRootView()
        .environmentObject(WatchConnectivityBridge.shared)
}
