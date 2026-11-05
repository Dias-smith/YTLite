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
    case catalogNews
}

/// Region-aware search queries for static Home chips (Content Region `gl`).
enum HomeLocalizedQuery {
    static func resolve(_ chipId: String, region gl: String) -> String {
        let code = gl.uppercased()
        let sinosphere: Set<String> = ["CN", "TW", "HK", "SG", "MY"]
        let japanese: Set<String> = ["JP"]
        let korean: Set<String> = ["KR"]

        if sinosphere.contains(code) {
            switch chipId {
            case "music": return "华语流行"
            case "podcasts": return "播客"
            case "charts": return "音乐排行榜"
            case "mixes": return "华语歌单"
            case "albums": return "华语专辑"
            case "rnb": return "R&B 中文"
            case "mandopop": return "华语流行"
            case "electropop": return "电子流行"
            case "energize": return "动感音乐"
            case "feel_good": return "轻松音乐"
            case "workout": return "健身音乐"
            case "chill": return "轻音乐"
            case "party": return "派对音乐"
            case "romance": return "情歌"
            case "commute": return "通勤音乐"
            case "focus": return "专注音乐"
            case "sad": return "伤感歌曲"
            case "sleep": return "助眠音乐"
            default: break
            }
        } else if japanese.contains(code) {
            switch chipId {
            case "music": return "J-POP"
            case "podcasts": return "ポッドキャスト"
            case "charts": return "音楽チャート"
            case "mixes": return "プレイリスト"
            case "albums": return "アルバム"
            case "mandopop": return "C-POP"
            case "energize": return "元気が出る曲"
            case "feel_good": return "気分が上がる曲"
            case "workout": return "ワークアウトミュージック"
            case "chill": return "チルミュージック"
            case "party": return "パーティーミュージック"
            case "romance": return "ラブソング"
            case "commute": return "通勤 BGM"
            case "focus": return "集中ミュージック"
            case "sad": return "悲しい曲"
            case "sleep": return "睡眠ミュージック"
            default: break
            }
        } else if korean.contains(code) {
            switch chipId {
            case "music": return "K-POP"
            case "podcasts": return "팟캐스트"
            case "charts": return "음악 차트"
            case "mixes": return "플레이리스트"
            case "albums": return "앨범"
            case "mandopop": return "C-POP"
            case "energize": return "신나는 음악"
            case "feel_good": return "기분 좋은 음악"
            case "workout": return "운동 음악"
            case "chill": return "힐링 음악"
            case "party": return "파티 음악"
            case "romance": return "사랑 노래"
            case "commute": return "출퇴근 음악"
            case "focus": return "집중 음악"
            case "sad": return "슬픈 노래"
            case "sleep": return "수면 음악"
            default: break
            }
        }

        switch chipId {
        case "music": return "music"
        case "podcasts": return "podcasts"
        case "charts": return "top songs chart"
        case "mixes": return "music mixes"
        case "albums": return "music albums"
        case "rnb": return "contemporary r&b"
        case "mandopop": return "mandopop"
        case "electropop": return "electropop"
        case "energize": return "energize music"
        case "feel_good": return "feel good music"
        case "workout": return "workout music"
        case "chill": return "chill music"
        case "party": return "party music"
        case "romance": return "romance music"
        case "commute": return "commute music"
        case "focus": return "focus music"
        case "sad": return "sad music"
        case "sleep": return "sleep music"
        default: return chipId
        }
    }
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
        case "charts": return L("home.category.charts")
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

