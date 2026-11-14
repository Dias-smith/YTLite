import SwiftUI

/// Phase 5 shell: Now Playing + Queue + Library.
struct WatchRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    /// Always land on Now Playing when opening the Watch app.
    @State private var selectedPage = 0

    var body: some View {
        TabView(selection: $selectedPage) {
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
            selectedPage = 0
            WatchPlaybackClient.shared.syncWithPhone(bootstrap: true)
            WatchLibraryClient.shared.requestSnapshot()
            WatchWidgetCommandBridge.shared.consumePending()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            selectedPage = 0
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
