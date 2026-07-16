import SwiftUI
import SwiftData

@main
struct YTLiteApp: App {
    @StateObject private var playback = PlaybackController()
    @StateObject private var appModel = AppModel()
    @StateObject private var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer

    init() {
        let config = AppConfig.fromBundle()
        _authService = StateObject(wrappedValue: AuthService(config: config))
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(playback)
                .environmentObject(appModel)
                .environmentObject(authService)
                .preferredColorScheme(appModel.nightModeEnabled ? .dark : .light)
                .task {
                    appModel.syncAuth(authService)
                    _ = try? await ExtractorBridge.shared.ensureReady()
                }
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
