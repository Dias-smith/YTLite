import Foundation

/// Persisted home category payloads (memory + disk) for fast reopen / chip switch.
/// Align Android `HomeFeedStore`: show store on switch; network only when empty or pull-to-refresh.
enum HomeFeedStore {
    private static let folderName = "home_feed"
    private static let selectedCategoryKey = "home_selected_category_id"
    private static let categoryOrderKey = "home_category_order"
    private static let dynamicChipsKeyPrefix = "home_dynamic_chips"
    /// Cover all home chips in memory (All + New release + moods).
    private static let maxMemoryEntries = 16
    private static var memory: [String: Snapshot] = [:]
    private static let lock = NSLock()

    private static func localeKey() -> String {
        "\(CatalogConstants.hl)_\(CatalogConstants.gl)"
    }

    private static func memoryKey(for categoryId: String) -> String {
        "\(localeKey())|\(categoryId)"
    }

    private static func dynamicChipsDefaultsKey() -> String {
        "\(dynamicChipsKeyPrefix)_\(localeKey())"
    }

    /// ***
    static func invalidateMemoryCache() {
        lock.lock()
        memory.removeAll()
        lock.unlock()
    }

    struct Snapshot: Codable, Sendable {
        let categoryId: String
        let savedAt: Date
        let items: [Entry]
        let continuation: String?
        let allFeedUsesSearchPagination: Bool?

        init(
            categoryId: String,
            savedAt: Date,
            items: [Entry],
            continuation: String? = nil,
            allFeedUsesSearchPagination: Bool? = nil
        ) {
            self.categoryId = categoryId
            self.savedAt = savedAt
            self.items = items
            self.continuation = continuation
            self.allFeedUsesSearchPagination = allFeedUsesSearchPagination
        }
    }

    struct LoadedFeed: Sendable {
        let entries: [HomeFeedEntry]
        let continuation: String?
        let allFeedUsesSearchPagination: Bool
    }

    struct Entry: Codable, Sendable {
        enum Kind: String, Codable, Sendable {
            case track
            case album
        }

        let kind: Kind
        // Track
        let videoId: String?
        let title: String
        let channelName: String?
        let subtitle: String?
        let thumbnailURLString: String?
        let channelAvatarURLString: String?
        let durationText: String?
        let viewCountText: String?
        let publishedTimeText: String?
        let isLive: Bool?
        // Album
        let browseId: String?
        let artistName: String?
        let releaseType: String?
        let playlistId: String?

        init(_ item: VideoItem) {
            kind = .track
            videoId = item.videoId
            title = item.title
            channelName = item.channelName
            subtitle = item.subtitle
            thumbnailURLString = item.thumbnailURL?.absoluteString
            channelAvatarURLString = item.channelAvatarURL?.absoluteString
            durationText = item.durationText
            viewCountText = item.viewCountText
            publishedTimeText = item.publishedTimeText
            isLive = item.isLive
            browseId = nil
            artistName = nil
            releaseType = nil
            playlistId = nil
        }

        init(_ album: MusicAlbumRelease) {
            kind = .album
            videoId = nil
            title = album.title
            channelName = nil
            subtitle = nil
            thumbnailURLString = album.thumbnailURL?.absoluteString
            channelAvatarURLString = nil
            durationText = nil
            viewCountText = nil
            publishedTimeText = nil
            isLive = nil
            browseId = album.browseId
            artistName = album.artistName
            releaseType = album.releaseType
            playlistId = album.playlistId
        }

        init(_ entry: HomeFeedEntry) {
            switch entry {
            case .track(let video): self.init(video)
            case .album(let album): self.init(album)
            }
        }

