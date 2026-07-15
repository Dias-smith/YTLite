import SwiftUI

enum HomeCategorySource: Hashable {
    case homeBrowse
    case musicNewReleaseAlbums
    case search(String)
}

struct HomeCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let source: HomeCategorySource

    /// Mirrors Android `HomeCategories.items`.
    static let all: [HomeCategory] = [
        HomeCategory(id: "all", title: "All", source: .homeBrowse),
        HomeCategory(id: "new_release", title: "New release", source: .musicNewReleaseAlbums),
        HomeCategory(id: "podcasts", title: "Podcasts", source: .search("podcasts")),
        HomeCategory(id: "energize", title: "Energize", source: .search("energize music")),
        HomeCategory(id: "feel_good", title: "Feel good", source: .search("feel good music")),
        HomeCategory(id: "workout", title: "Workout", source: .search("workout music")),
        HomeCategory(id: "chill", title: "Chill", source: .search("chill music")),
        HomeCategory(id: "party", title: "Party", source: .search("party music")),
        HomeCategory(id: "romance", title: "Romance", source: .search("romance music")),
        HomeCategory(id: "commute", title: "Commute", source: .search("commute music")),
        HomeCategory(id: "focus", title: "Focus", source: .search("focus music")),
        HomeCategory(id: "sad", title: "Sad", source: .search("sad music")),
        HomeCategory(id: "sleep", title: "Sleep", source: .search("sleep music")),
    ]
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var entries: [HomeFeedEntry] = []
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var selectedCategoryId: String = HomeCategory.all[0].id

    private var loadGeneration = 0
    private var rawEntries: [HomeFeedEntry] = []
    weak var libraryStore: LibraryStore?

    init() {
        applyStoredFeed(for: selectedCategoryId)
    }

    var selectedCategory: HomeCategory {
        HomeCategory.all.first { $0.id == selectedCategoryId } ?? HomeCategory.all[0]
    }

    /// Playable tracks currently listed (album cards excluded).
    var videos: [VideoItem] {
        rawEntries.compactMap(\.asVideoItem)
    }

    func selectCategory(_ category: HomeCategory) {
        guard category.id != selectedCategoryId else { return }
        selectedCategoryId = category.id
        errorMessage = nil
        applyStoredFeed(for: category.id)
        refreshIfNeeded()
    }

    func appear() {
        applyStoredFeed(for: selectedCategoryId)
        refreshIfNeeded()
    }

    func refilter() {
        entries = applyLibraryFilter(rawEntries)
    }

    private func refreshIfNeeded() {
        guard needsNetworkRefresh(entries, source: selectedCategory.source) else { return }
        Task { await refresh() }
    }

    private func needsNetworkRefresh(_ items: [HomeFeedEntry], source: HomeCategorySource) -> Bool {
        if items.isEmpty { return true }
        if case .musicNewReleaseAlbums = source { return false }
        let tracks = items.compactMap(\.asVideoItem)
        guard !tracks.isEmpty else { return true }
        let missingAvatar = tracks.filter { $0.channelAvatarURL == nil }.count
        let missingViews = tracks.filter { ($0.viewCountText ?? "").isEmpty }.count
        return missingAvatar * 2 >= tracks.count || missingViews * 2 >= tracks.count
    }

    func refresh() async {
        if isRefreshing { return }
        let category = selectedCategory
        let requestId = category.id
        loadGeneration += 1
        let generation = loadGeneration

        isRefreshing = true
        errorMessage = nil
        defer {
            if generation == loadGeneration {
                isRefreshing = false
            }
        }

        do {
            let fetched = try await fetchEntries(for: category)
            guard generation == loadGeneration, requestId == selectedCategoryId else { return }
            rawEntries = fetched
            entries = applyLibraryFilter(fetched)
            if fetched.isEmpty {
                errorMessage = "No videos in feed"
            } else {
                errorMessage = nil
                let trackVideos = fetched.compactMap(\.asVideoItem)
                if !trackVideos.isEmpty, category.source != .musicNewReleaseAlbums {
                    HomeFeedStore.save(categoryId: requestId, videos: trackVideos)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, requestId == selectedCategoryId else { return }
            if Task.isCancelled { return }
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
            errorMessage = error.localizedDescription
            if entries.isEmpty {
                applyStoredFeed(for: requestId)
            }
        }
    }

    private func fetchEntries(for category: HomeCategory) async throws -> [HomeFeedEntry] {
        switch category.source {
        case .homeBrowse:
            return try await InnerTubeClient.fetchHomeFeed().map { .track($0) }
        case .search(let query):
            return try await InnerTubeClient.searchVideos(query: query).map { .track($0) }
        case .musicNewReleaseAlbums:
            return try await InnerTubeClient.fetchMusicNewReleaseFeed()
        }
    }

    private func applyStoredFeed(for categoryId: String) {
        if let stored = HomeFeedStore.loadVideos(categoryId: categoryId) {
            rawEntries = stored.map { .track($0) }
        } else {
            rawEntries = []
        }
        entries = applyLibraryFilter(rawEntries)
    }

    private func applyLibraryFilter(_ items: [HomeFeedEntry]) -> [HomeFeedEntry] {
        guard let libraryStore else { return items }
        return items.compactMap { entry in
            switch entry {
            case .album:
                return entry
            case .track(let video):
                let kept = libraryStore.filterNotInterested([video])
                return kept.isEmpty ? nil : .track(video)
            }
        }
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var libraryStore
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryChips
                content
            }
            .background(YTLiteColor.background)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                viewModel.libraryStore = libraryStore
                viewModel.appear()
            }
            .onChange(of: libraryStore != nil) { _, _ in
                viewModel.libraryStore = libraryStore
                viewModel.refilter()
            }
            .onChange(of: trackActions.listEpoch) { _, _ in
                viewModel.refilter()
            }
            .sheet(isPresented: $showPlayer) {
                NavigationStack {
                    PlayerDetailView()
                        .preferredColorScheme(.dark)
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YTLiteLayout.stackDefault) {
                ForEach(HomeCategory.all) { cat in
                    YTLiteChip(
                        title: cat.title,
                        selected: viewModel.selectedCategoryId == cat.id
                    ) {
                        viewModel.selectCategory(cat)
                    }
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.vertical, YTLiteLayout.stackLoose)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isRefreshing && viewModel.entries.isEmpty {
            ProgressView()
                .tint(YTLiteColor.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.entries.isEmpty {
            ScrollView {
                ContentUnavailableView(
                    "Home",
                    systemImage: "house",
                    description: Text(viewModel.errorMessage ?? "Pull to refresh")
                )
                .foregroundStyle(YTLiteColor.onSurface)
                .frame(maxWidth: .infinity, minHeight: 420)
            }
            .refreshable { await viewModel.refresh() }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let err = viewModel.errorMessage {
                        Text(err)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.danger)
                            .padding(.horizontal, YTLiteLayout.screenPadding)
                    }
                    ForEach(viewModel.entries) { entry in
                        switch entry {
                        case .track(let item):
                            let queue = viewModel.videos
                            let index = queue.firstIndex(of: item) ?? 0
                            FeedVideoCard(
                                item: item,
                                onTap: {
                                    playback.play(items: queue.isEmpty ? [item] : queue, startAt: index)
                                    showPlayer = true
                                },
                                onMore: {
                                    trackActions.present(item: item)
                                }
                            )
                        case .album(let album):
                            NavigationLink {
                                AlbumTracksView(album: album)
                            } label: {
                                HomeAlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, YTLiteLayout.rowVertical)
            }
            .refreshable { await viewModel.refresh() }
        }
    }
}

private struct HomeAlbumCard: View {
    let album: MusicAlbumRelease

    var body: some View {
        HStack(alignment: .center, spacing: YTLiteLayout.feedAvatarTextGap) {
            RemoteImage(url: album.thumbnailURL)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.thumbRadius, style: .continuous))

            VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                Text(album.title)
                    .font(YTLiteType.feedTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(2)
                Text(album.artistName)
                    .font(YTLiteType.feedMeta)
                    .foregroundStyle(YTLiteColor.feedMeta)
                    .lineLimit(1)
                if !album.releaseType.isEmpty {
                    Text(album.releaseType)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .padding(.horizontal, YTLiteLayout.feedInfoHorizontal)
        .padding(.vertical, YTLiteLayout.feedInfoTop)
        .contentShape(Rectangle())
    }
}

struct AlbumTracksView: View {
    let album: MusicAlbumRelease
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var libraryStore
    @State private var tracks: [VideoItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPlayer = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(YTLiteColor.accent)
            } else if tracks.isEmpty {
                ContentUnavailableView(
                    "No tracks",
                    systemImage: "music.note.list",
                    description: Text(errorMessage ?? "")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, item in
                            FeedVideoCard(
                                item: item,
                                onTap: {
                                    playback.play(items: tracks, startAt: index)
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
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                let fetched = try await InnerTubeClient.fetchMusicAlbumTracks(
                    browseId: album.browseId,
                    albumTitle: album.title,
                    artistFallback: album.artistName,
                    thumbnailFallback: album.thumbnailURL
                )
                tracks = libraryStore?.filterNotInterested(fetched) ?? fetched
                if tracks.isEmpty {
                    errorMessage = "No tracks in album"
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                let ns = error as NSError
                if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showPlayer) {
            NavigationStack {
                PlayerDetailView().preferredColorScheme(.dark)
            }
        }
    }
}
