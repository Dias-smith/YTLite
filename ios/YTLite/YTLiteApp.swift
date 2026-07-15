import SwiftUI
import SwiftData

@main
struct YTLiteApp: App {
    @StateObject private var playback = PlaybackController()
    @StateObject private var appModel = AppModel()
    @StateObject private var authService: AuthService
    private let modelContainer: ModelContainer

    init() {
        let config = AppConfig.fromBundle()
        _authService = StateObject(wrappedValue: AuthService(config: config))
        do {
            modelContainer = try ModelContainer(
                for: LibraryTrack.self,
                    LibraryPlaylist.self,
                    LibraryPlaylistEntry.self,
                    PlayHistoryItem.self
            )
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
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
        }
        .modelContainer(modelContainer)
    }
}