        var asHomeFeedEntry: HomeFeedEntry? {
            switch kind {
            case .track:
                guard let videoId, !videoId.isEmpty else { return nil }
                return .track(
                    VideoItem(
                        videoId: videoId,
                        title: title,
                        channelName: channelName ?? "",
                        subtitle: subtitle ?? "",
                        thumbnailURL: thumbnailURLString.flatMap(URL.init(string:)),
                        channelAvatarURL: channelAvatarURLString.flatMap(URL.init(string:)),
                        durationText: durationText,
                        viewCountText: viewCountText,
                        publishedTimeText: publishedTimeText,
                        isLive: isLive ?? false
                    )
                )
            case .album:
                guard let browseId, !browseId.isEmpty else { return nil }
                return .album(
                    MusicAlbumRelease(
                        browseId: browseId,
                        title: title,
                        artistName: artistName ?? "",
                        thumbnailURL: thumbnailURLString.flatMap(URL.init(string:)),
                        releaseType: releaseType ?? "",
                        playlistId: playlistId
                    )
                )
            }
        }
    }

    /// Last selected home chip (mirrors Android `HomePreferences`).
    static func loadSelectedCategoryId() -> String? {
        UserDefaults.standard.string(forKey: selectedCategoryKey)
    }

    static func saveSelectedCategoryId(_ categoryId: String) {
        UserDefaults.standard.set(categoryId, forKey: selectedCategoryKey)
    }

    static func loadCategoryOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: categoryOrderKey) ?? []
    }

    /// Keep temporarily missing dynamic ids so they regain their former position when returned.
    static func saveCategoryOrder(_ visibleIds: [String]) {
        let old = loadCategoryOrder()
        let hidden = old.filter { !visibleIds.contains($0) }
        UserDefaults.standard.set(visibleIds + hidden, forKey: categoryOrderKey)
    }

    private struct DynamicChipSnapshot: Codable {
        let savedAt: Date
        let chips: [HomeDynamicChip]
    }

    static func loadDynamicChips(maxAge: TimeInterval = 30 * 24 * 60 * 60) -> [HomeDynamicChip] {
        guard let data = UserDefaults.standard.data(forKey: dynamicChipsDefaultsKey()),
              let snapshot = try? JSONDecoder().decode(DynamicChipSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) <= maxAge
        else { return [] }
        return snapshot.chips
    }

    static func saveDynamicChips(_ chips: [HomeDynamicChip]) {
        guard !chips.isEmpty else { return }
        let snapshot = DynamicChipSnapshot(savedAt: .now, chips: chips)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: dynamicChipsDefaultsKey())
    }

    static func loadEntries(categoryId: String) -> [HomeFeedEntry]? {
        loadFeed(categoryId: categoryId)?.entries
    }

    /// ***
    static func titleHintsByVideoId() -> [String: (title: String, channelName: String)] {
        var hints: [String: (title: String, channelName: String)] = [:]
        func ingest(_ entries: [Entry]) {
            for entry in entries where entry.kind == .track {
                guard let videoId = entry.videoId, !videoId.isEmpty else { continue }
                guard !TrackTitle.isPlaceholder(entry.title, videoId: videoId) else { continue }
                if hints[videoId] != nil { continue }
                hints[videoId] = (entry.title, entry.channelName ?? "")
            }
        }
        lock.lock()
        let memorySnapshots = Array(memory.values)
        lock.unlock()
        for snapshot in memorySnapshots {
            ingest(snapshot.items)
        }
        let dir = directoryURL()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return hints }
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = decodeSnapshot(data)
            else { continue }
            ingest(snapshot.items)
        }
        return hints
    }

    static func loadFeed(categoryId: String) -> LoadedFeed? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = memory[memoryKey(for: categoryId)] {
            let entries = hit.items.compactMap(\.asHomeFeedEntry)
            return entries.isEmpty ? nil : LoadedFeed(
                entries: entries,
                continuation: hit.continuation,
                allFeedUsesSearchPagination: hit.allFeedUsesSearchPagination ?? false
            )
        }
        guard let data = try? Data(contentsOf: fileURL(for: categoryId)),
              let snapshot = decodeSnapshot(data)
        else { return nil }
        memory[memoryKey(for: categoryId)] = snapshot
        trimMemoryLocked()
        let entries = snapshot.items.compactMap(\.asHomeFeedEntry)
        return entries.isEmpty ? nil : LoadedFeed(
            entries: entries,
            continuation: snapshot.continuation,
            allFeedUsesSearchPagination: snapshot.allFeedUsesSearchPagination ?? false
        )
    }

    /// Drop memory + disk snapshot for one chip (e.g. after source type changes).
    static func clearCategory(_ categoryId: String) {
        lock.lock()
        memory.removeValue(forKey: memoryKey(for: categoryId))
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL(for: categoryId))
    }

    static func save(
        categoryId: String,
        entries: [HomeFeedEntry],
        continuation: String? = nil,
        allFeedUsesSearchPagination: Bool = false
    ) {
        guard !entries.isEmpty else { return }
        let snapshot = Snapshot(
            categoryId: categoryId,
            savedAt: .now,
            items: entries.map(Entry.init),
            continuation: continuation,
            allFeedUsesSearchPagination: categoryId == "all" ? allFeedUsesSearchPagination : nil
        )
        lock.lock()
        memory[memoryKey(for: categoryId)] = snapshot
        trimMemoryLocked()
        lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: directoryURL(), withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL(for: categoryId), options: .atomic)
        }
    }

    /// Decode current schema, or migrate older track-only snapshots.
    private static func decodeSnapshot(_ data: Data) -> Snapshot? {
        if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return snapshot
        }
        // Legacy: `{ categoryId, savedAt, items: [{ videoId, title, ... }] }` without `kind`.
        struct LegacySnapshot: Codable {
            let categoryId: String
            let savedAt: Date
            let items: [LegacyTrack]
        }
        struct LegacyTrack: Codable {
            let videoId: String
            let title: String
            let channelName: String
            let subtitle: String
            let thumbnailURLString: String?
            let channelAvatarURLString: String?
            let durationText: String?
            let viewCountText: String?
            let publishedTimeText: String?
        }
        guard let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data) else {
            return nil
        }
        let items: [Entry] = legacy.items.map { t in
            Entry(
                VideoItem(
                    videoId: t.videoId,
                    title: t.title,
                    channelName: t.channelName,
                    subtitle: t.subtitle,
                    thumbnailURL: t.thumbnailURLString.flatMap(URL.init(string:)),
                    channelAvatarURL: t.channelAvatarURLString.flatMap(URL.init(string:)),
                    durationText: t.durationText,
                    viewCountText: t.viewCountText,
                    publishedTimeText: t.publishedTimeText
                )
            )
        }
        return Snapshot(categoryId: legacy.categoryId, savedAt: legacy.savedAt, items: items)
    }

    private static func trimMemoryLocked() {
        while memory.count > maxMemoryEntries {
            guard let eldest = memory.keys.first else { break }
            memory.removeValue(forKey: eldest)
        }
    }

    private static func directoryURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(localeKey(), isDirectory: true)
    }

    private static func fileURL(for categoryId: String) -> URL {
        let safe = categoryId.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "_",
            options: .regularExpression
        )
        return directoryURL().appendingPathComponent("\(safe).json")
    }
}

