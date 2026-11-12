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
    @Published private(set) var isLoadingMore = false
    @Published var isSuggestionsLoading = false
    @Published var errorMessage: String?
    @Published private(set) var phase: SearchPhase = .hub
    @Published private(set) var activeResultsQuery: String = ""
    /// Same duration / views buckets as Home (`HomeFeedFilter`).
    @Published private(set) var resultsFilter: HomeFeedFilter
    /// Data API mostPopular Music titles — Android `SearchUiState.hotKeywords`.
    @Published private(set) var hotKeywords: [String] = []

    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var suggestTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var hotKeywordsTask: Task<Void, Never>?
    private weak var memory: SearchMemoryStore?
    private var suppressQuerySideEffects = false
    /// One in-app interstitial per submitted query (not per tab reload).
    private var interstitialArmedQuery: String?
    /// Next-page token for the active results query / tab.
    private var resultsContinuation: String?

    init() {
        resultsFilter = SearchResultsFilterStore.load()
    }

    /// Hits after applying the local duration / views filter (channels & playlists always pass).
    var filteredHits: [SearchHit] {
        guard resultsFilter.isActive else { return hits }
        return hits.filter { hit in
            switch hit {
            case .video(let video):
                return resultsFilter.matches(video)
            case .channel, .playlist:
                return true
            }
        }
    }

    func bind(memory: SearchMemoryStore) {
        self.memory = memory
    }

    func applyResultsFilter(_ filter: HomeFeedFilter) {
        resultsFilter = filter
        SearchResultsFilterStore.save(filter)
    }

    func loadHotKeywordsIfNeeded() {
        guard hotKeywords.isEmpty, hotKeywordsTask == nil else { return }
        reloadHotKeywords()
    }

    /// Force-refresh hot keywords after Content Region / language change.
    func handleContentLocaleChange() {
        hotKeywordsTask?.cancel()
        hotKeywordsTask = nil
        hotKeywords = []
        searchTask?.cancel()
        suggestTask?.cancel()
        debounceTask?.cancel()
        hits = []
        suggestions = []
        errorMessage = nil
        interstitialArmedQuery = nil
        resultsContinuation = nil
        isLoadingMore = false

        let activeQuery = activeResultsQuery
        if phase == .results, !activeQuery.isEmpty, let memory {
            loadResults(memory: memory, reset: true)
        } else if phase != .hub {
            // Drop stale results/suggestions; hub will show new hot keywords.
            phase = .hub
            activeResultsQuery = ""
            selectedTab = .all
            isLoading = false
            isSuggestionsLoading = false
        }
        reloadHotKeywords()
    }

    private func reloadHotKeywords() {
        hotKeywordsTask?.cancel()
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
        AppAnalytics.searchSubmit(query: q)

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
        isLoadingMore = false
        isSuggestionsLoading = false
        interstitialArmedQuery = nil
        resultsContinuation = nil
    }

    /// Append the next results page when the user nears the list end.
    func loadMoreIfNeeded() {
        guard phase == .results,
              memory != nil,
              let continuation = resultsContinuation,
              !continuation.isEmpty,
              !isLoading,
              !isLoadingMore,
              !activeResultsQuery.isEmpty
        else { return }
        guard let memory else { return }
        loadResults(memory: memory, reset: false)
    }

    func applySuggestion(_ item: SearchSuggestionItem, memory: SearchMemoryStore) {
        submit(memory: memory, query: item.text)
    }

    /// Fill the search field without submitting (Android history ↖ / suggestion fill).
    func fillQuery(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        query = trimmed
    }

    private func loadResults(memory: SearchMemoryStore, reset: Bool) {
        let q = activeResultsQuery
        let tab = selectedTab
        guard !q.isEmpty else { return }
        let continuation = reset ? nil : resultsContinuation
        if !reset {
            guard let continuation, !continuation.isEmpty else { return }
        }
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        searchTask = Task {
            if reset {
                isLoading = true
                isLoadingMore = false
                errorMessage = nil
                hits = []
                resultsContinuation = nil
            } else {
                isLoadingMore = true
            }
            defer {
                if generation == searchGeneration {
                    isLoading = false
                    isLoadingMore = false
                }
            }
            do {
                let page = try await InnerTubeClient.search(
                    query: q,
                    tab: tab,
                    continuation: continuation
                )
                guard !Task.isCancelled, generation == searchGeneration else { return }
                if reset {
                    hits = page.hits
                } else {
                    var seen = Set(hits.map(\.id))
                    for hit in page.hits where seen.insert(hit.id).inserted {
                        hits.append(hit)
                    }
                }
                resultsContinuation = page.continuation
                if tab == .all || tab == .videos {
                    memory.record(query: q, results: hits.compactMap(\.asVideoItem))
                } else if reset {
                    memory.record(query: q, results: [])
                }
                if reset, page.hits.isEmpty {
                    errorMessage = "No results for \"\(q)\""
                }
                if reset {
                    presentSearchResultsAdIfNeeded(query: q)
                }
            } catch {
                guard generation == searchGeneration else { return }
                if reset {
                    errorMessage = error.localizedDescription
                    hits = []
                    resultsContinuation = nil
                    presentSearchResultsAdIfNeeded(query: q)
                }
                // Keep existing hits when a "load more" request fails.
            }
        }
    }

    private func presentSearchResultsAdIfNeeded(query: String) {
        guard interstitialArmedQuery != query else { return }
        interstitialArmedQuery = query
        AdSceneLifecycle.onSearchResultsPresented(query: query)
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
            // Stay on results when the field is merely re-synced to the submitted query
            // (common after dismissing the keyboard). Only leave when the user edits it.
            if trimmed == activeResultsQuery {
                return
            }
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
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.libraryStore) private var libraryStore
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FocusState private var searchFocused: Bool
    @State private var showResultsFilter = false

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
            .coordinateSpace(name: BubbleGuideStore.coordinateSpaceName)
            .bubbleGuideLayer(.searchFilter, text: L("guide.search_filter"))
            .ytLiteContentWidth(enabled: YTLiteAdaptive.isRegularWidth(horizontalSizeClass))
            .ytLiteAppBackground()
            .navigationBarHidden(true)
            .onAppear {
                viewModel.bind(memory: memory)
                viewModel.loadHotKeywordsIfNeeded()
            }
            .onChange(of: appModel.contentLocaleRevision) { _, _ in
                viewModel.handleContentLocaleChange()
            }
            .sheet(isPresented: $showResultsFilter) {
                HomeFeedFilterSheet(
                    filter: viewModel.resultsFilter,
                    onApply: { next in
                        viewModel.applyResultsFilter(next)
                        showResultsFilter = false
                    },
                    onCancel: {
                        showResultsFilter = false
                    }
                )
            }
            .debugAction("search.run_yudie") {
                viewModel.submit(memory: memory, query: "雨蝶", tab: .videos)
            }
            .debugAction("search.play_first") {
                let videos = viewModel.filteredHits.compactMap(\.asVideoItem)
                guard let first = videos.first else { return }
                playback.play(items: videos, startAt: 0, analyticsSource: "search")
                playerPresentation.isPresented = true
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
        .background(YTLiteColor.searchField, in: Capsule())
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
            } else if viewModel.filteredHits.isEmpty {
                VStack(spacing: YTLiteLayout.stackLoose) {
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .tint(YTLiteColor.accent)
                    }
                    Text(
                        viewModel.resultsFilter.isActive
                            ? L("home.filter.empty")
                            : (viewModel.errorMessage ?? L("search.no_results"))
                    )
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    // Keep paging while the active filter hides the current page.
                    viewModel.loadMoreIfNeeded()
                }
                .onChange(of: viewModel.hits.count) { _, _ in
                    viewModel.loadMoreIfNeeded()
                }
            } else {
                resultsList
            }
        }
    }

    private var resultTabs: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: YTLiteLayout.stackDefault) {
                    ForEach(SearchResultTab.allCases) { tab in
                        YTLiteChip(title: tab.title, selected: viewModel.selectedTab == tab) {
                            viewModel.selectTab(tab, memory: memory)
                        }
                    }
                }
                .padding(.leading, YTLiteLayout.screenPadding)
                .padding(.trailing, YTLiteLayout.stackTight)
            }

            Button {
                BubbleGuideStore.shared.dismiss(.searchFilter)
                showResultsFilter = true
            } label: {
                Image(systemName: viewModel.resultsFilter.isActive
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        viewModel.resultsFilter.isActive
                            ? YTLiteColor.accent
                            : YTLiteColor.onSurface
                    )
                    .frame(width: 32, height: 32)
                    .background(YTLiteColor.surfaceChip, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("home.filter.title"))
            .bubbleGuideTarget(.searchFilter)
            .padding(.leading, YTLiteLayout.stackLoose)
            .padding(.trailing, YTLiteLayout.screenPadding)
        }
        .padding(.bottom, YTLiteLayout.stackTight)
    }

    private var resultsList: some View {
        GeometryReader { geo in
            let columns = YTLiteAdaptive.searchColumns(
                for: geo.size.width,
                sizeClass: horizontalSizeClass,
                preferEvenColumns: YTLiteAdaptive.prefersEvenColumns(
                    in: geo,
                    sizeClass: horizontalSizeClass
                )
            )
            let displayHits = viewModel.filteredHits
            SearchResultsPane(
                token: searchHitsToken,
                hits: displayHits,
                columns: columns,
                isLoadingOverlay: viewModel.isLoading && !viewModel.hits.isEmpty,
                isLoadingMore: viewModel.isLoadingMore,
                onPlayVideo: { item in
                    let videos = displayHits.compactMap(\.asVideoItem)
                    let index = videos.firstIndex(where: { $0.videoId == item.videoId }) ?? 0
                    AppAnalytics.searchResultTap(type: "video")
                    playback.play(
                        items: videos.isEmpty ? [item] : videos,
                        startAt: index,
                        analyticsSource: "search"
                    )
                    playerPresentation.present()
                },
                onMore: { trackActions.present(item: $0) },
                onNearEnd: { viewModel.loadMoreIfNeeded() }
            )
            .equatable()
        }
    }

    private var searchHitsToken: Int {
        let display = viewModel.filteredHits
        var hasher = Hasher()
        hasher.combine(display.count)
        hasher.combine(display.first?.id)
        hasher.combine(display.last?.id)
        hasher.combine(viewModel.hits.count)
        hasher.combine(viewModel.selectedTab)
        hasher.combine(viewModel.isLoading)
        hasher.combine(viewModel.isLoadingMore)
        hasher.combine(viewModel.resultsFilter.durations.map(\.rawValue).sorted())
        hasher.combine(viewModel.resultsFilter.viewCounts.map(\.rawValue).sorted())
        return hasher.finalize()
    }

    private var suggestionsList: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.suggestions) { item in
                        Button {
                            searchFocused = false
                            viewModel.applySuggestion(item, memory: memory)
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
                            .padding(.horizontal, YTLiteLayout.screenPadding)
                            .padding(.vertical, YTLiteLayout.rowVertical)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)

            if viewModel.isSuggestionsLoading && viewModel.suggestions.isEmpty {
                ProgressView()
                    .tint(YTLiteColor.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ytLiteMiniPlayerScrollInset()
    }

    private var discoveryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !memory.recentVideos.isEmpty {
                    VStack(alignment: .leading, spacing: YTLiteLayout.stackLoose) {
                        SectionHeaderRow(title: L("search.recent"), actionTitle: L("search.clear_all")) {
                            memory.clearRecentVideos()
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: YTLiteLayout.stackLoose) {
                                ForEach(memory.recentVideos) { item in
                                    Button {
                                        AppAnalytics.searchResultTap(type: "video")
                                        playback.play(items: [item], startAt: 0, analyticsSource: "search")
                                        playerPresentation.present()
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
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }

                if !memory.recentQueries.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeaderRow(title: L("search.history"), actionTitle: L("search.clear_all")) {
                            memory.clearQueries()
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                        .padding(.top, memory.recentVideos.isEmpty ? 4 : 8)
                        .padding(.bottom, 4)

                        ForEach(memory.recentQueries, id: \.self) { q in
                            SearchHistoryRow(
                                query: q,
                                onSearch: {
                                    searchFocused = false
                                    viewModel.submit(memory: memory, query: q)
                                },
                                onFill: {
                                    viewModel.fillQuery(q)
                                    searchFocused = true
                                }
                            )
                        }
                    }
                }

                if !viewModel.hotKeywords.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("search.trending"))
                            .font(YTLiteType.labelEmphasized)
                            .foregroundStyle(YTLiteColor.onSurface)
                            .padding(.horizontal, YTLiteLayout.screenPadding)

                        FlowChips(items: viewModel.hotKeywords, spacing: 14) { tag in
                            searchFocused = false
                            viewModel.submit(memory: memory, query: tag)
                        }
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                    }
                    .padding(.top, (memory.recentQueries.isEmpty && memory.recentVideos.isEmpty) ? 4 : 10)
                }
            }
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.immediately)
        .ytLiteMiniPlayerScrollInset()
    }
}

