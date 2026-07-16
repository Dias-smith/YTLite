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
    /// Data API mostPopular Music titles — Android `SearchUiState.hotKeywords`.
    @Published private(set) var hotKeywords: [String] = []

    private var searchTask: Task<Void, Never>?
    private var suggestTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var hotKeywordsTask: Task<Void, Never>?
    private weak var memory: SearchMemoryStore?
    private var suppressQuerySideEffects = false

    func bind(memory: SearchMemoryStore) {
        self.memory = memory
    }

    func loadHotKeywordsIfNeeded() {
        guard hotKeywords.isEmpty, hotKeywordsTask == nil else { return }
        hotKeywordsTask = Task {
            let keywords = await InnerTubeClient.fetchHotKeywords()
            guard !Task.isCancelled else { return }
            hotKeywords = keywords
            hotKeywordsTask = nil
        }
    }

    /// Submit search and go straight to results (never via suggestions).
    /// Prefer `query:` when tapping history / chips so assigning the text field
    /// does not briefly flip `phase` to `.suggestions`.
    func submit(memory: SearchMemoryStore, query overrideQuery: String? = nil, tab: SearchResultTab? = nil) {
        let q = (overrideQuery ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        debounceTask?.cancel()
        suggestTask?.cancel()
        searchTask?.cancel()

        // Lock results phase before mutating `query` so any residual side effects
        // cannot flash the suggestions pane.
        if let tab {
            selectedTab = tab
        }
        phase = .results
        activeResultsQuery = q
        suggestions = []
        isSuggestionsLoading = false

        suppressQuerySideEffects = true
        query = q
        suppressQuerySideEffects = false

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
        submit(memory: memory, query: item.text)
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

        if phase == .results {
            // Editing from the results search field should drop into suggestions;
            // hub / history / hot taps use `submit` and never reach here.
            phase = .suggestions
        } else if phase == .hub {
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
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var libraryStore
    @State private var showPlayer = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .padding(.top, YTLiteLayout.rowVertical)
                    .padding(.bottom, YTLiteLayout.rowVertical)

                Group {
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
            .background(YTLiteColor.background)
            .navigationBarHidden(true)
            .onAppear {
                viewModel.bind(memory: memory)
                viewModel.loadHotKeywordsIfNeeded()
            }
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
                .foregroundStyle(YTLiteColor.onSurface)
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
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.stackLoose)
        .background(YTLiteColor.surfaceElevated, in: Capsule())
    }

    private var resultsPane: some View {
        VStack(spacing: 0) {
            // Tabs stay mounted across tab switches; only the content below reloads.
            resultTabs
            if viewModel.isLoading && viewModel.hits.isEmpty {
                ProgressView()
                    .tint(YTLiteColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = viewModel.errorMessage, viewModel.hits.isEmpty {
                Text(err)
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsList
            }
        }
    }

    private var resultTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YTLiteLayout.stackDefault) {
                ForEach(SearchResultTab.allCases) { tab in
                    YTLiteChip(title: tab.rawValue, selected: viewModel.selectedTab == tab) {
                        viewModel.selectTab(tab, memory: memory)
                    }
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
        }
        .padding(.bottom, YTLiteLayout.stackTight)
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
                            SearchVideoResultRow(item: item) {
                                trackActions.present(item: item)
                            }
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
            .padding(.bottom, YTLiteLayout.screenPadding)
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
                        HStack(spacing: YTLiteLayout.stackLoose) {
                            Button {
                                viewModel.applySuggestion(item, memory: memory)
                                searchFocused = false
                            } label: {
                                HStack(spacing: YTLiteLayout.stackLoose) {
                                    Image(systemName: item.isFromHistory ? "clock.arrow.circlepath" : "magnifyingglass")
                                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                        .frame(width: 22)
                                    Text(item.text)
                                        .foregroundStyle(YTLiteColor.onSurface)
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
                                    .font(YTLiteType.rowTitleMedium)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                        .padding(.vertical, YTLiteLayout.rowVertical)
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
            VStack(alignment: .leading, spacing: YTLiteLayout.sectionGap) {
                if !memory.recentVideos.isEmpty {
                    VStack(alignment: .leading, spacing: YTLiteLayout.stackLoose) {
                        SectionHeaderRow(title: "Recent searches", actionTitle: "Clear all") {
                            memory.clearRecentVideos()
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: YTLiteLayout.stackLoose) {
                                ForEach(memory.recentVideos) { item in
                                    Button {
                                        playback.play(items: [item], startAt: 0)
                                        showPlayer = true
                                    } label: {
                                        VStack(alignment: .leading, spacing: YTLiteLayout.stackDefault) {
                                            VideoThumbnail(
                                                url: item.thumbnailURL,
                                                durationText: item.durationText,
                                                width: 120,
                                                height: 120,
                                                badgePadding: YTLiteLayout.stackTight
                                            )
                                            Text("\(item.title) - \(item.channelName)")
                                                .font(YTLiteType.meta)
                                                .foregroundStyle(YTLiteColor.onSurface)
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
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeaderRow(title: "Search history", actionTitle: "Clear all") {
                            memory.clearQueries()
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                        .padding(.bottom, YTLiteLayout.stackTight)

                        ForEach(memory.recentQueries, id: \.self) { q in
                            Button {
                                searchFocused = false
                                viewModel.submit(memory: memory, query: q)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 16))
                                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    Text(q)
                                        .font(YTLiteType.body)
                                        .foregroundStyle(YTLiteColor.onSurface)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, YTLiteLayout.screenPadding)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !viewModel.hotKeywords.isEmpty {
                    VStack(alignment: .leading, spacing: YTLiteLayout.stackLoose) {
                        Text("Trending searches")
                            .font(YTLiteType.sectionTitle)
                            .foregroundStyle(YTLiteColor.onSurface)
                            .padding(.horizontal, YTLiteLayout.screenPadding)

                        FlowChips(items: viewModel.hotKeywords) { tag in
                            searchFocused = false
                            viewModel.submit(memory: memory, query: tag)
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                    }
                }
            }
            .padding(.bottom, YTLiteLayout.sectionGap)
        }
    }
}

// MARK: - Result rows (compact, Android SearchResultsScreen)

private struct SearchVideoResultRow: View {
    let item: VideoItem
    var onMore: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: YTLiteLayout.stackTight) {
            VideoThumbnail(
                url: item.thumbnailURL,
                durationText: item.durationText,
                width: YTLiteLayout.searchThumbWidth,
                height: YTLiteLayout.searchThumbHeight,
                badgePadding: YTLiteLayout.stackTight
            )

            VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                Text(item.title)
                    .font(YTLiteType.rowTitleMedium)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            .padding(.leading, YTLiteLayout.stackDefault)

            Spacer(minLength: YTLiteLayout.stackTight)

            Button {
                onMore?()
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.rowVertical)
    }
}

private struct SearchChannelResultRow: View {
    let channel: ChannelItem

    var body: some View {
        HStack(spacing: YTLiteLayout.stackLoose) {
            RemoteImage(url: channel.thumbnailURL)
            .frame(width: YTLiteLayout.channelAvatar, height: YTLiteLayout.channelAvatar)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                Text(channel.title)
                    .font(YTLiteType.rowTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)
                Text(channel.subtitle)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.rowVertical)
    }
}

private struct SearchPlaylistResultRow: View {
    let playlist: PlaylistPreview

    var body: some View {
        HStack(spacing: YTLiteLayout.stackLoose) {
            RemoteImage(url: playlist.thumbnailURL)
            .frame(width: YTLiteLayout.searchThumbWidth, height: YTLiteLayout.searchThumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.thumbRadius))

            VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                Text(playlist.title)
                    .font(YTLiteType.rowTitleMedium)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(2)
                Text(playlist.subtitle)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.rowVertical)
    }
}

struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void

    var body: some View {
        ChipFlowLayout(spacing: YTLiteLayout.stackDefault) {
            ForEach(items, id: \.self) { title in
                Button {
                    onTap(title)
                } label: {
                    Text(title)
                        .font(YTLiteType.label)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, YTLiteLayout.chipHorizontal)
                        .padding(.vertical, YTLiteLayout.chipVertical)
                        .background(YTLiteColor.surfaceChip, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Horizontal wrapping chip row sized to each label (Android `FlowRow`).
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widthUsed: CGFloat = 0

        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let chipWidth = maxWidth.isFinite ? min(ideal.width, maxWidth) : ideal.width
            let size = chipWidth < ideal.width
                ? subview.sizeThatFits(ProposedViewSize(width: chipWidth, height: nil))
                : ideal
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            widthUsed = max(widthUsed, x - spacing)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widthUsed, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let chipWidth = min(ideal.width, bounds.width)
            let size = chipWidth < ideal.width
                ? subview.sizeThatFits(ProposedViewSize(width: chipWidth, height: nil))
                : ideal
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
