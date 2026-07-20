import SwiftUI
import SwiftData
import UIKit

struct RootView: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var review: ReviewPromptCoordinator
    @Environment(\.modelContext) private var modelContext
    @StateObject private var playerPresentation = PlayerPresentation()
    @State private var selectedTab: AppTab = .home
    @State private var libraryStore: LibraryStore?
    @State private var syncService: LibrarySyncService?
    @State private var isKeyboardVisible = false

    var body: some View {
        TrackActionHost(libraryStore: libraryStore) {
            AppChrome(
                selectedTab: $selectedTab,
                isAuthenticated: auth.isAuthenticated,
                isKeyboardVisible: isKeyboardVisible
            ) {
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
            }
            .environment(\.selectAppTab) { tab in
                selectedTab = tab
                AdSceneLifecycle.recordFirstInteraction(source: "tab")
            }
            .onChange(of: selectedTab) { _, _ in
                AdSceneLifecycle.recordFirstInteraction(source: "tab")
            }
            .background(YTLiteColor.background.ignoresSafeArea())
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .onAppear {
                if libraryStore == nil {
                    let ownerKey = OwnerKeyStore.current(auth: auth)
                    let store = LibraryStore(modelContext: modelContext, ownerKey: ownerKey)
                    libraryStore = store
                    playback.libraryStore = store
                    let sync = LibrarySyncService(auth: auth)
                    syncService = sync
                    store.onMutate = {
                        Task { await sync.pushAll(store: store) }
                    }
                    store.onUnsubscribeChannel = { channelId in
                        Task { await sync.deleteSubscribedChannel(channelId: channelId) }
                    }
                    if auth.isAuthenticated {
                        Task {
                            let t0 = SyncProbe.now()
                            let trace = SyncProbe.newTraceId()
                            SyncProbe.currentTrace = trace
                            SyncProbe.logTrace("sync.start", "source=root_appear")
                            appModel.beginLibrarySync()
                            defer {
                                SyncProbe.logTrace("sync.end", "source=root_appear total_ms=\(SyncProbe.ms(since: t0))")
                                appModel.endLibrarySync()
                            }
                            await sync.syncBidirectional(store: store)
                        }
                    }
                }
            }
            .onChange(of: auth.session?.user.id) { previous, next in
                appModel.syncAuth(auth)
                guard let libraryStore else { return }

                Task {
                    // Any auth transition (login / logout / switch) shows Library spinner.
                    let t0 = SyncProbe.now()
                    let trace = SyncProbe.newTraceId()
                    SyncProbe.currentTrace = trace
                    let source: String
                    if next == nil {
                        source = "root_user_to_guest"
                    } else if previous == nil {
                        source = "root_guest_to_user"
                    } else if previous != next {
                        source = "root_user_switch"
                    } else {
                        source = "root_user_same"
                    }
                    SyncProbe.logTrace("sync.start", "source=\(source)")
                    appModel.beginLibrarySync()
                    defer {
                        SyncProbe.logTrace("sync.end", "source=\(source) total_ms=\(SyncProbe.ms(since: t0))")
                        appModel.endLibrarySync()
                    }

                    guard let next else {
                        // Sign out → guest bucket (keep prior user buckets).
                        libraryStore.setOwnerKey(OwnerKeyStore.stableGuestOwnerKey)
                        return
                    }

                    let userKey = OwnerKeyStore.userOwnerKey(userId: next.uuidString)
                    let guestKey = OwnerKeyStore.stableGuestOwnerKey

                    if previous == nil {
                        // Guest → User: merge guest into this user, then sync.
                        await syncService?.mergeGuestIntoUserAndSync(
                            store: libraryStore,
                            guestKey: guestKey,
                            userKey: userKey
                        )
                    } else if previous != next {
                        // User A → User B: switch bucket only (keep A cached).
                        libraryStore.setOwnerKey(userKey)
                        await syncService?.syncBidirectional(store: libraryStore)
                    } else {
                        libraryStore.setOwnerKey(userKey)
                        await syncService?.syncBidirectional(store: libraryStore)
                    }
                }
            }
            .onChange(of: appModel.isLibrarySyncing) { _, syncing in
                review.setBusy("librarySync", syncing)
            }
            .onChange(of: auth.isBusy) { _, busy in
                review.setBusy("auth", busy)
            }
            .sheet(isPresented: $review.showSheet) {
                ReviewPromptSheet()
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(YTLiteColor.surfaceElevated)
            }
        }
        // Must wrap TrackActionHost so AppChrome itself (not only its children) receives it.
        .environmentObject(playerPresentation)
    }
}

enum AppTab: Hashable {
    case home, shorts, search, you, library
}

private struct LibraryStoreKey: EnvironmentKey {
    static let defaultValue: LibraryStore? = nil
}

private struct SelectAppTabKey: EnvironmentKey {
    static let defaultValue: ((AppTab) -> Void)? = nil
}

extension EnvironmentValues {
    var libraryStore: LibraryStore? {
        get { self[LibraryStoreKey.self] }
        set { self[LibraryStoreKey.self] = newValue }
    }

    var selectAppTab: ((AppTab) -> Void)? {
        get { self[SelectAppTabKey.self] }
        set { self[SelectAppTabKey.self] = newValue }
    }
}
