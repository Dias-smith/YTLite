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
            .task(id: auth.userId) {
                guard auth.isAuthenticated else { return }
                viewModel.reload(store: store)
            }
            .onChange(of: appModel.libraryRevision) { _, _ in
                guard auth.isAuthenticated else { return }
                viewModel.reload(store: store)
            }
            .onChange(of: trackActions.listEpoch) { _, _ in
                viewModel.reload(store: store)
            }
            .sheet(isPresented: $showPlayer) {
                NavigationStack {
                    PlayerDetailView()
                        .preferredColorScheme(.dark)
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

            Text("Don't miss new videos")
                .font(YTLiteType.emptyTitle)
                .foregroundStyle(YTLiteColor.onSurface)
                .multilineTextAlignment(.center)

            Text("Sign in to see updates from your favorite YouTube channels")
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task {
                    await auth.signInWithGoogle()
                    appModel.syncAuth(auth)
                    viewModel.reload(store: store)
                    if let store, auth.isAuthenticated {
                        Task {
                            await LibrarySyncService(auth: auth).syncBidirectional(store: store)
                            viewModel.reload(store: store)
                        }
                    }
                }
            } label: {
                Text(auth.isBusy ? "Signing in…" : "Sign in")
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .padding(.horizontal, 28)
                    .padding(.vertical, YTLiteLayout.stackLoose)
                    .background(YTLiteColor.signInBlue, in: Capsule())
            }
            .disabled(auth.isBusy || !auth.isConfigured)
            .padding(.top, YTLiteLayout.stackTight)

            if let err = auth.lastError {
                Text(err)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.danger)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Authenticated (Android YoutubeYouScreen order)

    private var signedInContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                profileHeader

                youSection(
                    title: "Subscriptions",
                    isEmpty: viewModel.channels.isEmpty,
                    emptyText: "Channels you subscribe to in the player show up here",
                    emptySystemImage: "person.2",
                    showViewAll: !viewModel.channels.isEmpty
                ) {
                    EmptyView()
                } viewAll: {
                    SubscriptionChannelsListView(channels: viewModel.channels)
                } content: {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.channels, id: \.channelId) { channel in
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
                    title: "Playlists",
                    isEmpty: viewModel.playlists.isEmpty,
                    emptyText: "Playlists you create appear here",
                    emptySystemImage: "list.bullet.rectangle",
                    showViewAll: !viewModel.playlists.isEmpty
                ) {
                    Button {
                        trackActions.showToast("Creating playlists isn't available here yet")
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(YTLiteColor.onSurface)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New playlist")
                } viewAll: {
                    YouPlaylistsListView(playlists: viewModel.playlists)
                } content: {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.playlists, id: \.playlistId) { playlist in
                                NavigationLink {
                                    PlaylistDetailView(playlist: playlist) {
                                        viewModel.reload(store: store)
                                    }
                                } label: {
                                    YouPlaylistCard(
                                        title: playlistDisplayName(playlist),
                                        coverURL: playlistCoverURL(playlist),
                                        subtitle: playlistSubtitle(playlist)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }

                youSection(
                    title: "Liked videos",
                    isEmpty: viewModel.liked.isEmpty,
                    emptyText: "Videos you like will show up here",
                    emptySystemImage: "hand.thumbsup",
                    showViewAll: viewModel.likedPlaylist != nil && !viewModel.liked.isEmpty
                ) {
                    EmptyView()
                } viewAll: {
                    Group {
                        if let liked = viewModel.likedPlaylist {
                            PlaylistDetailView(playlist: liked) {
                                viewModel.reload(store: store)
                            }
                        } else {
                            EmptyView()
                        }
                    }
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
                                        sourcePlaylistId: viewModel.likedPlaylist?.playlistId
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
            // Reload shelves immediately — full Supabase push/pull can take a long time
            // (many tracks) and would leave the system refresh spinner stuck.
            viewModel.reload(store: store)
            guard let store, auth.isAuthenticated else { return }
            let sync = LibrarySyncService(auth: auth)
            Task { @MainActor in
                await sync.syncBidirectional(store: store)
                viewModel.reload(store: store)
            }
        }
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
                        await auth.switchGoogleAccount()
                        appModel.syncAuth(auth)
                        // RootView adopts remote library + bumps libraryRevision for shelf reload.
                        viewModel.reload(store: store)
                    }
                } label: {
                    Text("Switch account")
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
                        viewModel.reload(store: store)
                    }
                } label: {
                    Text("Sign out")
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
                            Text("View all")
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

    private func playlistDisplayName(_ playlist: LibraryPlaylist) -> String {
        if playlist.systemType == SystemPlaylistType.favorites { return "Liked videos" }
        if playlist.systemType == SystemPlaylistType.watchLater { return "Watch later" }
        return playlist.name
    }

    private func playlistSubtitle(_ playlist: LibraryPlaylist) -> String {
        let count = playlist.entries.count
        return count == 1 ? "1 video" : "\(count) videos"
    }

    private func playlistCoverURL(_ playlist: LibraryPlaylist) -> URL? {
        if let url = PlaylistCoverStorage.resolveURL(playlist.coverUrlOrPath) {
            return url
        }
        return playlist.entries
            .sorted { $0.position < $1.position }
            .compactMap { entry in
                let item = entry.track.map(\.asVideoItem)
                return item.flatMap { store?.displayItem(for: $0).thumbnailURL ?? $0.thumbnailURL }
            }
            .first
    }
}

// MARK: - View model

@MainActor
final class YouViewModel: ObservableObject {
    @Published private(set) var channels: [UserSubscribedChannel] = []
    @Published private(set) var playlists: [LibraryPlaylist] = []
    @Published private(set) var liked: [VideoItem] = []
    @Published private(set) var likedPlaylist: LibraryPlaylist?
    @Published private(set) var hasLoadedOnce = false

    func reload(store: LibraryStore?) {
        // Synchronous local read — do not leave isLoading true across awaits.
        channels = store?.allSubscribedChannels()
            .sorted { $0.subscribedAt > $1.subscribedAt } ?? []
        // Custom playlists only — Liked / Watch later have their own shelves on Android.
        playlists = (store?.allPlaylists() ?? []).filter { $0.systemType == nil }
        likedPlaylist = store?.favoritesPlaylist()
        if let fav = likedPlaylist {
            liked = fav.entries
                .sorted { $0.position < $1.position }
                .compactMap { $0.track?.asVideoItem }
                .map { store?.displayItem(for: $0) ?? $0 }
        } else {
            liked = []
        }
        hasLoadedOnce = true
    }
}

// MARK: - Cards

private struct YouChannelCard: View {
    let channel: UserSubscribedChannel

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
    let channels: [UserSubscribedChannel]

    var body: some View {
        Group {
            if channels.isEmpty {
                ContentUnavailableView(
                    "No subscriptions",
                    systemImage: "person.2",
                    description: Text("Subscribe to a channel from the player")
                )
            } else {
                List(channels, id: \.channelId) { channel in
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
                                Text(channelListSubtitle(channel))
                                    .font(YTLiteType.meta)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .listRowBackground(YTLiteColor.background)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(YTLiteColor.background)
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func channelListSubtitle(_ channel: UserSubscribedChannel) -> String {
        if let subscriberCountText = channel.subscriberCountText, !subscriberCountText.isEmpty {
            return subscriberCountText
        }
        if let handle = channel.handle, !handle.isEmpty { return handle }
        return "Channel"
    }
}

struct YouPlaylistsListView: View {
    let playlists: [LibraryPlaylist]
    @Environment(\.libraryStore) private var store

    var body: some View {
        Group {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No playlists",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create a playlist from Library")
                )
            } else {
                List(playlists, id: \.playlistId) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist, onChange: {})
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: coverURL(playlist))
                                .frame(width: 64, height: 36)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(YTLiteType.rowTitle)
                                    .foregroundStyle(YTLiteColor.onSurface)
                                    .lineLimit(1)
                                Text("\(playlist.entries.count) videos")
                                    .font(YTLiteType.meta)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            }
                        }
                    }
                    .listRowBackground(YTLiteColor.background)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(YTLiteColor.background)
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func coverURL(_ playlist: LibraryPlaylist) -> URL? {
        if let url = PlaylistCoverStorage.resolveURL(playlist.coverUrlOrPath) { return url }
        return playlist.entries
            .sorted { $0.position < $1.position }
            .compactMap { $0.track?.asVideoItem.thumbnailURL }
            .first
    }
}

