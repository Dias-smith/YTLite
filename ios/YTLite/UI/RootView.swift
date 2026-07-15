import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = .home
    @State private var libraryStore: LibraryStore?
    @State private var syncService: LibrarySyncService?

    var body: some View {
        TrackActionHost {
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .home:
                        HomeView()
                    case .shorts:
                        ShortsView()
                    case .search:
                        SearchView()
                    case .you:
                        YouView()
                    case .library:
                        LibraryView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(YTLiteColor.background)

                if playback.nowPlaying != nil && selectedTab != .shorts {
                    MiniPlayerBar()
                }

                MainTabBar(selected: $selectedTab)
            }
            .background(YTLiteColor.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .environment(\.libraryStore, libraryStore)
            .onAppear {
                if libraryStore == nil {
                    let store = LibraryStore(modelContext: modelContext)
                    libraryStore = store
                    playback.libraryStore = store
                    let sync = LibrarySyncService(auth: auth)
                    syncService = sync
                    store.onMutate = {
                        Task { await sync.pushAll(store: store) }
                    }
                }
            }
            .onChange(of: auth.session?.user.id) { _, _ in
                appModel.syncAuth(auth)
                guard let libraryStore, auth.isAuthenticated else { return }
                Task { await syncService?.syncBidirectional(store: libraryStore) }
            }
            .onChange(of: selectedTab) { _, tab in
                if tab == .shorts, playback.isPlaying {
                    playback.togglePlayPause()
                }
            }
        }
    }
}

enum AppTab: Hashable {
    case home, shorts, search, you, library
}

private struct LibraryStoreKey: EnvironmentKey {
    static let defaultValue: LibraryStore? = nil
}

extension EnvironmentValues {
    var libraryStore: LibraryStore? {
        get { self[LibraryStoreKey.self] }
        set { self[LibraryStoreKey.self] = newValue }
    }
}
