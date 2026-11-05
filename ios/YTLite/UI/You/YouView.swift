import SwiftUI

/// Subscriptions / You tab — aligned with Android `CatalogYouScreen`.
struct YouView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var store
    @StateObject private var viewModel = YouViewModel()
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isAuthenticated {
                    subsSignInEmpty
                } else if auth.googleAccessToken == nil {
                    appleSignedInYouPlaceholder
                } else if !viewModel.hasLoadedOnce {
                    ProgressView()
                        .tint(YTLiteColor.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    signedInContent
                }
            }
            .ytLiteContentWidth(enabled: YTLiteAdaptive.isRegularWidth(horizontalSizeClass))
            .ytLiteAppBackground()
            .navigationBarHidden(true)
            .task(id: "\(auth.userId ?? "nil")-\(auth.googleAccessToken != nil)") {
                guard auth.isAuthenticated, auth.googleAccessToken != nil else {
                    if auth.googleAccessToken == nil {
                        viewModel.clear()
                    }
                    return
                }
                let token = await auth.ensureFreshGoogleAccessToken()
                await viewModel.loadCatalogShelves(
                    token: token,
                    apiKey: appModel.config.catalogDataAPIKey
                )
            }
        }
    }

    // MARK: - Guest

    private var subsSignInEmpty: some View {
        VStack(spacing: 20) {
            Spacer()
            SubsEmptyGraphic()
                .frame(width: 120, height: 100)

            Text(L("you.dont_miss"))
                .font(YTLiteType.emptyTitle)
                .foregroundStyle(YTLiteColor.onSurface)
                .multilineTextAlignment(.center)

            Text(L("you.sign_in_desc"))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            SignInOptionsView(auth: auth, analyticsSource: "you") {
                appModel.syncAuth(auth)
                await viewModel.loadCatalogShelves(
                    token: auth.googleAccessToken,
                    apiKey: appModel.config.catalogDataAPIKey
                )
                if let store {
                    let t0 = SyncProbe.now()
                    let trace = SyncProbe.newTraceId()
                    SyncProbe.currentTrace = trace
                    SyncProbe.logTrace("sync.start", "source=you_onSignedIn")
                    await LibrarySyncService(auth: auth).syncBidirectional(store: store)
                    SyncProbe.logTrace("sync.end", "source=you_onSignedIn total_ms=\(SyncProbe.ms(since: t0))")
                }
            }
            .padding(.top, YTLiteLayout.stackTight)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Apple (or any session without catalog OAuth) — explain and guide to Google.
    private var appleSignedInYouPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileHeader
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("you.apple_needs_google_title"))
                        .font(YTLiteType.rowTitle)
                        .foregroundStyle(YTLiteColor.onSurface)
                    Text(L("you.apple_needs_google_desc"))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    Button {
                        Task {
                            await auth.signInWithGoogle(source: "you")
                            appModel.syncAuth(auth)
                            await viewModel.loadCatalogShelves(
                                token: auth.googleAccessToken,
                                apiKey: appModel.config.catalogDataAPIKey
                            )
                        }
                    } label: {
                        Text(L("you.sign_in_with_google_for_catalog"))
                            .font(YTLiteType.labelEmphasized)
                            .foregroundStyle(YTLiteColor.onAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(YTLiteColor.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(auth.isBusy)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    YTLiteColor.surfaceVariant,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .padding(.horizontal, 16)
            }
        }
        .ytLiteMiniPlayerScrollInset()
    }

    // MARK: - Authenticated (Android CatalogYouScreen order)

    private var signedInContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                profileHeader

                if viewModel.needsCatalogReauth {
                    catalogReauthBanner
                }

                if let err = viewModel.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.danger)
                        .padding(.horizontal, 16)
                }

                youSection(
                    title: L("you.subscriptions"),
                    isEmpty: viewModel.channels.isEmpty,
                    emptyText: viewModel.needsCatalogReauth
                        ? "Sign in again to grant catalog access"
                        : L("you.channels_empty"),
                    emptySystemImage: "person.2",
                    showViewAll: !viewModel.channels.isEmpty
                ) {
                    EmptyView()
                } viewAll: {
                    SubscriptionChannelsListView(channels: viewModel.channels)
                } content: {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.channels) { channel in
                                NavigationLink {
                                    ChannelVideosView(channel: channel.asChannelItem)
                                } label: {
                                    YouChannelCard(channel: channel)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }

                youSection(
                    title: L("you.playlists"),
                    isEmpty: viewModel.playlists.isEmpty,
                    emptyText: viewModel.needsCatalogReauth
                        ? "Sign in again to grant catalog access"
                        : L("you.playlists_empty"),
                    emptySystemImage: "list.bullet.rectangle",
                    showViewAll: !viewModel.playlists.isEmpty
                ) {
                    Button {
                        trackActions.showToast(L("toast.create_playlist_unavailable"))
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(YTLiteColor.onSurface)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("you.new_playlist"))
                } viewAll: {
                    YouPlaylistsListView(playlists: viewModel.playlists)
                } content: {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.playlists) { playlist in
                                NavigationLink {
                                    CatalogPlaylistItemsView(
                                        playlistId: playlist.playlistId,
                                        title: playlist.title
                                    )
                                } label: {
                                    YouPlaylistCard(
                                        title: playlist.title,
                                        coverURL: playlist.thumbnailUrl.flatMap(URL.init(string:)),
                                        subtitle: playlist.itemCount.map { $0 == 1 ? "1 video" : "\($0) videos" }
                                            ?? "Playlist"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }

                youSection(
                    title: L("you.liked"),
                    isEmpty: viewModel.liked.isEmpty,
                    emptyText: viewModel.needsCatalogReauth
                        ? "Sign in again to grant catalog access"
                        : L("you.playlist_empty"),
                    emptySystemImage: "hand.thumbsup",
                    showViewAll: !viewModel.liked.isEmpty
                ) {
                    EmptyView()
                } viewAll: {
                    CatalogPlaylistItemsView(
                        playlistId: viewModel.likedPlaylistId ?? "LL",
                        title: L("you.liked")
                    )
                } content: {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(viewModel.liked.enumerated()), id: \.element.id) { index, item in
                                YouVideoShelfCard(
                                    title: item.title,
                                    subtitle: item.channelName,
                                    imageURL: item.thumbnailURL,
                                    durationText: item.durationText
                                ) {
                                    playback.play(
                                        items: viewModel.liked,
                                        startAt: index,
                                        sourcePlaylistId: viewModel.likedPlaylistId
                                    )
                                    playerPresentation.present()
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .ytLiteMiniPlayerScrollInset()
        .refreshable {
            let token = await auth.ensureFreshGoogleAccessToken()
            await viewModel.loadCatalogShelves(
                token: token,
                apiKey: appModel.config.catalogDataAPIKey
            )
        }
    }

    private var catalogReauthBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("you.access_needed"))
                .font(YTLiteType.rowTitle)
                .foregroundStyle(YTLiteColor.onSurface)
            Text(L("you.access_desc"))
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Button {
                Task {
                    // Prefer re-consent without local sign-out dance (avoids wiping shelves on cancel).
                    await auth.signInWithGoogle(source: "you")
                    appModel.syncAuth(auth)
                    guard auth.lastError == nil else { return }
                    await viewModel.loadCatalogShelves(
                        token: auth.googleAccessToken,
                        apiKey: appModel.config.catalogDataAPIKey
                    )
                }
            } label: {
                Text(L("you.grant_access"))
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(YTLiteColor.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(YTLiteColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(auth.isBusy)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YTLiteColor.surfaceVariant, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                FeedChannelAvatar(
                    url: auth.avatarURL,
                    channelName: auth.displayName,
                    size: 72
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(auth.displayName)
                        .font(.title2.bold())
                        .foregroundStyle(YTLiteColor.onSurface)
                        .lineLimit(1)
                    if let handle = auth.emailHandle, !handle.isEmpty {
                        Text(handle)
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        await auth.switchAccount()
                        appModel.syncAuth(auth)
                        await viewModel.loadCatalogShelves(
                            token: auth.googleAccessToken,
                            apiKey: appModel.config.catalogDataAPIKey
                        )
                    }
                } label: {
                    Text(L("you.switch_account"))
                        .font(YTLiteType.labelEmphasized)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(YTLiteColor.surfaceVariant, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(auth.isBusy)

                Button {
                    Task {
                        await auth.signOut()
                        appModel.syncAuth(auth)
                        viewModel.clear()
                    }
                } label: {
                    Text(L("common.sign_out"))
                        .font(YTLiteType.labelEmphasized)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(Capsule().stroke(YTLiteColor.onSurfaceVariant.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(auth.isBusy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Section chrome

    private func youSection<Trailing: View, Destination: View, Content: View>(
        title: String,
        isEmpty: Bool,
        emptyText: String,
        emptySystemImage: String,
        showViewAll: Bool,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder viewAll: () -> Destination,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(YTLiteType.sectionTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 0)
                trailing()
                if showViewAll {
                    NavigationLink {
                        viewAll()
                    } label: {
                        HStack(spacing: 2) {
                            Text(L("common.view_all"))
                                .font(YTLiteType.meta.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            if isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: emptySystemImage)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    Text(emptyText)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                content()
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - View model

@MainActor
final class YouViewModel: ObservableObject {
    @Published private(set) var channels: [CatalogDataApiClient.SubscriptionChannel] = []
    @Published private(set) var playlists: [CatalogDataApiClient.PlaylistPreview] = []
    @Published private(set) var liked: [VideoItem] = []
    @Published private(set) var likedPlaylistId: String?
    @Published private(set) var needsCatalogReauth = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var isLoading = false

    func clear() {
        channels = []
        playlists = []
        liked = []
        likedPlaylistId = nil
        needsCatalogReauth = false
        errorMessage = nil
        hasLoadedOnce = true
    }

    func loadCatalogShelves(token: String?, apiKey: String) async {
        // Run fetch outside the caller's cancellation domain (SwiftUI `.refreshable`
        // often cancels when `@Published` flips, aborting URLSession mid-flight).
        let token = token
        let apiKey = apiKey
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task.detached(priority: .userInitiated) {
                let snap = await CatalogDataApiClient.loadYouPage(
                    oauthAccessToken: token,
                    apiKey: apiKey
                )
                await MainActor.run {
                    self.applySnapshot(snap)
                    cont.resume()
                }
            }
        }
    }

    func applySnapshot(_ snap: CatalogDataApiClient.YouPageSnapshot) {
        hasLoadedOnce = true
        isLoading = false

        // Detached fetch should not surface UI-cancel noise.
        if snap.wasCancelled {
            errorMessage = nil
            return
        }

        if snap.needsCatalogReauth {
            needsCatalogReauth = true
            errorMessage = nil
            // Still apply any partial shelves (e.g. InnerTube liked) when present.
            if !snap.subscriptions.isEmpty { channels = snap.subscriptions }
            if !snap.playlists.isEmpty { playlists = snap.playlists }
            if !snap.liked.isEmpty {
                liked = snap.liked
                likedPlaylistId = snap.likedPlaylistId
            }
            return
        }

        needsCatalogReauth = false
        errorMessage = snap.errorMessage
        channels = snap.subscriptions
        playlists = snap.playlists
        liked = snap.liked
        likedPlaylistId = snap.likedPlaylistId

        let hasContent = !snap.subscriptions.isEmpty
            || !snap.playlists.isEmpty
            || !snap.liked.isEmpty
        ReviewPromptCoordinator.shared.recordYouShelfSuccess(hasContent: hasContent)
    }
}

// MARK: - Cards

private struct YouChannelCard: View {
    let channel: CatalogDataApiClient.SubscriptionChannel

    var body: some View {
        VStack(spacing: 8) {
            FeedChannelAvatar(
                url: channel.avatarUrl.flatMap(URL.init(string:)),
                channelName: channel.title,
                size: 64
            )
            Text(channel.title)
                .font(YTLiteType.meta.weight(.semibold))
                .foregroundStyle(YTLiteColor.onSurface)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)
        }
        .frame(width: 80)
    }
}

private struct YouPlaylistCard: View {
    let title: String
    let coverURL: URL?
    let subtitle: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var cardWidth: CGFloat {
        YTLiteAdaptive.isRegularWidth(horizontalSizeClass) ? 220 : 160
    }

    private var cardHeight: CGFloat { cardWidth * 9 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: coverURL)
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(YTLiteType.meta.weight(.semibold))
                .foregroundStyle(YTLiteColor.onSurface)
                .lineLimit(2)
                .frame(width: cardWidth, alignment: .leading)
            Text(subtitle)
                .font(YTLiteType.iconCaption)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
        }
    }
}

private struct YouVideoShelfCard: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    var durationText: String? = nil
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var cardWidth: CGFloat {
        YTLiteAdaptive.isRegularWidth(horizontalSizeClass) ? 220 : 160
    }

    private var cardHeight: CGFloat { cardWidth * 9 / 16 }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                VideoThumbnail(
                    url: imageURL,
                    durationText: durationText,
                    width: cardWidth,
                    height: cardHeight,
                    cornerRadius: 8,
                    badgePadding: 4
                )
                Text(title)
                    .font(YTLiteType.meta.weight(.semibold))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(2)
                    .frame(width: cardWidth, alignment: .leading)
                Text(subtitle)
                    .font(YTLiteType.iconCaption)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View all pages

struct SubscriptionChannelsListView: View {
    let channels: [CatalogDataApiClient.SubscriptionChannel]

    var body: some View {
        Group {
            if channels.isEmpty {
                ContentUnavailableView(
                    L("you.subscriptions"),
                    systemImage: "person.2",
                    description: Text(L("you.channels_empty"))
                )
            } else {
                List(channels) { channel in
                    NavigationLink {
                        ChannelVideosView(channel: channel.asChannelItem)
                    } label: {
                        HStack(spacing: 14) {
                            FeedChannelAvatar(
                                url: channel.avatarUrl.flatMap(URL.init(string:)),
                                channelName: channel.title,
                                size: 48
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.title)
                                    .font(YTLiteType.rowTitle)
                                    .foregroundStyle(YTLiteColor.onSurface)
                                    .lineLimit(1)
                                Text(L("common.channel"))
                                    .font(YTLiteType.meta)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(YTLiteColor.background)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .ytLiteAppBackground()
        .ytLiteMiniPlayerScrollInset()
        .navigationTitle(L("you.subscriptions"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
    }
}

struct YouPlaylistsListView: View {
    let playlists: [CatalogDataApiClient.PlaylistPreview]

    var body: some View {
        Group {
            if playlists.isEmpty {
                ContentUnavailableView(
                    L("you.playlists"),
                    systemImage: "list.bullet.rectangle",
                    description: Text(L("you.playlists_empty"))
                )
            } else {
                List(playlists) { playlist in
                    NavigationLink {
                        CatalogPlaylistItemsView(
                            playlistId: playlist.playlistId,
                            title: playlist.title
                        )
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: playlist.thumbnailUrl.flatMap(URL.init(string:)))
                                .frame(width: 64, height: 36)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.title)
                                    .font(YTLiteType.rowTitle)
                                    .foregroundStyle(YTLiteColor.onSurface)
                                    .lineLimit(1)
                                Text(
                                    playlist.itemCount.map { $0 == 1 ? "1 video" : "\($0) videos" }
                                        ?? "Playlist"
                                )
                                    .font(YTLiteType.meta)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(YTLiteColor.background)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .ytLiteAppBackground()
        .ytLiteMiniPlayerScrollInset()
        .navigationTitle(L("you.playlists"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
    }
}

/// Remote catalog playlist items via Data API (not local LibraryStore).
struct CatalogPlaylistItemsView: View {
    let playlistId: String
    let title: String

    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @State private var items: [VideoItem] = []
    @State private var itemsVersion: Int = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @EnvironmentObject private var playerPresentation: PlayerPresentation

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(YTLiteColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    L("error.load_playlist"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                MediaTracksListPane(
                    tracks: items,
                    tracksVersion: itemsVersion,
                    emptyTitle: L("library.empty_playlist"),
                    emptySystemImage: "play.rectangle",
                    emptyDescription: L("you.playlist_empty"),
                    onPlay: { index in
                        playback.play(items: items, startAt: index, sourcePlaylistId: playlistId)
                        playerPresentation.present()
                    }
                )
                .equatable()
            }
        }
        .ytLiteAppBackground()
        .ytLiteMiniPlayerScrollInset()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let token = auth.googleAccessToken else {
            errorMessage = "Sign in again to grant catalog access"
            replaceItems([])
            return
        }
        let key = appModel.config.catalogDataAPIKey
        guard !key.isEmpty else {
            errorMessage = "Catalog Data API key is not configured"
            replaceItems([])
            return
        }
        let next = await CatalogDataApiClient.listPlaylistItems(
            token: token,
            apiKey: key,
            playlistId: playlistId,
            maxResults: 50
        ) ?? []
        replaceItems(next)
        if items.isEmpty {
            errorMessage = nil
        }
    }

    private func replaceItems(_ next: [VideoItem]) {
        if next.map(\.videoId) != items.map(\.videoId) {
            itemsVersion &+= 1
        }
        items = next
    }
}

// MARK: - Guest graphic

private struct SubsEmptyGraphic: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(YTLiteColor.onSurface.opacity(0.12))
                .frame(width: 88, height: 56)
                .rotationEffect(.degrees(-8))
                .offset(x: -18, y: -8)
            RoundedRectangle(cornerRadius: 10)
                .fill(YTLiteColor.onSurface.opacity(0.18))
                .frame(width: 92, height: 58)
                .rotationEffect(.degrees(6))
                .offset(x: 16, y: -4)
            RoundedRectangle(cornerRadius: 10)
                .fill(YTLiteColor.onSurface.opacity(0.28))
                .frame(width: 96, height: 60)
            Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(YTLiteColor.onSurface.opacity(0.85))
        }
    }
}

// MARK: - Deep browse (channel / playlist search retained for Library / links)

struct ChannelSearchView: View {
    @State private var query = ""
    @State private var results: [ChannelItem] = []
    @State private var isLoading = false

    var body: some View {
        List(results) { channel in
            NavigationLink {
                ChannelVideosView(channel: channel)
            } label: {
                HStack(spacing: YTLiteLayout.stackLoose) {
                    RemoteImage(url: channel.thumbnailURL)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    VStack(alignment: .leading) {
                        Text(channel.title)
                            .font(YTLiteType.rowTitle)
                            .foregroundStyle(YTLiteColor.onSurface)
                        Text(channel.subtitle)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .listRowBackground(YTLiteColor.background)
            }
        }
        .scrollContentBackground(.hidden)
        .ytLiteAppBackground()
        .ytLiteMiniPlayerScrollInset()
        .navigationTitle(L("you.channels"))
        .searchable(text: $query, prompt: "Search channels")
        .onSubmit(of: .search) { Task { await search() } }
        .overlay { if isLoading { ProgressView().tint(YTLiteColor.accent) } }
    }

    private func search() async {
        isLoading = true
        defer { isLoading = false }
        results = (try? await InnerTubeClient.searchChannels(query: query)) ?? []
    }
}

struct PlaylistSearchView: View {
    @State private var query = ""
    @State private var results: [PlaylistPreview] = []
    @State private var isLoading = false

    var body: some View {
        List(results) { playlist in
            NavigationLink {
                PlaylistVideosBrowserView(playlist: playlist)
            } label: {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                        Text(playlist.title)
                            .font(YTLiteType.rowTitle)
                            .foregroundStyle(YTLiteColor.onSurface)
                        Text(playlist.subtitle)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .listRowBackground(YTLiteColor.background)
            }
        }
        .scrollContentBackground(.hidden)
        .ytLiteAppBackground()
        .ytLiteMiniPlayerScrollInset()
        .navigationTitle(L("you.playlists"))
        .searchable(text: $query, prompt: "Search playlists")
        .onSubmit(of: .search) { Task { await search() } }
        .overlay { if isLoading { ProgressView().tint(YTLiteColor.accent) } }
    }

    private func search() async {
        isLoading = true
        defer { isLoading = false }
        results = (try? await InnerTubeClient.searchPlaylists(query: query)) ?? []
    }
}

struct ChannelVideosView: View {
    let channel: ChannelItem
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var store
    @State private var videos: [VideoItem] = []
    @State private var videosVersion: Int = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSubscribed = false
    @EnvironmentObject private var playerPresentation: PlayerPresentation

    private var canSubscribe: Bool {
        ChannelID.isBrowsable(channel.channelId)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(YTLiteColor.accent)
            } else {
                MediaTracksListPane(
                    tracks: videos,
                    tracksVersion: videosVersion,
                    emptyTitle: L("common.no_videos"),
                    emptyDescription: errorMessage ?? "",
                    onPlay: { index in
                        playback.play(
                            items: videos,
                            startAt: index,
                            sourcePlaylistId: "yt_channel:\(channel.channelId)"
                        )
                        playerPresentation.present()
                    },
                    onMore: { trackActions.present(item: $0) }
                )
                .equatable()
            }
        }
        .ytLiteAppBackground()
        .ytLiteMiniPlayerScrollInset()
        .navigationTitle(channel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if canSubscribe {
                    Button {
                        toggleSubscribe()
                    } label: {
                        Text(isSubscribed ? L("player.subscribed") : L("player.subscribe"))
                            .font(YTLiteType.badge)
                            .foregroundStyle(isSubscribed ? YTLiteColor.onSurface : YTLiteColor.onMedia)
                            .padding(.horizontal, YTLiteLayout.stackLoose)
                            .padding(.vertical, 6)
                            .background(
                                isSubscribed ? YTLiteColor.surfaceVariant : YTLiteColor.accent,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { refreshSubscribeState() }
        .onChange(of: trackActions.listEpoch) { _, _ in
            replaceVideos(store?.filterNotInterested(videos) ?? videos)
            refreshSubscribeState()
        }
        .onChange(of: playback.isChannelSubscribed) { _, _ in
            refreshSubscribeState()
        }
        .task(id: channel.channelId) {
            refreshSubscribeState()
            await loadVideos()
        }
    }

    private func replaceVideos(_ next: [VideoItem]) {
        if next.map(\.videoId) != videos.map(\.videoId) {
            videosVersion &+= 1
        }
        videos = next
    }

    private func refreshSubscribeState() {
        isSubscribed = store?.isSubscribed(channelId: channel.channelId) ?? false
    }

    private func toggleSubscribe() {
        guard canSubscribe else { return }
        let avatar = channel.thumbnailURL?.absoluteString
        let nowSubscribed = store?.toggleSubscribeChannel(
            channelId: channel.channelId,
            title: channel.title,
            avatarUrl: avatar
        ) ?? false
        isSubscribed = nowSubscribed
        if playback.nowPlaying?.channelId == channel.channelId {
            playback.refreshSubscribeState()
        }
        trackActions.showToast(nowSubscribed ? L("player.subscribed") : L("player.unsubscribed"))
        trackActions.notifyListsChanged()
    }

    private func loadVideos() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await InnerTubeClient.fetchChannelUploads(channelId: channel.channelId)
            guard !Task.isCancelled else { return }
            let labeled = fetched.map { item -> VideoItem in
                guard item.channelName.isEmpty else { return item }
                return VideoItem(
                    videoId: item.videoId,
                    title: item.title,
                    channelName: channel.title,
                    thumbnailURL: item.thumbnailURL,
                    channelAvatarURL: item.channelAvatarURL ?? channel.thumbnailURL,
                    durationText: item.durationText,
                    viewCountText: item.viewCountText,
                    publishedTimeText: item.publishedTimeText
                )
            }
            replaceVideos(store?.filterNotInterested(labeled) ?? labeled)
            if videos.isEmpty {
                errorMessage = "No uploads found for this channel"
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

struct PlaylistVideosBrowserView: View {
    let playlist: PlaylistPreview
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var store
    @State private var videos: [VideoItem] = []
    @State private var videosVersion: Int = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @EnvironmentObject private var playerPresentation: PlayerPresentation

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(YTLiteColor.accent)
            } else {
                MediaTracksListPane(
                    tracks: videos,
                    tracksVersion: videosVersion,
                    emptyTitle: L("library.empty_playlist"),
                    emptySystemImage: "list.bullet",
                    emptyDescription: errorMessage ?? "",
                    onPlay: { index in
                        playback.play(
                            items: videos,
                            startAt: index,
                            sourcePlaylistId: "yt_playlist:\(playlist.playlistId)"
                        )
                        playerPresentation.present()
                    },
                    onMore: { trackActions.present(item: $0) }
                )
                .equatable()
            }
        }
        .ytLiteAppBackground()
        .ytLiteMiniPlayerScrollInset()
        .navigationTitle(playlist.title)
        .onChange(of: trackActions.listEpoch) { _, _ in
            replaceVideos(store?.filterNotInterested(videos) ?? videos)
        }
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                let fetched = try await InnerTubeClient.fetchPlaylistVideos(playlistId: playlist.playlistId)
                replaceVideos(store?.filterNotInterested(fetched) ?? fetched)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func replaceVideos(_ next: [VideoItem]) {
        if next.map(\.videoId) != videos.map(\.videoId) {
            videosVersion &+= 1
        }
        videos = next
    }
}
