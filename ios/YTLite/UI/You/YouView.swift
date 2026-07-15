import SwiftUI

struct YouView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.libraryStore) private var store
    @StateObject private var viewModel = YouViewModel()
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isAuthenticated {
                    subsSignInEmpty
                } else if viewModel.isLoading && viewModel.trending.isEmpty {
                    ProgressView()
                        .tint(YTLiteColor.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    signedInContent
                }
            }
            .background(YTLiteColor.background)
            .navigationBarHidden(true)
            .task {
                guard auth.isAuthenticated else { return }
                await viewModel.load(apiKey: appModel.config.youtubeDataAPIKey, store: store)
            }
            .sheet(isPresented: $showPlayer) {
                NavigationStack {
                    PlayerDetailView()
                        .preferredColorScheme(.dark)
                }
            }
        }
    }

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
                    await viewModel.load(apiKey: appModel.config.youtubeDataAPIKey, store: store)
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

    private var signedInContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Subscriptions")
                    .font(YTLiteType.pageTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .padding(.top, YTLiteLayout.rowVertical)

                if let err = viewModel.errorMessage {
                    Text(err)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.danger)
                        .padding(.horizontal)
                }

                if !viewModel.liked.isEmpty {
                    Text("Liked")
                        .font(YTLiteType.sectionTitle)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: YTLiteLayout.stackLoose) {
                            ForEach(viewModel.liked) { item in
                                ShelfCard(
                                    title: item.title,
                                    subtitle: item.channelName,
                                    imageURL: item.thumbnailURL,
                                    durationText: item.durationText
                                ) {
                                    playback.play(items: viewModel.liked, startAt: viewModel.liked.firstIndex(of: item) ?? 0)
                                    showPlayer = true
                                }
                            }
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                    }
                }

                Text("Trending music")
                    .font(YTLiteType.sectionTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .padding(.horizontal, YTLiteLayout.screenPadding)

                LazyVStack(spacing: YTLiteLayout.stackTight) {
                    ForEach(Array(viewModel.trending.enumerated()), id: \.element.id) { index, item in
                        Button {
                            playback.play(items: viewModel.trending, startAt: index)
                            showPlayer = true
                        } label: {
                            FeedVideoCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 0) {
                    NavigationLink {
                        ChannelSearchView()
                    } label: {
                        discoverRow(title: "Search channels", icon: "person.2")
                    }
                    NavigationLink {
                        PlaylistSearchView()
                    } label: {
                        discoverRow(title: "Search playlists", icon: "list.bullet.rectangle")
                    }
                }
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.bottom, YTLiteLayout.sectionGap)
            }
        }
        .refreshable {
            await viewModel.load(apiKey: appModel.config.youtubeDataAPIKey, store: store)
        }
    }

    private func discoverRow(title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(YTLiteColor.accent)
            Text(title)
                .font(YTLiteType.rowTitleMedium)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .padding(.vertical, YTLiteLayout.stackLoose)
    }
}

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

@MainActor
final class YouViewModel: ObservableObject {
    @Published var liked: [VideoItem] = []
    @Published var trending: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(apiKey: String, store: LibraryStore?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        if let fav = store?.favoritesPlaylist() {
            liked = fav.entries
                .sorted { $0.position < $1.position }
                .compactMap { $0.track?.asVideoItem }
        }
        do {
            trending = try await InnerTubeClient.fetchTrendingMusic(apiKey: apiKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ShelfCard: View {
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
                    width: 140,
                    height: 80,
                    badgePadding: YTLiteLayout.stackTight
                )
                Text(title)
                    .font(YTLiteType.meta.weight(.semibold))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(2)
                    .frame(width: 140, alignment: .leading)
                Text(subtitle)
                    .font(YTLiteType.iconCaption)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

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
                    AsyncImage(url: channel.thumbnailURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: YTLiteColor.surfaceVariant
                        }
                    }
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
                    LazyVStack(spacing: YTLiteLayout.stackTight) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, item in
                            Button {
                                playback.play(items: videos, startAt: index)
                                showPlayer = true
                            } label: {
                                FeedVideoCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .background(YTLiteColor.background)
        .navigationTitle(channel.title)
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                videos = try await InnerTubeClient.fetchChannelUploads(channelId: channel.channelId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showPlayer) {
            NavigationStack { PlayerDetailView().preferredColorScheme(.dark) }
        }
    }
}

struct PlaylistVideosBrowserView: View {
    let playlist: PlaylistPreview
    @EnvironmentObject private var playback: PlaybackController
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
                    LazyVStack(spacing: YTLiteLayout.stackTight) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, item in
                            Button {
                                playback.play(items: videos, startAt: index)
                                showPlayer = true
                            } label: {
                                FeedVideoCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .background(YTLiteColor.background)
        .navigationTitle(playlist.title)
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                videos = try await InnerTubeClient.fetchPlaylistVideos(playlistId: playlist.playlistId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showPlayer) {
            NavigationStack { PlayerDetailView().preferredColorScheme(.dark) }
        }
    }
}
