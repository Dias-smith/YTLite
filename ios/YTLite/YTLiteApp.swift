import SwiftUI
import SwiftData
import FirebaseAnalytics

@main
struct YTLiteApp: App {
    @StateObject private var playback = PlaybackController()
    @StateObject private var appModel = AppModel()
    @StateObject private var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer

    init() {
        FirebaseBootstrap.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        let config = AppConfig.fromBundle()
        _authService = StateObject(wrappedValue: AuthService(config: config))
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(playback)
                .environmentObject(playback.progress)
                .environmentObject(appModel)
                .environmentObject(authService)
                .environmentObject(ReviewPromptCoordinator.shared)
                .environment(\.locale, appModel.resolvedLocale)
                .environment(\.layoutDirection, appModel.layoutDirection)
                .id("\(appModel.languageCode)-\(appModel.themeRevision)")
                .preferredColorScheme(appModel.themeColorScheme)
                .task {
                    ExtractorRemoteConfigStore.restoreFromDisk()
                    appModel.syncAuth(authService)
                    ReviewPromptCoordinator.shared.recordActiveDay()
                    // Start after the first cooperative yield so early taps do not pay WKWebView startup.
                    Task(priority: .utility) {
                        await Task.yield()
                        _ = try? await ExtractorBridge.shared.ensureReady()
                    }
                    // UMP (+ ATT via IDFA Explainer) then Mobile Ads — before review prompts.
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
                        ReviewPromptCoordinator.shared.recordActiveDay()
                    }
                    if phase == .background || phase == .inactive {
                        playback.flushSession()
                        playback.publishNowPlaying()
                    }
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