// MARK: - Duration buckets (multi-select; empty = any)

enum HomeDurationFilter: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case overOneHour
    case from30To60Minutes
    case from10To30Minutes
    case from3To10Minutes
    case under3Minutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overOneHour: return L("home.filter.duration.over_1h")
        case .from30To60Minutes: return L("home.filter.duration.30m_1h")
        case .from10To30Minutes: return L("home.filter.duration.10m_30m")
        case .from3To10Minutes: return L("home.filter.duration.3m_10m")
        case .under3Minutes: return L("home.filter.duration.under_3m")
        }
    }

    func matches(seconds: Int) -> Bool {
        guard seconds > 0 else { return false }
        switch self {
        case .overOneHour: return seconds > 3600
        case .from30To60Minutes: return seconds >= 1800 && seconds <= 3600
        case .from10To30Minutes: return seconds >= 600 && seconds < 1800
        case .from3To10Minutes: return seconds >= 180 && seconds < 600
        case .under3Minutes: return seconds > 0 && seconds < 180
        }
    }
}

// MARK: - View-count buckets (multi-select; empty = any)

enum HomeViewCountFilter: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case over1M
    case from10KTo1M
    case under10K

    var id: String { rawValue }

    var title: String {
        switch self {
        case .over1M: return L("home.filter.views.over_1m")
        case .from10KTo1M: return L("home.filter.views.10k_1m")
        case .under10K: return L("home.filter.views.under_10k")
        }
    }

    func matches(count: Int64) -> Bool {
        guard count >= 0 else { return false }
        switch self {
        case .over1M: return count > 1_000_000
        case .from10KTo1M: return count >= 10_000 && count <= 1_000_000
        case .under10K: return count < 10_000
        }
    }
}