// MARK: - Guest graphic

private struct SubsEmptyGraphic: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.12))
                .frame(width: 88, height: 56)
                .rotationEffect(.degrees(-8))
                .offset(x: -18, y: -8)
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.18))
                .frame(width: 92, height: 58)
                .rotationEffect(.degrees(6))
                .offset(x: 16, y: -4)
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.28))
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
                }
                .listRowBackground(YTLiteColor.background)
            }
        }
        .scrollContentBackground(.hidden)
        .background(YTLiteColor.background)
        .navigationTitle("Channels")
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
                VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                    Text(playlist.title)
                        .font(YTLiteType.rowTitle)
                        .foregroundStyle(YTLiteColor.onSurface)
                    Text(playlist.subtitle)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
                .listRowBackground(YTLiteColor.background)
            }
        }
        .scrollContentBackground(.hidden)
        .background(YTLiteColor.background)
        .navigationTitle("Playlists")
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
                ContentUnavailableView("No videos", systemImage: "play.slash", description: Text(errorMessage ?? ""))
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
            NavigationStack { PlayerDetailView().preferredColorScheme(.dark) }
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
                ContentUnavailableView("Empty playlist", systemImage: "list.bullet", description: Text(errorMessage ?? ""))
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
            NavigationStack { PlayerDetailView().preferredColorScheme(.dark) }
        }
    }
}

private extension UserSubscribedChannel {
    var asChannelItem: ChannelItem {
        ChannelItem(
            channelId: channelId,
            title: title,
            subtitle: {
                if let subscriberCountText, !subscriberCountText.isEmpty { return subscriberCountText }
                if let handle, !handle.isEmpty { return handle }
                return "Channel"
            }(),
            thumbnailURL: avatarUrl.flatMap(URL.init(string:))
        )
    }
}
