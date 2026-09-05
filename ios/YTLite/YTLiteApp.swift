import SwiftUI
import SwiftData
import FirebaseAnalytics

@main
struct YTLiteApp: App {
    @UIApplicationDelegateAdaptor(YTLiteAppDelegate.self) private var appDelegate
    @StateObject private var playback = PlaybackController()
    @StateObject private var appModel = AppModel()
    @StateObject private var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer

    init() {
        FirebaseBootstrap.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        AppNotificationCenterDelegate.shared.install()
        WatchConnectivityBridge.shared.activate()
        let config = AppConfig.fromBundle()
        _authService = StateObject(wrappedValue: AuthService(config: config))
        modelContainer = Self.makeModelContainer()
        #if DEBUG
        print("[AppDebugKit] YTLiteApp.init → starting debug server")
        NSLog("[AppDebugKit] YTLiteApp.init → starting debug server")
        AppDebugServer.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(playback)
                .environmentObject(playback.progress)
                .environmentObject(playback.equalizerStore)
                .environmentObject(appModel)
                .environmentObject(authService)
                .environmentObject(ReviewPromptCoordinator.shared)
                .environmentObject(VipStore.shared)
                .environment(\.locale, appModel.resolvedLocale)
                .environment(\.layoutDirection, appModel.layoutDirection)
                // Rebuild the tree on theme *or* language so `L()` strings refresh immediately
                // (VIP / Settings sections otherwise keep stale English copy).
                .id("\(appModel.themeRevision)-\(appModel.languageCode)")
                .preferredColorScheme(appModel.themeColorScheme)
                .task {
                    // First frame, then ATT, then UMP / AdMob.
                    await Task.yield()
                    WatchConnectivityBridge.shared.activate()
                    WatchPlaybackHost.shared.start(playback: playback)
                    await AdConsentManager.requestTrackingAuthorizationAtLaunch()

                    ResolverRemoteConfigStore.restoreFromDisk()
                    await RemoteConfigStore.fetchAndActivate()
                    await VipStore.shared.refresh()
                    appModel.syncAuth(authService)
                    ReviewPromptCoordinator.shared.recordActiveDay()
                    // Start after the first cooperative yield so early taps do not pay WKWebView startup.
                    Task(priority: .utility) {
                        await Task.yield()
                        _ = try? await StreamResolver.shared.ensureReady()
                    }
                    await AdBootstrap.startIfNeeded()
                }
                .adSceneLifecycle()
                .onOpenURL { url in
                    Task {
                        if let client = authService.supabaseClient() {
                            _ = try? await client.auth.session(from: url)
                            await authService.refreshSession()
                            appModel.syncAuth(authService)
                        }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        AppAnalytics.appOpen(coldStart: false)
                        ReviewPromptCoordinator.shared.recordActiveDay()
                        playback.consumePendingDailyListenIfNeeded()
                        if playback.isPlaying {
                            playback.prepareForBackgroundPlayback()
                        }
                    }
                    if phase == .background {
                        AppAnalytics.appBackground()
                        playback.flushSession()
                        playback.prepareForBackgroundPlayback()
                    } else if phase == .inactive {
                        playback.flushSession()
                        playback.publishNowPlaying()
                        // Arm audio session early. When PiP is off, surfaces also detach
                        // the video layer on willResignActive so Home from player detail
                        // cannot open a floating window.
                        if playback.isPlaying {
                            playback.prepareForBackgroundPlayback()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .ytlitePlayFromDailyNotification)) { _ in
                    playback.consumePendingDailyListenIfNeeded()
                }
                .onAppear {
                    AppAnalytics.appOpen(coldStart: true)
                }
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            LibraryTrack.self,
            LibraryPlaylist.self,
            LibraryPlaylistEntry.self,
            PlaybackHistoryItem.self,
            UserTrackLastPlayed.self,
            UserTrackMetadata.self,
            UserSubscribedChannel.self,
            NotInterestedItem.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Schema evolved (e.g. new optional fields); wipe local store and recreate.
            // Library data can be re-synced after sign-in.
            let url = configuration.url
            try? FileManager.default.removeItem(at: url)
            let wal = URL(fileURLWithPath: url.path + "-wal")
            let shm = URL(fileURLWithPath: url.path + "-shm")
            try? FileManager.default.removeItem(at: wal)
            try? FileManager.default.removeItem(at: shm)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("SwiftData container failed: \(error)")
            }
        }
    }
}
