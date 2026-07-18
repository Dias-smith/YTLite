import Foundation

/// Persisted home category payloads (memory + disk) for fast reopen / chip switch.
/// Align Android `HomeFeedCache`: show cache on switch; network only when empty or pull-to-refresh.
enum HomeFeedStore {
    private static let folderName = "home_feed"
    private static let selectedCategoryKey = "home_selected_category_id"
    private static let categoryOrderKey = "home_category_order"
    private static let dynamicChipsKey = "home_dynamic_chips"
    /// Cover all home chips in memory (All + New release + moods).
    private static let maxMemoryEntries = 16
    private static var memory: [String: Snapshot] = [:]
    private static let lock = NSLock()

    struct Snapshot: Codable, Sendable {
        let categoryId: String
        let savedAt: Date
        let items: [Entry]
        let continuation: String?

        init(
            categoryId: String,
            savedAt: Date,
            items: [Entry],
            continuation: String? = nil
        ) {
            self.categoryId = categoryId
            self.savedAt = savedAt
            self.items = items
            self.continuation = continuation
        }
    }

    struct LoadedFeed: Sendable {
        let entries: [HomeFeedEntry]
        let continuation: String?
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
        guard let data = UserDefaults.standard.data(forKey: dynamicChipsKey),
              let snapshot = try? JSONDecoder().decode(DynamicChipSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) <= maxAge
        else { return [] }
        return snapshot.chips
    }

    static func saveDynamicChips(_ chips: [HomeDynamicChip]) {
        guard !chips.isEmpty else { return }
        let snapshot = DynamicChipSnapshot(savedAt: .now, chips: chips)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: dynamicChipsKey)
    }

    static func loadEntries(categoryId: String) -> [HomeFeedEntry]? {
        loadFeed(categoryId: categoryId)?.entries
    }

    static func loadFeed(categoryId: String) -> LoadedFeed? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = memory[categoryId] {
            let entries = hit.items.compactMap(\.asHomeFeedEntry)
            return entries.isEmpty ? nil : LoadedFeed(entries: entries, continuation: hit.continuation)
        }
        guard let data = try? Data(contentsOf: fileURL(for: categoryId)),
              let snapshot = decodeSnapshot(data)
        else { return nil }
        memory[categoryId] = snapshot
        trimMemoryLocked()
        let entries = snapshot.items.compactMap(\.asHomeFeedEntry)
        return entries.isEmpty ? nil : LoadedFeed(entries: entries, continuation: snapshot.continuation)
    }

    static func save(
        categoryId: String,
        entries: [HomeFeedEntry],
        continuation: String? = nil
    ) {
        guard !entries.isEmpty else { return }
        let snapshot = Snapshot(
            categoryId: categoryId,
            savedAt: .now,
            items: entries.map(Entry.init),
            continuation: continuation
        )
        lock.lock()
        memory[categoryId] = snapshot
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
        return base.appendingPathComponent(folderName, isDirectory: true)
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
