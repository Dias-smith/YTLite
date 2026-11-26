import SwiftUI
import SwiftData
import FirebaseAnalytics

@main
struct YTLiteApp: App {
    @UIApplicationDelegateAdaptor(YTLiteAppDelegate.self) private var appDelegate
    @StateObject private var playback: PlaybackController
    @StateObject private var appModel = AppModel()
    @StateObject private var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer

    init() {
        FirebaseBootstrap.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        AppNotificationCenterDelegate.shared.install()
        let config = AppConfig.fromBundle()
        _authService = StateObject(wrappedValue: AuthService(config: config))
        modelContainer = Self.makeModelContainer()
        // Create playback + bind widget intents before SwiftUI `.task`.
        // `AudioPlaybackIntent` can wake a killed app and run `perform()` immediately.
        let playbackController = PlaybackController()
        _playback = StateObject(wrappedValue: playbackController)
        PhoneWidgetCommandBridge.shared.start(playback: playbackController)
        // Activate WC + playback host in init so a Watch `transferUserInfo` that wakes a
        // killed app can be handled before SwiftUI `.task` runs.
        WatchConnectivityBridge.shared.activate()
        WatchPlaybackHost.shared.start(playback: playbackController)
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
                .modifier(MacReleaseNoticeModifier())
                .task {
                    await Task.yield()
                    WatchConnectivityBridge.shared.activate()
                    WatchPlaybackHost.shared.start(playback: playback)
                    // Re-bind in case init raced; also drains any command still queued.
                    PhoneWidgetCommandBridge.shared.start(playback: playback)
                    playback.publishPhoneWidgetSnapshot(force: true)

                    // Resolve VIP before ads/ATT so VIP users skip UMP + AdMob entirely.
                    // Remote Config runs in parallel (offline flags, etc.).
                    async let remoteConfig = RemoteConfigStore.fetchAndActivate()
                    await VipStore.shared.refresh()
                    #if targetEnvironment(macCatalyst)
                    let cachedIds = await PlaybackMediaStore.shared.cachedSnapshots().map(\.videoId)
                    MacCachedMediaIndex.shared.replace(Set(cachedIds))
                    #endif
                    _ = await remoteConfig

                    // ATT / UMP only for non-VIP, and only while foreground-active.
                    if !VipStore.shared.isVipActive {
                        await AdConsentManager.requestTrackingAuthorizationAtLaunch()
                        await AdBootstrap.startIfNeeded()
                    } else {
                        AdProbe.log("launch.ads_skipped", "reason=vip")
                    }

                    appModel.syncAuth(authService)
                    ReviewPromptCoordinator.shared.recordActiveDay()
                    // StreamResolver WKWebView warms on first resolve that needs the bridge
                    // (avoid ~2s WebContent/GPU cost on every cold launch).
                    ColdStartVipOffer.shared.noteLaunchFlowReady()
                    #if targetEnvironment(macCatalyst)
                    await MacReleaseNotice.shared.check()
                    #endif
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
                        #if targetEnvironment(macCatalyst)
                        Task { await MacReleaseNotice.shared.check() }
                        #endif
                        AppAnalytics.appOpen(coldStart: false)
                        ReviewPromptCoordinator.shared.recordActiveDay()
                        playback.consumePendingDailyListenIfNeeded()
                        PhoneWidgetCommandBridge.shared.consumePending()
                        playback.publishPhoneWidgetSnapshot(force: true)
                        if playback.isPlaying {
                            playback.prepareForBackgroundPlayback()
                        }
                        Task {
                            await AdConsentManager.resumeDeferredPromptsIfNeeded()
                            await DailyListenNotificationScheduler.refresh(using: playback.libraryStore)
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
        #if targetEnvironment(macCatalyst)
        // The default store URL follows an App Group when one is present. The Mac
        // sandbox cannot write the iOS group container, so keep the library in this app.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.applicationSupportDirectory
        let directory = support.appendingPathComponent("MixtubeLibrary", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            schema: schema,
            url: directory.appendingPathComponent("library.store")
        )
        #else
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        #endif
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

/// No-op on iPhone. Mac compares the running version with the website release file.
private struct MacReleaseNoticeModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.modifier(MacReleaseNoticeAlert())
        #else
        content
        #endif
    }
}

#if targetEnvironment(macCatalyst)
@MainActor
final class MacReleaseNotice: ObservableObject {
    static let shared = MacReleaseNotice()

    struct Prompt: Identifiable, Equatable {
        let version: String
        let notes: String
        let url: URL
        var id: String { version }
    }

    @Published private(set) var prompt: Prompt?

    private let dismissedKey = "ytlite.mac-release.dismissed-version"
    private let feedURL = URL(string: "https://www.ytlite.cc/app-release.json")!
    private let fallbackDownloadURL = URL(string: "https://www.ytlite.cc/#download")!
    private var inFlight = false
    private var confirmed = false

    func check() async {
        guard !confirmed, prompt == nil, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        guard let remote = await fetch() else { return }
        confirmed = true

        let version = remote.version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return }
        let local = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard Self.isNewer(version, than: local) else { return }
        let dismissed = UserDefaults.standard.string(forKey: dismissedKey)
        guard dismissed != version else { return }

        prompt = Prompt(
            version: version,
            notes: remote.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            url: downloadURL(from: remote.url)
        )
    }

    func dismiss() {
        if let version = prompt?.version {
            UserDefaults.standard.set(version, forKey: dismissedKey)
        }
        prompt = nil
    }

    func openDownload() {
        if let url = prompt?.url {
            AppLinks.open(url)
        }
        dismiss()
    }

    private struct Feed: Decodable {
        struct Mac: Decodable {
            let version: String
            let url: String?
            let notes: String?
        }
        let mac: Mac
    }

    private func fetch() async -> Feed.Mac? {
        var request = URLRequest(
            url: feedURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(Feed.self, from: data).mac
        } catch {
            return nil
        }
    }

    private func downloadURL(from raw: String?) -> URL {
        guard let raw,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "www.ytlite.cc" || host == "ytlite.cc"
        else { return fallbackDownloadURL }
        return url
    }

    /// Numeric dotted versions. `1.10.0` is newer than `1.9.0`.
    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").map { Int($0) ?? 0 }
        let localParts = local.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(remoteParts.count, localParts.count, 1)
        for index in 0..<count {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let localValue = index < localParts.count ? localParts[index] : 0
            if remoteValue != localValue { return remoteValue > localValue }
        }
        return false
    }
}

private struct MacReleaseNoticeAlert: ViewModifier {
    @ObservedObject private var notice = MacReleaseNotice.shared

    func body(content: Content) -> some View {
        content.alert(
            notice.prompt.map { Lf("mac.release.title", $0.version) } ?? "",
            isPresented: Binding(
                get: { notice.prompt != nil },
                set: { showing in
                    if !showing { notice.dismiss() }
                }
            ),
            presenting: notice.prompt
        ) { _ in
            Button(L("mac.release.download")) { notice.openDownload() }
            Button(L("mac.release.later"), role: .cancel) { notice.dismiss() }
        } message: { prompt in
            Text(prompt.notes.isEmpty ? L("mac.release.message") : prompt.notes)
        }
    }
}
#endif