// MARK: - Result rows (compact, Android SearchResultsScreen)

/// Android `HistoryQueryRow` — tap row to search; ↖ fills the field.
private struct SearchHistoryRow: View {
    let query: String
    var onSearch: () -> Void
    var onFill: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSearch) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(width: 18, alignment: .center)
                    Text(query)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onFill) {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("search.fill"))
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, 5)
    }
}

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
        .contentShape(Rectangle())
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
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.rowVertical)
        .contentShape(Rectangle())
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.rowVertical)
        .contentShape(Rectangle())
    }
}

struct FlowChips: View {
    let items: [String]
    var spacing: CGFloat = 14
    var onTap: (String) -> Void

    var body: some View {
        ChipFlowLayout(spacing: spacing) {
            ForEach(items, id: \.self) { title in
                Button {
                    onTap(title)
                } label: {
                    Text(title)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
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

/// Search hits grid/list — skips body when only playback publishes.
private struct SearchResultsPane: View, Equatable {
    let token: Int
    let hits: [SearchHit]
    let columns: Int
    let isLoadingOverlay: Bool
    let isLoadingMore: Bool
    let onPlayVideo: (VideoItem) -> Void
    let onMore: (VideoItem) -> Void
    let onNearEnd: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.token == rhs.token
            && lhs.columns == rhs.columns
            && lhs.isLoadingOverlay == rhs.isLoadingOverlay
            && lhs.isLoadingMore == rhs.isLoadingMore
    }

    var body: some View {
        Group {
            if columns <= 1 {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            hitRow(hit, fullWidth: true)
                                .onAppear {
                                    if index >= max(0, hits.count - 4) {
                                        onNearEnd()
                                    }
                                }
                        }
                        if isLoadingMore {
                            ProgressView()
                                .tint(YTLiteColor.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: YTLiteAdaptive.gridItems(count: columns, spacing: 12),
                        spacing: 12
                    ) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            hitRow(hit, fullWidth: false)
                                .onAppear {
                                    if index >= max(0, hits.count - 4) {
                                        onNearEnd()
                                    }
                                }
                        }
                        if isLoadingMore {
                            ProgressView()
                                .tint(YTLiteColor.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .gridCellColumns(columns)
                        }
                    }
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .padding(.bottom, YTLiteLayout.screenPadding)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .ytLiteMiniPlayerScrollInset()
        .overlay {
            if isLoadingOverlay {
                ProgressView()
                    .tint(YTLiteColor.accent)
            }
        }
    }

    @ViewBuilder
    private func hitRow(_ hit: SearchHit, fullWidth: Bool) -> some View {
        switch hit {
        case .video(let item):
            Button {
                onPlayVideo(item)
            } label: {
                SearchVideoResultRow(item: item) {
                    onMore(item)
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
            .simultaneousGesture(TapGesture().onEnded {
                AppAnalytics.searchResultTap(type: "channel")
            })
            .modifier(SearchGridSpan(columns: columns, enabled: !fullWidth))
        case .playlist(let playlist):
            NavigationLink {
                PlaylistVideosBrowserView(playlist: playlist)
            } label: {
                SearchPlaylistResultRow(playlist: playlist)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                AppAnalytics.searchResultTap(type: "playlist")
            })
            .modifier(SearchGridSpan(columns: columns, enabled: !fullWidth))
        }
    }
}

private struct SearchGridSpan: ViewModifier {
    let columns: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.gridCellColumns(columns)
        } else {
            content
        }
    }
}
