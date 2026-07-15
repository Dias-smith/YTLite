import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { onQueryChanged() }
    }
    @Published var hits: [SearchHit] = []
    @Published var suggestions: [SearchSuggestionItem] = []
    @Published var selectedTab: SearchResultTab = .all
    @Published var isLoading = false
    @Published var isSuggestionsLoading = false
    @Published var errorMessage: String?
    @Published private(set) var phase: SearchPhase = .hub
    @Published private(set) var activeResultsQuery: String = ""

    private var searchTask: Task<Void, Never>?
    private var suggestTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private weak var memory: SearchMemoryStore?
    private var suppressQuerySideEffects = false

    func bind(memory: SearchMemoryStore) {
        self.memory = memory
    }

    func submit(memory: SearchMemoryStore, tab: SearchResultTab? = nil) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        debounceTask?.cancel()
        suggestTask?.cancel()
        searchTask?.cancel()

        suppressQuerySideEffects = true
        query = q
        suppressQuerySideEffects = false

        if let tab {
            selectedTab = tab
        }
        phase = .results
        activeResultsQuery = q
        suggestions = []
        loadResults(memory: memory, reset: true)
    }

    func selectTab(_ tab: SearchResultTab, memory: SearchMemoryStore) {
        guard phase == .results else { return }
        guard tab != selectedTab else { return }
        selectedTab = tab
        loadResults(memory: memory, reset: true)
    }

    func clearQuery() {
        debounceTask?.cancel()
        suggestTask?.cancel()
        searchTask?.cancel()
        suppressQuerySideEffects = true
        query = ""
        suppressQuerySideEffects = false
        hits = []
        suggestions = []
        errorMessage = nil
        phase = .hub
        activeResultsQuery = ""
        selectedTab = .all
        isLoading = false
        isSuggestionsLoading = false
    }

    func applySuggestion(_ item: SearchSuggestionItem, memory: SearchMemoryStore) {
        suppressQuerySideEffects = true
        query = item.text
        suppressQuerySideEffects = false
        submit(memory: memory)
    }

    func fillSuggestion(_ item: SearchSuggestionItem) {
        query = item.text
    }

    private func loadResults(memory: SearchMemoryStore, reset: Bool) {
        let q = activeResultsQuery
        let tab = selectedTab
        guard !q.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            isLoading = true
            errorMessage = nil
            if reset { hits = [] }
            defer { isLoading = false }
            do {
                let page = try await InnerTubeClient.search(query: q, tab: tab)
                guard !Task.isCancelled else { return }
                hits = page
                if tab == .all || tab == .videos {
                    memory.record(query: q, results: page.compactMap(\.asVideoItem))
                } else {
                    memory.record(query: q, results: [])
                }
                if page.isEmpty {
                    errorMessage = "No results for \"\(q)\""
                }
            } catch {
                errorMessage = error.localizedDescription
                hits = []
            }
        }
    }

    private func onQueryChanged() {
        guard !suppressQuerySideEffects else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        debounceTask?.cancel()

        if trimmed.isEmpty {
            suggestTask?.cancel()
            suggestions = []
            isSuggestionsLoading = false
            phase = .hub
            hits = []
            errorMessage = nil
            activeResultsQuery = ""
            return
        }

        if phase == .results || phase == .hub {
            phase = .suggestions
        }

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadSuggestions(for: trimmed)
        }
    }

    private func loadSuggestions(for query: String) async {
        suggestTask?.cancel()
        let history = memory?.recentQueries ?? []
        let request = query
        suggestTask = Task {
            isSuggestionsLoading = true
            defer { isSuggestionsLoading = false }
            let remote = await InnerTubeClient.fetchSuggestQueries(query: request)
            guard !Task.isCancelled else { return }
            let current = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == request else { return }
            suggestions = SearchSuggestionMerger.merge(
                query: request,
                history: history,
                remote: remote
            )
            if phase != .results {
                phase = .suggestions
            }
        }
        await suggestTask?.value
    }
}

enum SearchPhase: Equatable {
    case hub
    case suggestions
    case results
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
                    .padding(.bottom, 8)

