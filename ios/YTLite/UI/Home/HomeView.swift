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
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedCategoryId: String = HomeCategory.all[0].id

    private var loadGeneration = 0

    var selectedCategory: HomeCategory {
        HomeCategory.all.first { $0.id == selectedCategoryId } ?? HomeCategory.all[0]
    }

    func selectCategory(_ category: HomeCategory) {
        guard category.id != selectedCategoryId else { return }
        selectedCategoryId = category.id
        load(force: true)
    }

    func load(force: Bool = false) {
        if isLoading && !force { return }
        let category = selectedCategory
        let requestId = category.id
        loadGeneration += 1
        let generation = loadGeneration

        isLoading = true
        errorMessage = nil
        if force {
            videos = []
        }

        Task {
            defer {
                if generation == loadGeneration {
                    isLoading = false
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
                videos = fetched
                if fetched.isEmpty {
                    errorMessage = "No videos in feed"
                }
            } catch {
                guard generation == loadGeneration, requestId == selectedCategoryId else { return }
                errorMessage = error.localizedDescription
                if videos.isEmpty {
                    videos = []
                }
            }
        }
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var playback: PlaybackController
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
                if viewModel.videos.isEmpty {
                    viewModel.load(force: true)
                }
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
            HStack(spacing: 8) {
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
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.videos.isEmpty {
            ProgressView()
                .tint(YTLiteColor.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.videos.isEmpty {
            ContentUnavailableView(
                "Home",
                systemImage: "house",
                description: Text(viewModel.errorMessage ?? "Pull to refresh")
            )
            .foregroundStyle(.white)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(YTLiteColor.accent)
                            .padding(.vertical, 8)
                    }
                    if let err = viewModel.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                    ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, item in
                        Button {
                            playback.play(items: viewModel.videos, startAt: index)
                            showPlayer = true
                        } label: {
                            FeedVideoCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
            .refreshable { viewModel.load(force: true) }
        }
    }
}
