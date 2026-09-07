import SwiftUI

/// Phase 5 shell: Now Playing + Queue + Library.
struct WatchRootView: View {
    @EnvironmentObject private var bridge: WatchConnectivityBridge

    var body: some View {
        TabView {
            WatchNowPlayingView()
                .containerBackground(for: .tabView) {
                    Color.black
                }
                .ignoresSafeArea()
                .tag(0)
            WatchQueueView()
                .tag(1)
            WatchLibraryView()
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
        .scrollIndicators(.hidden)
    }
}

#Preview {
    WatchRootView()
        .environmentObject(WatchConnectivityBridge.shared)
}
