import SwiftUI

/// Temporary probe for home pull-to-refresh (filter Console: `YTLite.HomeFeed`).
enum HomeFeedProbe {
    static let tag = "YTLite.HomeFeed"

    static func log(_ stage: String, _ detail: String = "") {
        let detailPart = detail.isEmpty ? "" : " | \(detail)"
        print("[\(tag)] [\(stage)]\(detailPart)")
    }
}

enum HomeCategorySource: Hashable {
    case homeBrowse
    case musicNewReleaseAlbums
    case search(String)
    case innerTube(HomeChipEndpoint)
    case live
    case youtubeNews
}

struct HomeCategory: Identifiable, Hashable {
    let id: String
    let source: HomeCategorySource
    var customTitle: String? = nil

    var title: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        switch id {
        case "all": return L("home.category.all")
        case "music": return L("home.category.music")
        case "new_release": return L("home.category.new_release")
        case "podcasts": return L("home.category.podcasts")
        case "news": return L("home.category.news")
        case "live": return L("home.category.live")
        case "mixes": return L("home.category.mixes")
        case "albums": return L("home.category.albums")
        case "rnb": return L("home.category.rnb")
        case "mandopop": return L("home.category.mandopop")
        case "electropop": return L("home.category.electropop")
        case "energize": return L("home.category.energize")
        case "feel_good": return L("home.category.feel_good")
        case "workout": return L("home.category.workout")
        case "chill": return L("home.category.chill")
        case "party": return L("home.category.party")
        case "romance": return L("home.category.romance")
        case "commute": return L("home.category.commute")
        case "focus": return L("home.category.focus")
        case "sad": return L("home.category.sad")
        case "sleep": return L("home.category.sleep")
        default: return id
        }
    }

    static let catalog: [HomeCategory] = [
        HomeCategory(id: "all", source: .homeBrowse),
        HomeCategory(id: "music", source: .search("music")),
        HomeCategory(id: "new_release", source: .musicNewReleaseAlbums),
        HomeCategory(id: "podcasts", source: .search("podcasts")),
        HomeCategory(id: "news", source: .youtubeNews),
        HomeCategory(id: "live", source: .live),
        HomeCategory(id: "mixes", source: .search("music mixes")),
        HomeCategory(id: "albums", source: .search("music albums")),
        HomeCategory(id: "rnb", source: .search("contemporary r&b")),
        HomeCategory(id: "mandopop", source: .search("mandopop")),
        HomeCategory(id: "electropop", source: .search("electropop")),
        HomeCategory(id: "energize", source: .search("energize music")),
        HomeCategory(id: "feel_good", source: .search("feel good music")),
        HomeCategory(id: "workout", source: .search("workout music")),
        HomeCategory(id: "chill", source: .search("chill music")),
        HomeCategory(id: "party", source: .search("party music")),
        HomeCategory(id: "romance", source: .search("romance music")),
        HomeCategory(id: "commute", source: .search("commute music")),
        HomeCategory(id: "focus", source: .search("focus music")),
        HomeCategory(id: "sad", source: .search("sad music")),
        HomeCategory(id: "sleep", source: .search("sleep music")),
    ]

    static func merged(with dynamic: [HomeDynamicChip]) -> [HomeCategory] {
        var result = [catalog[0]]
        var seen = Set(["all"])

        for chip in dynamic {
            let key = categoryAlias(normalizedTitle(chip.title))
            guard !key.isEmpty, key != "all", seen.insert(key).inserted else { continue }
            let matchingStatic = catalog.dropFirst().first {
                categoryAlias($0.id.replacingOccurrences(of: "_", with: "")) == key
            }
            result.append(
                HomeCategory(
                    id: matchingStatic?.id ?? chip.id,
                    source: key == "live"
                        ? .live
                        : (key == "news" ? .youtubeNews : .innerTube(chip.endpoint)),
                    customTitle: chip.title
                )
            )
        }
        for category in catalog.dropFirst() {
            let key = categoryAlias(category.id.replacingOccurrences(of: "_", with: ""))
            guard seen.insert(key).inserted else { continue }
            result.append(category)
        }
        return result
    }

    static func applyingSavedOrder(to categories: [HomeCategory]) -> [HomeCategory] {
        guard let all = categories.first(where: { $0.id == "all" }) else { return categories }
        let rest = categories.filter { $0.id != "all" }
        let positions = Dictionary(
            uniqueKeysWithValues: HomeFeedStore.loadCategoryOrder().enumerated().map { ($0.element, $0.offset) }
        )
        let original = Dictionary(uniqueKeysWithValues: rest.enumerated().map { ($0.element.id, $0.offset) })
        let ordered = rest.sorted {
            let lhs = positions[$0.id] ?? (positions.count + (original[$0.id] ?? 0))
            let rhs = positions[$1.id] ?? (positions.count + (original[$1.id] ?? 0))
            return lhs < rhs
        }
        return [all] + ordered
    }

    private static func normalizedTitle(_ title: String) -> String {
        var value = title.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value != "music", value.hasSuffix(" music") {
            value.removeLast(" music".count)
        }
        value = value
            .replacingOccurrences(of: "[^a-z0-9\\p{Han}]", with: "", options: .regularExpression)
        if value == "romantic" { value = "romance" }
        if value == "contemporaryrb" { value = "rb" }
        return value
    }

    private static func categoryAlias(_ value: String) -> String {
        switch value {
        case "newreleases", "recentlyuploaded", "latest": return "newrelease"
        case "livenow": return "live"
        case "mixesforyou", "yourmixes": return "mixes"
        case "contemporaryrb", "rnb": return "rb"
        case "romantic": return "romance"
        default: return value
        }
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var entries: [HomeFeedEntry] = []
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var selectedCategoryId: String = "all"
    @Published private(set) var orderedCategories: [HomeCategory]
    /// Bumped after a successful pull-to-refresh so the list can scroll to top.
    @Published private(set) var scrollToTopToken = 0
    /// Playable tracks for queue play — updated with `entries`, not recomputed per row.
    @Published private(set) var playableVideos: [VideoItem] = []

    private var loadGeneration = 0
    private var rawEntries: [HomeFeedEntry] = []
    private var playableIndexById: [String: Int] = [:]
    private var dynamicChips: [HomeDynamicChip]
    private var didRequestDynamicChips = false
    private var continuation: String?
    /// Re-entrancy guard — not @Published. Publishing `isRefreshing` during pull-to-refresh
    /// rebuilds the ScrollView and cancels SwiftUI's `.refreshable` task mid-request.
    private var isRefreshInFlight = false
    weak var libraryStore: LibraryStore?

    init() {
        dynamicChips = HomeFeedStore.loadDynamicChips()
        orderedCategories = HomeCategory.applyingSavedOrder(
            to: HomeCategory.merged(with: dynamicChips)
        )
        if let saved = HomeFeedStore.loadSelectedCategoryId(),
           orderedCategories.contains(where: { $0.id == saved }) {
            selectedCategoryId = saved
        }
        applyStoredFeed(for: selectedCategoryId)
    }

    var selectedCategory: HomeCategory {
        orderedCategories.first { $0.id == selectedCategoryId }
            ?? orderedCategories.first
            ?? HomeCategory.catalog[0]
    }

    /// Playable tracks currently listed (album cards excluded).
    var videos: [VideoItem] { playableVideos }

    func playIndex(for item: VideoItem) -> Int {
        playableIndexById[item.videoId] ?? 0
    }

    func selectCategory(_ category: HomeCategory) {
        guard category.id != selectedCategoryId else { return }
        selectedCategoryId = category.id
        HomeFeedStore.saveSelectedCategoryId(category.id)
        errorMessage = nil
        // Align Android: show disk/memory cache immediately; network only if empty.
        applyStoredFeed(for: category.id)
        refreshIfNeeded()
    }

    func appear() {
        applyStoredFeed(for: selectedCategoryId)
        refreshIfNeeded()
        refreshDynamicChipsIfNeeded()
    }

    func applyCategoryOrder(_ categories: [HomeCategory]) {
        let all = orderedCategories.first(where: { $0.id == "all" }) ?? HomeCategory.catalog[0]
        orderedCategories = [all] + categories.filter { $0.id != "all" }
        HomeFeedStore.saveCategoryOrder(orderedCategories.map(\.id))
    }

    func refilter() {
        entries = applyLibraryFilter(rawEntries)
        rebuildPlayableIndex(from: entries)
    }

    private func rebuildPlayableIndex(from items: [HomeFeedEntry]) {
        let videos = items.compactMap(\.asVideoItem)
        playableVideos = videos
        var map: [String: Int] = [:]
        map.reserveCapacity(videos.count)
        for (i, v) in videos.enumerated() {
            map[v.videoId] = i
        }
        playableIndexById = map
    }

    /// Network only when this category has no cached content (Android `preferCache = true`).
    private func refreshIfNeeded() {
        guard entries.isEmpty else { return }
        Task { await refresh(force: false) }
    }

    private func refreshDynamicChipsIfNeeded() {
        guard !didRequestDynamicChips else { return }
        didRequestDynamicChips = true
        if selectedCategoryId == "all", entries.isEmpty { return }
        Task {
            guard let page = try? await InnerTubeClient.fetchHomeFeedPage() else { return }
            acceptDynamicChips(page.chips)
        }
    }

    private func acceptDynamicChips(_ chips: [HomeDynamicChip]) {
        guard !chips.isEmpty else { return }
        dynamicChips = chips
        HomeFeedStore.saveDynamicChips(chips)
        orderedCategories = HomeCategory.applyingSavedOrder(
            to: HomeCategory.merged(with: chips)
        )
        if !orderedCategories.contains(where: { $0.id == selectedCategoryId }) {
            selectedCategoryId = "all"
            HomeFeedStore.saveSelectedCategoryId("all")
            applyStoredFeed(for: "all")
        }
    }

    /// Pull-to-refresh entry. Detach from SwiftUI cancellation so gesture/view
    /// teardown cannot abort the in-flight InnerTube request.
    func refresh() async {
        HomeFeedProbe.log("refresh.public", "category=\(selectedCategoryId)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                await self.refresh(force: true)
                continuation.resume()
            }
        }
    }

    private func refresh(force: Bool) async {
        if isRefreshInFlight {
            HomeFeedProbe.log(
                "refresh.skip",
                "reason=already_refreshing force=\(force) category=\(selectedCategoryId)"
            )
            return
        }
        let category = selectedCategory
        let requestId = category.id
        // Non-force with existing UI content is a no-op (cache already shown).
        if !force, !entries.isEmpty {
            HomeFeedProbe.log(
                "refresh.skip",
                "reason=cache_hit force=false count=\(entries.count) category=\(requestId)"
            )
            return
        }

        let previousIds = entries.map(\.id)
        let hadContinuation = !(continuation ?? "").isEmpty
        loadGeneration += 1
        let generation = loadGeneration

        HomeFeedProbe.log(
            "refresh.start",
            "force=\(force) gen=\(generation) category=\(requestId) source=\(String(describing: category.source)) prevCount=\(previousIds.count) hasCont=\(hadContinuation) contPrefix=\(continuationPrefix(continuation))"
        )

        isRefreshInFlight = true
        // Only publish loading for empty-state ProgressView. Publishing during pull-to-refresh
        // with existing rows cancels the `.refreshable` task (see refresh.cancelled logs).
        let publishLoading = entries.isEmpty
        if publishLoading {
            isRefreshing = true
        }
        // Avoid no-op @Published writes — they still rebuild the view and cancel refreshable.
        if errorMessage != nil {
            errorMessage = nil
        }
        defer {
            isRefreshInFlight = false
            if generation == loadGeneration {
                if publishLoading {
                    isRefreshing = false
                }
                HomeFeedProbe.log("refresh.end", "gen=\(generation) category=\(requestId)")
            }
        }

        do {
            let page = try await fetchPage(for: category, preferContinuation: force)
            guard generation == loadGeneration, requestId == selectedCategoryId else {
                HomeFeedProbe.log(
                    "refresh.stale",
                    "gen=\(generation)/\(loadGeneration) req=\(requestId) selected=\(selectedCategoryId)"
                )
                return
            }
            let newIds = page.entries.map(\.id)
            let overlap = Set(previousIds).intersection(newIds).count
            let sameOrder = previousIds == newIds
            HomeFeedProbe.log(
                "refresh.result",
                "count=\(page.entries.count) overlap=\(overlap)/\(previousIds.count) sameOrder=\(sameOrder) newCont=\(!(page.continuation ?? "").isEmpty) contPrefix=\(continuationPrefix(page.continuation)) first=\(newIds.prefix(3).joined(separator: ","))"
            )
            rawEntries = page.entries
            entries = applyLibraryFilter(page.entries)
            rebuildPlayableIndex(from: entries)
            continuation = page.continuation
            if let chips = page.chips {
                acceptDynamicChips(chips)
            }
            if page.entries.isEmpty {
                errorMessage = "No videos in feed"
                HomeFeedProbe.log("refresh.empty", "category=\(requestId)")
            } else {
                errorMessage = nil
                HomeFeedStore.save(
                    categoryId: requestId,
                    entries: page.entries,
                    continuation: page.continuation
                )
                if force {
                    scrollToTopToken += 1
                    HomeFeedProbe.log("refresh.scrollTop", "token=\(scrollToTopToken)")
                }
            }
        } catch is CancellationError {
            HomeFeedProbe.log("refresh.cancelled", "gen=\(generation) category=\(requestId)")
            return
        } catch {
            guard generation == loadGeneration, requestId == selectedCategoryId else { return }
            if Task.isCancelled {
                HomeFeedProbe.log("refresh.taskCancelled", "gen=\(generation)")
                return
            }
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
                HomeFeedProbe.log("refresh.urlCancelled", "gen=\(generation)")
                return
            }
            HomeFeedProbe.log(
                "refresh.error",
                "category=\(requestId) err=\(error.localizedDescription)"
            )
            errorMessage = error.localizedDescription
            if entries.isEmpty {
                applyStoredFeed(for: requestId)
            }
        }
    }

    private func continuationPrefix(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "nil" }
        return String(token.prefix(16))
    }

    private struct FeedPage {
        let entries: [HomeFeedEntry]
        let continuation: String?
        var chips: [HomeDynamicChip]? = nil
    }

    private func fetchPage(
        for category: HomeCategory,
        preferContinuation: Bool
    ) async throws -> FeedPage {
        let token = preferContinuation ? continuation : nil
        if let token, !token.isEmpty {
            HomeFeedProbe.log(
                "fetch.tryCont",
                "category=\(category.id) contPrefix=\(continuationPrefix(token))"
            )
            if let page = try? await fetchPage(for: category, continuation: token),
               !page.entries.isEmpty
            {
                HomeFeedProbe.log(
                    "fetch.cont.ok",
                    "category=\(category.id) count=\(page.entries.count) nextCont=\(!(page.continuation ?? "").isEmpty)"
                )
                return page
            }
            HomeFeedProbe.log(
                "fetch.cont.fallback",
                "category=\(category.id) reason=empty_or_error → cold"
            )
        } else {
            HomeFeedProbe.log(
                "fetch.cold",
                "category=\(category.id) preferCont=\(preferContinuation)"
            )
        }
        return try await fetchPage(for: category, continuation: nil)
    }

    private func fetchPage(
        for category: HomeCategory,
        continuation token: String?
    ) async throws -> FeedPage {
        switch category.source {
        case .homeBrowse:
            let page = try await InnerTubeClient.fetchHomeFeedPage(continuation: token)
            return FeedPage(
                entries: page.videos.map { .track($0) },
                continuation: page.continuation,
                chips: token == nil ? page.chips : nil
            )
        case .search(let query):
            let page = try await InnerTubeClient.searchVideosPage(
                query: query,
                continuation: token
            )
            return FeedPage(
                entries: page.videos.map { .track($0) },
                continuation: page.continuation
            )
        case .musicNewReleaseAlbums:
            let page = try await InnerTubeClient.fetchMusicNewReleaseFeed(
                continuation: token
            )
            return FeedPage(entries: page.entries, continuation: page.continuation)
        case .innerTube(let endpoint):
            let page = try await InnerTubeClient.fetchHomeFeedPage(
                endpoint: endpoint,
                continuation: token
            )
            return FeedPage(
                entries: page.videos.map { .track($0) },
                continuation: page.continuation
            )
        case .live:
            let page = try await InnerTubeClient.fetchLiveVideosPage(continuation: token)
            return FeedPage(
                entries: page.videos.map { .track($0) },
                continuation: page.continuation
            )
        case .youtubeNews:
            let page = try await InnerTubeClient.fetchNewsVideosPage(continuation: token)
            return FeedPage(
                entries: page.videos.map { .track($0) },
                continuation: page.continuation
            )
        }
    }

    private func applyStoredFeed(for categoryId: String) {
        if let stored = HomeFeedStore.loadFeed(categoryId: categoryId) {
            rawEntries = stored.entries
            continuation = stored.continuation
            HomeFeedProbe.log(
                "cache.load",
                "category=\(categoryId) count=\(stored.entries.count) hasCont=\(!(stored.continuation ?? "").isEmpty)"
            )
        } else {
            rawEntries = []
            continuation = nil
            HomeFeedProbe.log("cache.miss", "category=\(categoryId)")
        }
        entries = applyLibraryFilter(rawEntries)
        rebuildPlayableIndex(from: entries)
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
    @State private var showCategoryReorder = false
    @State private var reorderCategories: [HomeCategory] = []

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
                }
            }
            .sheet(isPresented: $showCategoryReorder) {
                categoryReorderSheet
            }
        }
    }

    private var categoryChips: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: YTLiteLayout.stackDefault) {
                        ForEach(viewModel.orderedCategories) { cat in
                            YTLiteChip(
                                title: cat.title,
                                selected: viewModel.selectedCategoryId == cat.id
                            ) {
                                viewModel.selectCategory(cat)
                            }
                            .id(cat.id)
                        }
                    }
                    .padding(.leading, YTLiteLayout.screenPadding)
                    .padding(.trailing, YTLiteLayout.stackDefault)
                    .padding(.vertical, YTLiteLayout.stackLoose)
                }

                Button {
                    reorderCategories = viewModel.orderedCategories
                    showCategoryReorder = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(width: 42, height: 42)
                        .background(YTLiteColor.surfaceElevated, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("home.category.reorder"))
                .padding(.trailing, YTLiteLayout.screenPadding)
            }
            .onAppear {
                proxy.scrollTo(viewModel.selectedCategoryId, anchor: .center)
            }
            .onChange(of: viewModel.selectedCategoryId) { _, id in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var categoryReorderSheet: some View {
        NavigationStack {
            List {
                ForEach(reorderCategories) { category in
                    HStack(spacing: YTLiteLayout.stackDefault) {
                        Image(systemName: category.id == "all" ? "pin.fill" : "line.3.horizontal")
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .frame(width: 24)
                        Text(category.title)
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.onSurface)
                    }
                    .listRowBackground(YTLiteColor.surface)
                    .moveDisabled(category.id == "all")
                }
                .onMove { source, destination in
                    let movable = IndexSet(source.filter { $0 != 0 })
                    guard !movable.isEmpty else { return }
                    reorderCategories.move(
                        fromOffsets: movable,
                        toOffset: max(1, destination)
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(YTLiteColor.surface)
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L("home.category.reorder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) {
                        viewModel.applyCategoryOrder(reorderCategories)
                        showCategoryReorder = false
                    }
                    .font(YTLiteType.labelEmphasized)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) {
                        showCategoryReorder = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                    L("home.empty_title"),
                    systemImage: "house",
                    description: Text(viewModel.errorMessage ?? L("home.pull_to_refresh"))
                )
                .foregroundStyle(YTLiteColor.onSurface)
                .frame(maxWidth: .infinity, minHeight: 420)
            }
            .refreshable {
                HomeFeedProbe.log("ui.refreshable", "path=empty category=\(viewModel.selectedCategoryId)")
                await viewModel.refresh()
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id("home_feed_top")
                        if let err = viewModel.errorMessage {
                            Text(err)
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.danger)
                                .padding(.horizontal, YTLiteLayout.screenPadding)
                        }
                        ForEach(viewModel.entries) { entry in
                            switch entry {
                            case .track(let item):
                                FeedVideoCard(
                                    item: item,
                                    onTap: {
                                        let queue = viewModel.playableVideos
                                        let index = viewModel.playIndex(for: item)
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
                .refreshable {
                    HomeFeedProbe.log(
                        "ui.refreshable",
                        "path=list category=\(viewModel.selectedCategoryId) count=\(viewModel.entries.count)"
                    )
                    await viewModel.refresh()
                }
                .onChange(of: viewModel.scrollToTopToken) { _, token in
                    HomeFeedProbe.log("ui.scrollTop", "token=\(token)")
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("home_feed_top", anchor: .top)
                    }
                }
            }
        }
    }
}

private struct HomeAlbumCard: View {
    let album: MusicAlbumRelease

    var body: some View {
        HStack(alignment: .center, spacing: YTLiteLayout.feedAvatarTextGap) {
            RemoteImage(url: album.thumbnailURL, maxPointSize: 88)
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
                    L("common.no_tracks"),
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
                PlayerDetailView()
            }
        }
    }
}
