import SwiftUI

/// Subscriptions / You tab — aligned with Android `YoutubeYouScreen`.
struct YouView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var store
    @StateObject private var viewModel = YouViewModel()
    @State private var showPlayer = false

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
            .background(YTLiteColor.background)
            .navigationBarHidden(true)
            .task(id: "\(auth.userId ?? "nil")-\(auth.googleAccessToken != nil)") {
                guard auth.isAuthenticated, auth.googleAccessToken != nil else {
                    if auth.googleAccessToken == nil {
                        viewModel.clear()
                    }
                    return
                }
                let token = await auth.ensureFreshGoogleAccessToken()
                await viewModel.loadYouTubeShelves(
                    token: token,
                    apiKey: appModel.config.youtubeDataAPIKey
                )
            }
            .sheet(isPresented: $showPlayer) {
                NavigationStack {
                    PlayerDetailView()
                }
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

            SignInOptionsView(auth: auth) {
                appModel.syncAuth(auth)
                await viewModel.loadYouTubeShelves(
                    token: auth.googleAccessToken,
                    apiKey: appModel.config.youtubeDataAPIKey
                )
                if let store {
                    await LibrarySyncService(auth: auth).syncBidirectional(store: store)
                }
            }
            .padding(.top, YTLiteLayout.stackTight)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Apple (or any session without YouTube OAuth) — explain and guide to Google.
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
                            await auth.signInWithGoogle()
                            appModel.syncAuth(auth)
                            await viewModel.loadYouTubeShelves(
                                token: auth.googleAccessToken,
                                apiKey: appModel.config.youtubeDataAPIKey
                            )
                        }
                    } label: {
                        Text(L("you.sign_in_with_google_for_youtube"))
                            .font(YTLiteType.labelEmphasized)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(YTLiteColor.signInBlue, in: Capsule())
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
    }

    // MARK: - Authenticated (Android YoutubeYouScreen order)

    private var signedInContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                profileHeader

                if viewModel.needsYoutubeReauth {
                    youtubeReauthBanner
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
                    emptyText: viewModel.needsYoutubeReauth
                        ? "Sign in again to grant YouTube access"
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
                    emptyText: viewModel.needsYoutubeReauth
                        ? "Sign in again to grant YouTube access"
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
                                    YoutubePlaylistItemsView(
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
                    emptyText: viewModel.needsYoutubeReauth
                        ? "Sign in again to grant YouTube access"
                        : L("you.playlist_empty"),
                    emptySystemImage: "hand.thumbsup",
                    showViewAll: !viewModel.liked.isEmpty
                ) {
                    EmptyView()
                } viewAll: {
                    YoutubePlaylistItemsView(
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
                                    showPlayer = true
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable {
            let token = await auth.ensureFreshGoogleAccessToken()
            await viewModel.loadYouTubeShelves(
                token: token,
                apiKey: appModel.config.youtubeDataAPIKey
            )
        }
    }

    private var youtubeReauthBanner: some View {
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
                    await auth.signInWithGoogle()
                    appModel.syncAuth(auth)
                    guard auth.lastError == nil else { return }
                    await viewModel.loadYouTubeShelves(
                        token: auth.googleAccessToken,
                        apiKey: appModel.config.youtubeDataAPIKey
                    )
                }
            } label: {
                Text(L("you.grant_access"))
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(YTLiteColor.signInBlue, in: Capsule())
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
                        await viewModel.loadYouTubeShelves(
                            token: auth.googleAccessToken,
                            apiKey: appModel.config.youtubeDataAPIKey
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
    @Published private(set) var channels: [YoutubeDataApiClient.SubscriptionChannel] = []
    @Published private(set) var playlists: [YoutubeDataApiClient.PlaylistPreview] = []
    @Published private(set) var liked: [VideoItem] = []
    @Published private(set) var likedPlaylistId: String?
    @Published private(set) var needsYoutubeReauth = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var isLoading = false

    func clear() {
        channels = []
        playlists = []
        liked = []
        likedPlaylistId = nil
        needsYoutubeReauth = false
        errorMessage = nil
        hasLoadedOnce = true
    }

    func loadYouTubeShelves(token: String?, apiKey: String) async {
        // Run fetch outside the caller's cancellation domain (SwiftUI `.refreshable`
        // often cancels when `@Published` flips, aborting URLSession mid-flight).
        let token = token
        let apiKey = apiKey
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task.detached(priority: .userInitiated) {
                let snap = await YoutubeDataApiClient.loadYouPage(
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

    func applySnapshot(_ snap: YoutubeDataApiClient.YouPageSnapshot) {
        hasLoadedOnce = true
        isLoading = false

        // Detached fetch should not surface UI-cancel noise.
        if snap.wasCancelled {
            errorMessage = nil
            return
        }

        if snap.needsYoutubeReauth {
            needsYoutubeReauth = true
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

        needsYoutubeReauth = false
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
    let channel: YoutubeDataApiClient.SubscriptionChannel

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: coverURL)
                .frame(width: 160, height: 90)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(YTLiteType.meta.weight(.semibold))
                .foregroundStyle(YTLiteColor.onSurface)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)
            Text(subtitle)
                .font(YTLiteType.iconCaption)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)
        }
    }
}

private struct YouVideoShelfCard: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    var durationText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                VideoThumbnail(
                    url: imageURL,
                    durationText: durationText,
                    width: 160,
                    height: 90,
                    cornerRadius: 8,
                    badgePadding: 4
                )
                Text(title)
                    .font(YTLiteType.meta.weight(.semibold))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(2)
                    .frame(width: 160, alignment: .leading)
                Text(subtitle)
                    .font(YTLiteType.iconCaption)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View all pages

struct SubscriptionChannelsListView: View {
    let channels: [YoutubeDataApiClient.SubscriptionChannel]

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
        .background(YTLiteColor.background)
        .navigationTitle(L("you.subscriptions"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
    }
}

struct YouPlaylistsListView: View {
    let playlists: [YoutubeDataApiClient.PlaylistPreview]

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
                        YoutubePlaylistItemsView(
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
        .background(YTLiteColor.background)
        .navigationTitle(L("you.playlists"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
    }
}

/// Remote YouTube playlist items via Data API (not local LibraryStore).
struct YoutubePlaylistItemsView: View {
    let playlistId: String
    let title: String

    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @State private var items: [VideoItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPlayer = false

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
            } else if items.isEmpty {
                ContentUnavailableView(
                    L("library.empty_playlist"),
                    systemImage: "play.rectangle",
                    description: Text(L("you.playlist_empty"))
                )
            } else {
                List(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        playback.play(items: items, startAt: index, sourcePlaylistId: playlistId)
                        showPlayer = true
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: item.thumbnailURL)
                                .frame(width: 120, height: 68)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(YTLiteType.rowTitle)
                                    .foregroundStyle(YTLiteColor.onSurface)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(item.channelName)
                                    .font(YTLiteType.meta)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(YTLiteColor.background)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(YTLiteColor.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
        .task {
            await load()
        }
        .sheet(isPresented: $showPlayer) {
            NavigationStack {
                PlayerDetailView()
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let token = auth.googleAccessToken else {
            errorMessage = "Sign in again to grant YouTube access"
            items = []
            return
        }
        let key = appModel.config.youtubeDataAPIKey
        guard !key.isEmpty else {
            errorMessage = "YouTube Data API key is not configured"
            items = []
            return
        }
        items = await YoutubeDataApiClient.listPlaylistItems(
            token: token,
            apiKey: key,
            playlistId: playlistId,
            maxResults: 50
        ) ?? []
        if items.isEmpty {
            errorMessage = nil
        }
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
        .background(YTLiteColor.background)
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
        .background(YTLiteColor.background)
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
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPlayer = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(YTLiteColor.accent)
            } else if videos.isEmpty {
                ContentUnavailableView(L("common.no_videos"), systemImage: "play.slash", description: Text(errorMessage ?? ""))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, item in
                            FeedVideoCard(
                                item: item,
                                onTap: {
                                    playback.play(
                                        items: videos,
                                        startAt: index,
                                        sourcePlaylistId: "yt_channel:\(channel.channelId)"
                                    )
                                    showPlayer = true
                                },
                                onMore: {
                                    trackActions.present(item: item)
                                }
                            )
                        }
                    }
                }
            }
        }
        .background(YTLiteColor.background)
        .navigationTitle(channel.title)
        .onChange(of: trackActions.listEpoch) { _, _ in
            videos = store?.filterNotInterested(videos) ?? videos
        }
        .task(id: channel.channelId) {
            await loadVideos()
        }
        .sheet(isPresented: $showPlayer) {
            NavigationStack { PlayerDetailView() }
        }
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
            videos = store?.filterNotInterested(labeled) ?? labeled
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
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPlayer = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(YTLiteColor.accent)
            } else if videos.isEmpty {
                ContentUnavailableView(L("library.empty_playlist"), systemImage: "list.bullet", description: Text(errorMessage ?? ""))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, item in
                            FeedVideoCard(
                                item: item,
                                onTap: {
                                    playback.play(
                                        items: videos,
                                        startAt: index,
                                        sourcePlaylistId: "yt_playlist:\(playlist.playlistId)"
                                    )
                                    showPlayer = true
                                },
                                onMore: {
                                    trackActions.present(item: item)
                                }
                            )
                        }
                    }
                }
            }
        }
        .background(YTLiteColor.background)
        .navigationTitle(playlist.title)
        .onChange(of: trackActions.listEpoch) { _, _ in
            videos = store?.filterNotInterested(videos) ?? videos
        }
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                let fetched = try await InnerTubeClient.fetchPlaylistVideos(playlistId: playlist.playlistId)
                videos = store?.filterNotInterested(fetched) ?? fetched
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showPlayer) {
            NavigationStack { PlayerDetailView() }
        }
    }
}
