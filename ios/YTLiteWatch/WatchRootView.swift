import SwiftUI

/// Phase 5 shell: Now Playing + Queue + Library.
struct WatchRootView: View {
    @Environment(\.scenePhase) private var scenePhase

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
        .onAppear {
            WatchPlaybackClient.shared.syncWithPhone(bootstrap: true)
            WatchLibraryClient.shared.requestSnapshot()
            WatchWidgetCommandBridge.shared.consumePending()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            WatchPlaybackClient.shared.syncWithPhone(bootstrap: true)
            WatchLibraryClient.shared.requestSnapshot()
            WatchWidgetCommandBridge.shared.consumePending()
        }
    }
}

#Preview {
    WatchRootView()
        .environmentObject(WatchConnectivityBridge.shared)
}
