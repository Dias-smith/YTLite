import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasSearched = false

    private var searchTask: Task<Void, Never>?

    func submit(memory: SearchMemoryStore) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            isLoading = true
            errorMessage = nil
            hasSearched = true
            defer { isLoading = false }
            do {
                results = try await InnerTubeClient.searchVideos(query: q)
                memory.record(query: q, results: results)
                if results.isEmpty {
                    errorMessage = "No videos found"
                }
            } catch {
                errorMessage = error.localizedDescription
                results = []
            }
        }
    }

    func clearResults() {
        results = []
        hasSearched = false
        errorMessage = nil
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @StateObject private var memory = SearchMemoryStore()
    @EnvironmentObject private var playback: PlaybackController
    @State private var showPlayer = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if viewModel.isLoading {
                    ProgressView()
                        .tint(YTLiteColor.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.hasSearched {
                    resultsList
                } else {
                    discoveryContent
                }
            }
            .background(YTLiteColor.background)
            .navigationBarHidden(true)
            .sheet(isPresented: $showPlayer) {
                NavigationStack {
                    PlayerDetailView()
                        .preferredColorScheme(.dark)
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            TextField("Search videos, channels...", text: $viewModel.query)
                .foregroundStyle(.white)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { viewModel.submit(memory: memory) }
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.clearResults()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(YTLiteColor.surfaceElevated, in: Capsule())
    }

    private var discoveryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !memory.recentVideos.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderRow(title: "Recent searches", actionTitle: "Clear all") {
                            memory.clearRecentVideos()
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(memory.recentVideos) { item in
                                    Button {
                                        playback.play(items: [item], startAt: 0)
                                        showPlayer = true
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            AsyncImage(url: item.thumbnailURL) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image.resizable().scaledToFill()
                                                default:
                                                    YTLiteColor.surfaceVariant
                                                }
                                            }
                                            .frame(width: 120, height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            Text("\(item.title) - \(item.channelName)")
                                                .font(.caption)
                                                .foregroundStyle(.white)
                                                .lineLimit(2)
                                                .frame(width: 120, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, YTLiteLayout.screenPadding)
                        }
                    }
                }

                if !memory.recentQueries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderRow(title: "Search history", actionTitle: "Clear all") {
                            memory.clearQueries()
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)

                        ForEach(memory.recentQueries, id: \.self) { q in
                            Button {
                                viewModel.query = q
                                viewModel.submit(memory: memory)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    Text(q)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.footnote)
                                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                }
                                .padding(.horizontal, YTLiteLayout.screenPadding)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Trending searches")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, YTLiteLayout.screenPadding)

                    FlowChips(items: SearchMemoryStore.trendingDefaults) { tag in
                        viewModel.query = tag
                        viewModel.submit(memory: memory)
                    }
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if let err = viewModel.errorMessage, viewModel.results.isEmpty {
                    Text(err)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .padding()
                }
                ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, item in
                    Button {
                        playback.play(items: viewModel.results, startAt: index)
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

/// Simple wrapping chip row.
struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { title in
                Button {
                    onTap(title)
                } label: {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(YTLiteColor.surfaceChip, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
