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
            .onChange(of: selectedTab) { _, tab in
                AdSceneLifecycle.recordFirstInteraction(source: "tab")
                #if DEBUG
                AppDebugSessionState.shared.setTab(Self.debugTabName(tab), viewID: "tab.\(Self.debugTabName(tab))")
                #endif
            }
            .debugView("tab.\(Self.debugTabName(selectedTab))")
            .debugAction("tab.home") { selectedTab = .home }
            .debugAction("tab.search") { selectedTab = .search }
            .debugAction("tab.you") { selectedTab = .you }
            .debugAction("tab.library") { selectedTab = .library }
            .debugAction("playback.toggle") { playback.togglePlayPause() }
            .debugAction("playback.next") { playback.playNext() }
            .debugAction("playback.previous") { playback.playPrevious() }
            .debugAction("playback.cycle_repeat") { _ = playback.cycleRepeatMode() }
            .debugAction("queue.play_next_index") {
                let target = playback.queueIndex + 1
                guard playback.queue.indices.contains(target) else { return }
                playback.playQueueIndex(target)
            }
            .debugAction("player.open") { playerPresentation.isPresented = true }
            .debugAction("player.close") { playerPresentation.isPresented = false }
            .onAppear {
                #if DEBUG
                AppDebugSessionState.shared.setTab(
                    Self.debugTabName(selectedTab),
                    viewID: "tab.\(Self.debugTabName(selectedTab))"
                )
                AppDebugSessionState.shared.returnToRoot = {
                    playerPresentation.isPresented = false
                    selectedTab = .home
                }
                AppDebugSessionState.shared.extraSnapshot = {
                    [
                        "playback": playback.debugStateSnapshot(),
                        "auth": [
                            "isAuthenticated": auth.isAuthenticated,
                        ] as [String: Any],
                        "playerPresented": playerPresentation.isPresented,
                    ]
                }
                #endif
            }
            .ytLiteAppBackground()
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
                    AdEligibility.bind(libraryStore: store)
                    Task { await DailyListenNotificationScheduler.refresh(using: store) }
                    playback.consumePendingDailyListenIfNeeded()
                    let sync = LibrarySyncService(auth: auth)
                    syncService = sync
                    store.onMutate = {
                        Task {
                            await sync.pushAll(store: store)
                            AdEligibility.refreshInventoryIfEligible()
                            await DailyListenNotificationScheduler.refresh(using: store)
                        }
                    }
                    WatchLibraryHost.shared.start(store: store, playback: playback, auth: auth)
                    store.onUnsubscribeChannel = { channelId in
                        Task { await sync.deleteSubscribedChannel(channelId: channelId) }
                    }
                    // Restore catalogue titles that were overwritten with videoId.
                    if store.repairPlaceholderTitlesLocally() > 0 {
                        playback.reenrichTitlesFromLibrary()
                        appModel.bumpLibraryRevision()
                    }
                    Task {
                        if await store.repairPlaceholderTitlesFromNetwork() > 0 {
                            playback.reenrichTitlesFromLibrary()
                            appModel.bumpLibraryRevision()
                        }
                    }
                    if auth.isAuthenticated {
                        Task {
                            let t0 = SyncProbe.now()
                            let trace = SyncProbe.newTraceId()
                            SyncProbe.currentTrace = trace
                            SyncProbe.logTrace("sync.start", "source=root_appear")
                            AppAnalytics.librarySyncStart(source: "appear")
                            appModel.beginLibrarySync()
                            defer {
                                let ms = SyncProbe.ms(since: t0)
                                SyncProbe.logTrace("sync.end", "source=root_appear total_ms=\(ms)")
                                AppAnalytics.librarySyncEnd(ok: true, ms: ms)
                                appModel.endLibrarySync()
                            }
                            await sync.syncBidirectional(store: store)
                            // Cloud may still hold real titles for rows we couldn't fix locally.
                            if store.repairPlaceholderTitlesLocally() > 0 {
                                playback.reenrichTitlesFromLibrary()
                            }
                            if await store.repairPlaceholderTitlesFromNetwork() > 0 {
                                playback.reenrichTitlesFromLibrary()
                            }
                            AdEligibility.refreshInventoryIfEligible()
                            await DailyListenNotificationScheduler.refresh(using: store)
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
                    AppAnalytics.librarySyncStart(source: "login")
                    appModel.beginLibrarySync()
                    defer {
                        let ms = SyncProbe.ms(since: t0)
                        SyncProbe.logTrace("sync.end", "source=\(source) total_ms=\(ms)")
                        AppAnalytics.librarySyncEnd(ok: true, ms: ms)
                        appModel.endLibrarySync()
                    }

                    guard let next else {
                        // Sign out → guest bucket (keep prior user buckets).
                        libraryStore.setOwnerKey(OwnerKeyStore.stableGuestOwnerKey)
                        WatchLibraryHost.shared.refresh()
                        AdEligibility.refreshInventoryIfEligible()
                        await DailyListenNotificationScheduler.refresh(using: libraryStore)
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
                        // User A → User B: switch bucket only (keep A stored).
                        libraryStore.setOwnerKey(userKey)
                        await syncService?.syncBidirectional(store: libraryStore)
                    } else {
                        libraryStore.setOwnerKey(userKey)
                        await syncService?.syncBidirectional(store: libraryStore)
                    }
                    AdEligibility.refreshInventoryIfEligible()
                    await DailyListenNotificationScheduler.refresh(using: libraryStore)
                    WatchLibraryHost.shared.refresh()
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
            .sheet(isPresented: $appModel.showLocaleSetupSheet) {
                LocaleSetupSheet(
                    languageCode: appModel.languageCode,
                    regionCode: appModel.contentRegionCode
                )
                .environmentObject(appModel)
            }
        }
        // Must wrap TrackActionHost so AppChrome itself (not only its children) receives it.
        .environmentObject(playerPresentation)
    }
}

enum AppTab: Hashable {
    case home, search, you, library
}

extension RootView {
    fileprivate static func debugTabName(_ tab: AppTab) -> String {
        switch tab {
        case .home: return "home"
        case .search: return "search"
        case .you: return "you"
        case .library: return "library"
        }
    }
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