                Group {
                    if viewModel.isLoading && viewModel.phase == .results && viewModel.hits.isEmpty {
                        ProgressView()
                            .tint(YTLiteColor.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        switch viewModel.phase {
                        case .hub:
                            discoveryContent
                        case .suggestions:
                            suggestionsList
                        case .results:
                            resultsPane
                        }
                    }
                }
            }
            .background(YTLiteColor.background)
            .navigationBarHidden(true)
            .onAppear { viewModel.bind(memory: memory) }
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
                    viewModel.clearQuery()
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

    private var resultsPane: some View {
        VStack(spacing: 0) {
            resultTabs
            if let err = viewModel.errorMessage, viewModel.hits.isEmpty, !viewModel.isLoading {
                Text(err)
                    .font(.subheadline)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsList
            }
        }
    }

    private var resultTabs: some View {
        HStack(spacing: 0) {
            ForEach(SearchResultTab.allCases) { tab in
                Button {
                    viewModel.selectTab(tab, memory: memory)
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(viewModel.selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(
                                viewModel.selectedTab == tab
                                    ? YTLiteColor.accent
                                    : YTLiteColor.onSurfaceVariant
                            )
                        Rectangle()
                            .fill(viewModel.selectedTab == tab ? YTLiteColor.accent : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.hits) { hit in
                    switch hit {
                    case .video(let item):
                        Button {
                            let videos = viewModel.hits.compactMap(\.asVideoItem)
                            let index = videos.firstIndex(of: item) ?? 0
                            playback.play(items: videos.isEmpty ? [item] : videos, startAt: index)
                            showPlayer = true
                        } label: {
                            SearchVideoResultRow(item: item)
                        }
                        .buttonStyle(.plain)
                    case .channel(let channel):
                        NavigationLink {
                            ChannelVideosView(channel: channel)
                        } label: {
                            SearchChannelResultRow(channel: channel)
                        }
                        .buttonStyle(.plain)
                    case .playlist(let playlist):
                        NavigationLink {
                            PlaylistVideosBrowserView(playlist: playlist)
                        } label: {
                            SearchPlaylistResultRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .overlay {
            if viewModel.isLoading && !viewModel.hits.isEmpty {
                ProgressView()
                    .tint(YTLiteColor.accent)
            }
        }
    }

    private var suggestionsList: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.suggestions) { item in
                        HStack(spacing: 12) {
                            Button {
                                viewModel.applySuggestion(item, memory: memory)
                                searchFocused = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.isFromHistory ? "clock.arrow.circlepath" : "magnifyingglass")
                                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                        .frame(width: 22)
                                    Text(item.text)
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                viewModel.fillSuggestion(item)
                                searchFocused = true
                            } label: {
                                Image(systemName: "arrow.up.left")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                        .padding(.vertical, 10)
                    }
                }
            }

            if viewModel.isSuggestionsLoading && viewModel.suggestions.isEmpty {
                ProgressView()
                    .tint(YTLiteColor.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            HStack(spacing: 12) {
                                Button {
                                    viewModel.query = q
                                    viewModel.submit(memory: memory)
                                    searchFocused = false
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                        Text(q)
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    viewModel.query = q
                                    searchFocused = true
                                } label: {
                                    Image(systemName: "arrow.up.left")
                                        .font(.footnote)
                                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                        .frame(width: 36, height: 36)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, YTLiteLayout.screenPadding)
                            .padding(.vertical, 10)
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
                        searchFocused = false
                    }
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                }
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Result rows (compact, Android SearchResultsScreen)

private struct SearchVideoResultRow: View {
    let item: VideoItem

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            AsyncImage(url: item.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    YTLiteColor.surfaceVariant
                }
            }
            .frame(width: 112, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            .padding(.leading, 8)

            Spacer(minLength: 4)

            Image(systemName: "arrow.down.to.line")
                .font(.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .frame(width: 28, height: 28)
            Image(systemName: "ellipsis")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, 8)
    }
}

private struct SearchChannelResultRow: View {
    let channel: ChannelItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: channel.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    YTLiteColor.surfaceVariant
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(channel.subtitle)
                    .font(.caption)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, 8)
    }
}

private struct SearchPlaylistResultRow: View {
    let playlist: PlaylistPreview

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: playlist.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    YTLiteColor.surfaceVariant
                }
            }
            .frame(width: 112, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(playlist.subtitle)
                    .font(.caption)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, 8)
    }
}

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
