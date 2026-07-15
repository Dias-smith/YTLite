import SwiftUI

struct HomeCategory: Identifiable, Hashable {
    let id: String
    let title: String
    /// `nil` uses InnerTube home browse; otherwise video search.
    let searchQuery: String?

    static let all: [HomeCategory] = [
        HomeCategory(id: "all", title: "All", searchQuery: nil),
        HomeCategory(id: "music", title: "Music", searchQuery: "music"),
        HomeCategory(id: "podcasts", title: "Podcasts", searchQuery: "podcasts"),
        HomeCategory(id: "live", title: "Live", searchQuery: "live music"),
        HomeCategory(id: "gaming", title: "Gaming", searchQuery: "gaming"),
        HomeCategory(id: "news", title: "News", searchQuery: "news"),
        HomeCategory(id: "sports", title: "Sports", searchQuery: "sports"),
        HomeCategory(id: "learning", title: "Learning", searchQuery: "learning"),
    ]
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var selectedCategoryId: String = HomeCategory.all[0].id

    private var loadGeneration = 0
    private var rawVideos: [VideoItem] = []
    weak var libraryStore: LibraryStore?

    init() {
        applyStoredFeed(for: selectedCategoryId)
    }

    var selectedCategory: HomeCategory {
        HomeCategory.all.first { $0.id == selectedCategoryId } ?? HomeCategory.all[0]
    }

    /// Switch chip: show local feed; auto-refresh only when this category has no local data.
    func selectCategory(_ category: HomeCategory) {
        guard category.id != selectedCategoryId else { return }
        selectedCategoryId = category.id
        errorMessage = nil
        applyStoredFeed(for: category.id)
        refreshIfEmpty()
    }

    /// First open / home enter: show local feed; auto-refresh only when empty.
    func appear() {
        applyStoredFeed(for: selectedCategoryId)
        refreshIfEmpty()
    }

    func refilter() {
        videos = applyLibraryFilter(rawVideos)
    }

    private func refreshIfEmpty() {
        guard videos.isEmpty else { return }
        Task { await refresh() }
    }

    /// Pull-to-refresh / explicit network reload for the current category.
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
            let fetched: [VideoItem]
            if let query = category.searchQuery {
                fetched = try await InnerTubeClient.searchVideos(query: query)
            } else {
                fetched = try await InnerTubeClient.fetchHomeFeed()
            }
            guard generation == loadGeneration, requestId == selectedCategoryId else { return }
            rawVideos = fetched
            videos = applyLibraryFilter(fetched)
            if fetched.isEmpty {
                errorMessage = "No videos in feed"
            } else {
                errorMessage = nil
                HomeFeedStore.save(categoryId: requestId, videos: fetched)
            }
        } catch {
            guard generation == loadGeneration, requestId == selectedCategoryId else { return }
            errorMessage = error.localizedDescription
            if videos.isEmpty {
                applyStoredFeed(for: requestId)
            }
        }
    }

    private func applyStoredFeed(for categoryId: String) {
        if let stored = HomeFeedStore.loadVideos(categoryId: categoryId) {
            rawVideos = stored
        } else {
            rawVideos = []
        }
        videos = applyLibraryFilter(rawVideos)
    }

    private func applyLibraryFilter(_ items: [VideoItem]) -> [VideoItem] {
        guard let libraryStore else { return items }
        return libraryStore.filterNotInterested(items)
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
            .navigationBarHidden(true)
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
        if viewModel.isRefreshing && viewModel.videos.isEmpty {
            ProgressView()
                .tint(YTLiteColor.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.videos.isEmpty {
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
                    ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, item in
                        Button {
                            playback.play(items: viewModel.videos, startAt: index)
                            showPlayer = true
                        } label: {
                            FeedVideoCard(item: item) {
                                trackActions.present(item: item)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, YTLiteLayout.rowVertical)
            }
            .refreshable { await viewModel.refresh() }
        }
    }
}
