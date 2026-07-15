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
                    ContentUnavailableView {
                        VStack(spacing: 12) {
                            Image("BrandLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            Label("You", systemImage: "person.crop.circle")
                        }
                    } description: {
                        Text("Sign in to see Liked and discover music channels.")
                    } actions: {
                        Button(auth.isBusy ? "Signing in…" : "Sign in with Google") {
                            Task {
                                await auth.signInWithGoogle()
                                appModel.syncAuth(auth)
                                await viewModel.load(apiKey: appModel.config.youtubeDataAPIKey, store: store)
                            }
                        }
                        .disabled(auth.isBusy || !auth.isConfigured)
                    }
                } else if viewModel.isLoading && viewModel.trending.isEmpty {
                    ProgressView("Loading…")
                } else {
                    List {
                        if let err = viewModel.errorMessage {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }

                        Section("Liked") {
                            if viewModel.liked.isEmpty {
                                Text("No liked videos yet").foregroundStyle(.secondary)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(viewModel.liked) { item in
                                            ShelfCard(title: item.title, subtitle: item.channelName, imageURL: item.thumbnailURL) {
                                                playback.play(items: viewModel.liked, startAt: viewModel.liked.firstIndex(of: item) ?? 0)
                                                showPlayer = true
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowInsets(EdgeInsets())
                            }
                        }

                        Section("Trending music") {
                            ForEach(Array(viewModel.trending.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    playback.play(items: viewModel.trending, startAt: index)
                                    showPlayer = true
                                } label: {
                                    VideoRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Section("Find channels") {
                            NavigationLink("Search channels") {
                                ChannelSearchView()
                            }
                            NavigationLink("Search playlists") {
                                PlaylistSearchView()
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.load(apiKey: appModel.config.youtubeDataAPIKey, store: store)
                    }
                }
            }
            .navigationTitle("You")
            .task {
                guard auth.isAuthenticated else { return }
                await viewModel.load(apiKey: appModel.config.youtubeDataAPIKey, store: store)
            }
            .sheet(isPresented: $showPlayer) {
                NavigationStack { PlayerDetailView() }
            }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Color.secondary.opacity(0.2)
                    }
                }
                .frame(width: 140, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title).font(.caption.weight(.semibold)).lineLimit(2).frame(width: 140, alignment: .leading)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 140, alignment: .leading)
            }
            .padding(.horizontal, 8)
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
                HStack(spacing: 12) {
                    AsyncImage(url: channel.thumbnailURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Color.secondary.opacity(0.2)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    VStack(alignment: .leading) {
                        Text(channel.title).font(.subheadline.weight(.semibold))
                        Text(channel.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Channels")
        .searchable(text: $query, prompt: "Search channels")
        .onSubmit(of: .search) { Task { await search() } }
        .overlay { if isLoading { ProgressView() } }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.title).font(.subheadline.weight(.semibold))
                    Text(playlist.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Playlists")
        .searchable(text: $query, prompt: "Search playlists")
        .onSubmit(of: .search) { Task { await search() } }
        .overlay { if isLoading { ProgressView() } }
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
                ProgressView()
            } else if videos.isEmpty {
                ContentUnavailableView("No videos", systemImage: "play.slash", description: Text(errorMessage ?? ""))
            } else {
                List {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, item in
                        Button {
                            playback.play(items: videos, startAt: index)
                            showPlayer = true
                        } label: {
                            VideoRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
            NavigationStack { PlayerDetailView() }
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
                ProgressView()
            } else if videos.isEmpty {
                ContentUnavailableView("Empty playlist", systemImage: "list.bullet", description: Text(errorMessage ?? ""))
            } else {
                List {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, item in
                        Button {
                            playback.play(items: videos, startAt: index)
                            showPlayer = true
                        } label: {
                            VideoRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
            NavigationStack { PlayerDetailView() }
        }
    }
}