    static var catalog: [HomeCategory] {
        let gl = CatalogConstants.gl
        return [
            HomeCategory(id: "all", source: .homeBrowse),
            HomeCategory(id: "music", source: .search(HomeLocalizedQuery.resolve("music", region: gl))),
            HomeCategory(id: "new_release", source: .musicNewReleaseAlbums),
            HomeCategory(id: "podcasts", source: .search(HomeLocalizedQuery.resolve("podcasts", region: gl))),
            HomeCategory(id: "news", source: .catalogNews),
            HomeCategory(id: "live", source: .live),
            HomeCategory(id: "charts", source: .search(HomeLocalizedQuery.resolve("charts", region: gl))),
            HomeCategory(id: "mixes", source: .search(HomeLocalizedQuery.resolve("mixes", region: gl))),
            HomeCategory(id: "albums", source: .musicNewReleaseAlbums),
            HomeCategory(id: "rnb", source: .search(HomeLocalizedQuery.resolve("rnb", region: gl))),
            HomeCategory(id: "mandopop", source: .search(HomeLocalizedQuery.resolve("mandopop", region: gl))),
            HomeCategory(id: "electropop", source: .search(HomeLocalizedQuery.resolve("electropop", region: gl))),
            HomeCategory(id: "energize", source: .search(HomeLocalizedQuery.resolve("energize", region: gl))),
            HomeCategory(id: "feel_good", source: .search(HomeLocalizedQuery.resolve("feel_good", region: gl))),
            HomeCategory(id: "workout", source: .search(HomeLocalizedQuery.resolve("workout", region: gl))),
            HomeCategory(id: "chill", source: .search(HomeLocalizedQuery.resolve("chill", region: gl))),
            HomeCategory(id: "party", source: .search(HomeLocalizedQuery.resolve("party", region: gl))),
            HomeCategory(id: "romance", source: .search(HomeLocalizedQuery.resolve("romance", region: gl))),
            HomeCategory(id: "commute", source: .search(HomeLocalizedQuery.resolve("commute", region: gl))),
            HomeCategory(id: "focus", source: .search(HomeLocalizedQuery.resolve("focus", region: gl))),
            HomeCategory(id: "sad", source: .search(HomeLocalizedQuery.resolve("sad", region: gl))),
            HomeCategory(id: "sleep", source: .search(HomeLocalizedQuery.resolve("sleep", region: gl))),
        ]
    }

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
                        : (key == "news" ? .catalogNews : .innerTube(chip.endpoint)),
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
    @Published private(set) var isLoadingMore = false
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
    /// All tab: browse home vs search fallback pagination (Android `feedSearchQuery == null`).
    private var allFeedUsesSearchPagination = false
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

    var hasMore: Bool {
        !(continuation ?? "").isEmpty
    }

    func playIndex(for item: VideoItem) -> Int {
        playableIndexById[item.videoId] ?? 0
    }

    func selectCategory(_ category: HomeCategory) {
        guard category.id != selectedCategoryId else { return }
        selectedCategoryId = category.id
        HomeFeedStore.saveSelectedCategoryId(category.id)
        errorMessage = nil
        // Align Android: show disk/memory store immediately; network only if empty.
        applyStoredFeed(for: category.id)
        refreshIfNeeded()
    }

    /// Swipe between top chips: negative delta = previous, positive = next.
    @discardableResult
    func selectAdjacentCategory(delta: Int) -> Bool {
        guard delta != 0 else { return false }
        guard let index = orderedCategories.firstIndex(where: { $0.id == selectedCategoryId })
        else { return false }
        let next = index + delta
        guard orderedCategories.indices.contains(next) else { return false }
        selectCategory(orderedCategories[next])
        return true
    }

    func appear() {
        Self.migrateAlbumsChipSourceIfNeeded()
        applyStoredFeed(for: selectedCategoryId)
        refreshIfNeeded()
        refreshDynamicChipsIfNeeded()
    }

    /// Albums chip used to search a keyword; wipe stale video rows once after switching to album browse.
    private static func migrateAlbumsChipSourceIfNeeded() {
        let key = "home.albums.source.music_new_release.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        HomeFeedStore.clearCategory("albums")
        UserDefaults.standard.set(true, forKey: key)
    }