// MARK: - Selection state

struct HomeFeedFilter: Equatable, Codable, Sendable {
    var durations: Set<HomeDurationFilter>
    var viewCounts: Set<HomeViewCountFilter>

    static let `default` = HomeFeedFilter(durations: [], viewCounts: [])

    var isActive: Bool {
        !durations.isEmpty || !viewCounts.isEmpty
    }

    func matches(_ video: VideoItem) -> Bool {
        if !durations.isEmpty {
            // Live / missing duration cannot satisfy a duration bucket.
            let seconds = DurationFormat.seconds(from: video.durationText)
            guard durations.contains(where: { $0.matches(seconds: seconds) }) else { return false }
        }
        if !viewCounts.isEmpty {
            guard let count = ViewCountFormat.count(from: video.viewCountText),
                  viewCounts.contains(where: { $0.matches(count: count) })
            else { return false }
        }
        return true
    }

    func matches(_ entry: HomeFeedEntry) -> Bool {
        switch entry {
        case .album:
            // Album rows have no duration/views — keep them when filtering tracks.
            return true
        case .track(let video):
            return matches(video)
        }
    }
}

// MARK: - Persistence

enum HomeFeedFilterStore {
    private static let defaultsKey = "home.feed.filter.v1"

    static func load() -> HomeFeedFilter {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(HomeFeedFilter.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ filter: HomeFeedFilter) {
        guard let data = try? JSONEncoder().encode(filter) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

/// Independent persistence for Search results (same filter model as Home).
enum SearchResultsFilterStore {
    private static let defaultsKey = "search.results.filter.v1"

    static func load() -> HomeFeedFilter {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(HomeFeedFilter.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ filter: HomeFeedFilter) {
        guard let data = try? JSONEncoder().encode(filter) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

// MARK: - View count parsing ("1.2M views", "15K", "120万次观看", …)

enum ViewCountFormat {
    /// Best-effort parse of InnerTube short / localized view strings. `nil` if unknown.
    static func count(from text: String?) -> Int64? {
        guard var raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return nil }

        // Drop common suffixes / noise.
        let lowered = raw.lowercased()
        if lowered.contains("watching") || lowered.contains("正在观看") { return nil }

        raw = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")

        // Chinese units first (万 / 亿).
        if let yi = raw.range(of: "亿") {
            let head = String(raw[..<yi.lowerBound])
            if let n = parseLeadingNumber(head) {
                return Int64((n * 100_000_000).rounded())
            }
        }
        if let wan = raw.range(of: "万") {
            let head = String(raw[..<wan.lowerBound])
            if let n = parseLeadingNumber(head) {
                return Int64((n * 10_000).rounded())
            }
        }

        let compact = raw.lowercased()
        if let range = compact.range(of: #"([0-9]*\.?[0-9]+)\s*([kmb])"#, options: .regularExpression) {
            let token = String(compact[range])
            if let n = parseLeadingNumber(token),
               let unit = token.last
            {
                let mult: Double
                switch unit {
                case "k": mult = 1_000
                case "m": mult = 1_000_000
                case "b": mult = 1_000_000_000
                default: mult = 1
                }
                return Int64((n * mult).rounded())
            }
        }

        if let n = parseLeadingNumber(compact) {
            return Int64(n.rounded())
        }
        return nil
    }

    private static func parseLeadingNumber(_ text: String) -> Double? {
        var digits = ""
        var seenDot = false
        for ch in text {
            if ch.isNumber {
                digits.append(ch)
            } else if ch == ".", !seenDot {
                digits.append(ch)
                seenDot = true
            } else if digits.isEmpty {
                continue
            } else {
                break
            }
        }
        guard !digits.isEmpty, digits != "." else { return nil }
        return Double(digits)
    }
}