    func handleContentLocaleChange() {
        loadGeneration += 1
        rawEntries = []
        entries = []
        playableVideos = []
        continuation = nil
        allFeedUsesSearchPagination = false
        errorMessage = nil
        didRequestDynamicChips = false
        dynamicChips = HomeFeedStore.loadDynamicChips()
        // Rebuild static chip search queries for the new `gl`.
        orderedCategories = HomeCategory.applyingSavedOrder(
            to: HomeCategory.merged(with: dynamicChips)
        )
        if !orderedCategories.contains(where: { $0.id == selectedCategoryId }) {
            selectedCategoryId = "all"
            HomeFeedStore.saveSelectedCategoryId("all")
        }
        Task { await refresh(force: true) }
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

    /// Infinite scroll — append the next InnerTube page when near the list bottom.
    func loadMoreIfNeeded() {
        guard hasMore, !isLoadingMore, !isRefreshInFlight else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard let token = continuation, !token.isEmpty else { return }
        guard !isLoadingMore, !isRefreshInFlight else { return }

        let category = selectedCategory
        let requestId = category.id
        isLoadingMore = true
        defer { isLoadingMore = false }

        HomeFeedProbe.log(
            "loadMore.start",
            "category=\(requestId) contPrefix=\(continuationPrefix(token)) count=\(rawEntries.count)"
        )

        do {
            let page = try await fetchPage(for: category, continuation: token)
            guard requestId == selectedCategoryId else {
                HomeFeedProbe.log(
                    "loadMore.stale",
                    "req=\(requestId) selected=\(selectedCategoryId)"
                )
                return
            }
            let merged = mergeEntries(rawEntries, page.entries)
            rawEntries = merged
            entries = applyLibraryFilter(merged)
            rebuildPlayableIndex(from: entries)
            if page.entries.isEmpty, page.continuation == token {
                continuation = nil
            } else {
                continuation = page.continuation
            }
            HomeFeedStore.save(
                categoryId: requestId,
                entries: merged,
                continuation: page.continuation,
                allFeedUsesSearchPagination: requestId == "all" ? allFeedUsesSearchPagination : false
            )
            HomeFeedProbe.log(
                "loadMore.ok",
                "added=\(page.entries.count) total=\(merged.count) hasNext=\(!(page.continuation ?? "").isEmpty)"
            )
        } catch is CancellationError {
            HomeFeedProbe.log("loadMore.cancelled", "category=\(requestId)")
        } catch {
            if Task.isCancelled { return }
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
            HomeFeedProbe.log(
                "loadMore.error",
                "category=\(requestId) err=\(error.localizedDescription)"
            )
        }
    }

    private func mergeEntries(_ existing: [HomeFeedEntry], _ incoming: [HomeFeedEntry]) -> [HomeFeedEntry] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        merged.reserveCapacity(existing.count + incoming.count)
        for entry in incoming where seen.insert(entry.id).inserted {
            merged.append(entry)
        }
        return merged
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

    /// Network only when this category has no stored content (Android preferStore).
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
        // Non-force with existing UI content is a no-op (store already shown).
        if !force, !entries.isEmpty {
            HomeFeedProbe.log(
                "refresh.skip",
                "reason=store_hit force=false count=\(entries.count) category=\(requestId)"
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
            if requestId == "all" {
                allFeedUsesSearchPagination = page.allFeedUsesSearchPagination
            }
            if let chips = page.chips {
                acceptDynamicChips(chips)
            }
            if page.entries.isEmpty {
                errorMessage = "No videos in feed"
                HomeFeedProbe.log("refresh.empty", "category=\(requestId)")
                AppAnalytics.homeFeedLoad(ok: false, count: 0, category: requestId)
            } else {
                errorMessage = nil
                HomeFeedStore.save(
                    categoryId: requestId,
                    entries: page.entries,
                    continuation: page.continuation,
                    allFeedUsesSearchPagination: requestId == "all" ? allFeedUsesSearchPagination : false
                )
                AppAnalytics.homeFeedLoad(ok: true, count: page.entries.count, category: requestId)
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
            AppAnalytics.homeFeedLoad(ok: false, count: entries.count, category: requestId)
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
        var allFeedUsesSearchPagination: Bool = false
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
            if allFeedUsesSearchPagination {
                let page = try await InnerTubeClient.searchVideosPage(
                    query: InnerTubeClient.homeSearchFallbackQuery,
                    continuation: token
                )
                return FeedPage(
                    entries: page.videos.map { .track($0) },
                    continuation: page.continuation,
                    allFeedUsesSearchPagination: true
                )
            }
            let page = try await InnerTubeClient.fetchHomeFeedPage(continuation: token)
            return FeedPage(
                entries: page.videos.map { .track($0) },
                continuation: page.continuation,
                chips: token == nil ? page.chips : nil,
                allFeedUsesSearchPagination: page.paginationUsesSearchFallback
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
        case .catalogNews:
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
            allFeedUsesSearchPagination = stored.allFeedUsesSearchPagination
            HomeFeedProbe.log(
                "store.load",
                "category=\(categoryId) count=\(stored.entries.count) hasCont=\(!(stored.continuation ?? "").isEmpty) searchPag=\(stored.allFeedUsesSearchPagination)"
            )
        } else {
            rawEntries = []
            continuation = nil
            allFeedUsesSearchPagination = false
            HomeFeedProbe.log("store.miss", "category=\(categoryId)")
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
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var libraryStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showCategoryReorder = false
    @EnvironmentObject private var playerPresentation: PlayerPresentation

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryChips
                categoryPager
            }
            .ytLiteContentWidth(enabled: YTLiteAdaptive.isRegularWidth(horizontalSizeClass))
            .background(YTLiteColor.background)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                viewModel.libraryStore = libraryStore
                guard !appModel.isAwaitingLocaleSetup else { return }
                viewModel.appear()
            }
            .onChange(of: appModel.isAwaitingLocaleSetup) { _, awaiting in
                guard !awaiting else { return }
                viewModel.handleContentLocaleChange()
            }
            .onChange(of: libraryStore != nil) { _, _ in
                viewModel.libraryStore = libraryStore
                viewModel.refilter()
            }
            .onChange(of: trackActions.listEpoch) { _, _ in
                viewModel.refilter()
            }
            .onChange(of: appModel.contentLocaleRevision) { _, _ in
                viewModel.handleContentLocaleChange()
            }
            .sheet(isPresented: $showCategoryReorder) {
                CategoryReorderSheet(
                    categories: viewModel.orderedCategories,
                    onDone: { ordered in
                        viewModel.applyCategoryOrder(ordered)
                        showCategoryReorder = false
                    },
                    onCancel: {
                        showCategoryReorder = false
                    }
                )
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
                    .padding(.trailing, YTLiteLayout.stackTight)
                    .padding(.vertical, YTLiteLayout.stackLoose)
                }

                Button {
                    showCategoryReorder = true
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                        // Match YTLiteChip height (subheadline + chipVertical×2 ≈ 32–34).
                        .frame(width: 32, height: 32)
                        .background(YTLiteColor.surfaceChip, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("home.category.reorder"))
                .padding(.leading, YTLiteLayout.stackLoose)
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

    /// Interactive page swipe between chips — content tracks the finger.
    private var categoryPager: some View {
        TabView(selection: categorySelection) {
            ForEach(viewModel.orderedCategories) { category in
                categoryPage(for: category)
                    .tag(category.id)
                    .allowsHitTesting(viewModel.selectedCategoryId == category.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(YTLiteColor.background)
    }

    private var categorySelection: Binding<String> {
        Binding(
            get: { viewModel.selectedCategoryId },
            set: { newId in
                guard newId != viewModel.selectedCategoryId,
                      let category = viewModel.orderedCategories.first(where: { $0.id == newId })
                else { return }
                viewModel.selectCategory(category)
            }
        )
    }

    @ViewBuilder
    private func categoryPage(for category: HomeCategory) -> some View {
        let selected = viewModel.selectedCategoryId == category.id
        if selected {
            selectedCategoryContent
        } else {
            previewCategoryPage(categoryId: category.id)
        }
    }

    @ViewBuilder
    private var selectedCategoryContent: some View {
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
            .ytLiteMiniPlayerScrollInset()
        } else {
            ScrollViewReader { proxy in
                GeometryReader { geo in
                    let columns = YTLiteAdaptive.feedColumns(
                        for: geo.size.width,
                        sizeClass: horizontalSizeClass
                    )
                    let compact = columns > 1
                    ScrollView {
                        // Keep the scroll-to-top anchor *outside* the grid — a zero-height
                        // cell inside LazyVGrid still shares row height with neighbors and
                        // leaves a blank “black card” on multi-column layouts.
                        Color.clear
                            .frame(height: 0)
                            .id("home_feed_top")
                        // Isolate from PlaybackController publish storms while flinging the feed.
                        HomeFeedGridPane(
                            token: homeFeedToken(for: viewModel.selectedCategoryId, entries: viewModel.entries),
                            entries: viewModel.entries,
                            columns: columns,
                            compact: compact,
                            horizontalPadding: compact
                                ? YTLiteAdaptive.screenPadding(for: geo.size.width, sizeClass: horizontalSizeClass) - 4
                                : 0,
                            errorMessage: viewModel.errorMessage,
                            isLoadingMore: viewModel.isLoadingMore,
                            onPlayTrack: { item in
                                let queue = viewModel.playableVideos
                                let playIndex = viewModel.playIndex(for: item)
                                playback.play(
                                    items: queue.isEmpty ? [item] : queue,
                                    startAt: playIndex,
                                    analyticsSource: "home"
                                )
                                playerPresentation.present()
                            },
                            onMore: { trackActions.present(item: $0) },
                            onNearEnd: { index in
                                if index >= max(0, viewModel.entries.count - 3) {
                                    viewModel.loadMoreIfNeeded()
                                }
                            }
                        )
                        .equatable()
                    }
                    .refreshable {
                        HomeFeedProbe.log(
                            "ui.refreshable",
                            "path=list category=\(viewModel.selectedCategoryId) count=\(viewModel.entries.count)"
                        )
                        await viewModel.refresh()
                    }
                    .ytLiteMiniPlayerScrollInset()
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

    /// ***
    @ViewBuilder
    private func previewCategoryPage(categoryId: String) -> some View {
        let entries = previewEntries(for: categoryId)
        if entries.isEmpty {
            YTLiteColor.background
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let columns = YTLiteAdaptive.feedColumns(
                    for: geo.size.width,
                    sizeClass: horizontalSizeClass
                )
                let compact = columns > 1
                ScrollView {
                    HomeFeedGridPane(
                        token: homeFeedToken(for: categoryId, entries: entries),
                        entries: entries,
                        columns: columns,
                        compact: compact,
                        horizontalPadding: compact
                            ? YTLiteAdaptive.screenPadding(for: geo.size.width, sizeClass: horizontalSizeClass) - 4
                            : 0,
                        errorMessage: nil,
                        isLoadingMore: false,
                        onPlayTrack: { _ in },
                        onMore: { _ in },
                        onNearEnd: { _ in }
                    )
                    .equatable()
                }
                .scrollDisabled(true)
                .ytLiteMiniPlayerScrollInset()
            }
        }
    }

    private func previewEntries(for categoryId: String) -> [HomeFeedEntry] {
        let raw = HomeFeedStore.loadFeed(categoryId: categoryId)?.entries ?? []
        guard let libraryStore else { return raw }
        return raw.compactMap { entry in
            switch entry {
            case .album:
                return entry
            case .track(let video):
                return libraryStore.filterNotInterested([video]).isEmpty ? nil : entry
            }
        }
    }

    /// Cheap identity for Equatable feed grid (avoids comparing full entry arrays each tick).
    private func homeFeedToken(for categoryId: String, entries: [HomeFeedEntry]) -> Int {
        var hasher = Hasher()
        hasher.combine(categoryId)
        hasher.combine(entries.count)
        hasher.combine(entries.first?.id)
        hasher.combine(entries.last?.id)
        hasher.combine(viewModel.isLoadingMore && categoryId == viewModel.selectedCategoryId)
        hasher.combine(categoryId == viewModel.selectedCategoryId ? viewModel.errorMessage : nil)
        return hasher.finalize()
    }
}

/// Home feed cells — skips body when only playback publishes.
private struct HomeFeedGridPane: View, Equatable {
    let token: Int
    let entries: [HomeFeedEntry]
    let columns: Int
    let compact: Bool
    let horizontalPadding: CGFloat
    let errorMessage: String?
    let isLoadingMore: Bool
    let onPlayTrack: (VideoItem) -> Void
    let onMore: (VideoItem) -> Void
    let onNearEnd: (Int) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.token == rhs.token
            && lhs.columns == rhs.columns
            && lhs.compact == rhs.compact
            && lhs.horizontalPadding == rhs.horizontalPadding
    }

    var body: some View {
        LazyVGrid(
            columns: YTLiteAdaptive.gridItems(count: columns, spacing: compact ? 12 : 0),
            spacing: compact ? 16 : 0
        ) {
            if let err = errorMessage {
                Text(err)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.danger)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gridCellColumns(columns)
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                switch entry {
                case .track(let item):
                    FeedVideoCard(
                        item: item,
                        onTap: { onPlayTrack(item) },
                        onMore: { onMore(item) },
                        compact: compact
                    )
                    .onAppear { onNearEnd(index) }
                case .album(let album):
                    NavigationLink {
                        AlbumTracksView(album: album)
                    } label: {
                        HomeAlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                    .gridCellColumns(columns)
                    .onAppear { onNearEnd(index) }
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
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, YTLiteLayout.rowVertical)
    }
}

/// Standalone sheet so `@State` is seeded from current categories at presentation time
/// (parent `@State` + `isPresented` often opened with an empty list).
private struct CategoryReorderSheet: View {
    @State private var categories: [HomeCategory]
    let onDone: ([HomeCategory]) -> Void
    let onCancel: () -> Void

    init(
        categories: [HomeCategory],
        onDone: @escaping ([HomeCategory]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _categories = State(initialValue: categories)
        self.onDone = onDone
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories) { category in
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
                    categories.move(
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
                        onDone(categories)
                    }
                    .font(YTLiteType.labelEmphasized)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel"), action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
    @State private var tracksVersion: Int = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @EnvironmentObject private var playerPresentation: PlayerPresentation

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(YTLiteColor.accent)
            } else {
                MediaTracksListPane(
                    tracks: tracks,
                    tracksVersion: tracksVersion,
                    emptyTitle: L("common.no_tracks"),
                    emptySystemImage: "music.note.list",
                    emptyDescription: errorMessage ?? "",
                    onPlay: { index in
                        playback.play(items: tracks, startAt: index, analyticsSource: "home")
                        playerPresentation.present()
                    },
                    onMore: { trackActions.present(item: $0) }
                )
                .equatable()
            }
        }
        .background(YTLiteColor.background)
        .ytLiteMiniPlayerScrollInset()
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
                let next = libraryStore?.filterNotInterested(fetched) ?? fetched
                if next.map(\.videoId) != tracks.map(\.videoId) {
                    tracksVersion &+= 1
                }
                tracks = next
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
    }
}
