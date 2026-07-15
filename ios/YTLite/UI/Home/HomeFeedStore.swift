import Foundation

/// Persisted home category payloads (memory + disk) for fast reopen / chip switch.
enum HomeFeedStore {
    private static let folderName = "home_feed"
    private static let maxMemoryEntries = 8
    private static var memory: [String: Snapshot] = [:]
    private static let lock = NSLock()

    struct Snapshot: Codable, Sendable {
        let categoryId: String
        let savedAt: Date
        let items: [Entry]
    }

    struct Entry: Codable, Sendable {
        let videoId: String
        let title: String
        let channelName: String
        let subtitle: String
        let thumbnailURLString: String?
        let channelAvatarURLString: String?
        let durationText: String?
        let viewCountText: String?
        let publishedTimeText: String?

        init(_ item: VideoItem) {
            videoId = item.videoId
            title = item.title
            channelName = item.channelName
            subtitle = item.subtitle
            thumbnailURLString = item.thumbnailURL?.absoluteString
            channelAvatarURLString = item.channelAvatarURL?.absoluteString
            durationText = item.durationText
            viewCountText = item.viewCountText
            publishedTimeText = item.publishedTimeText
        }

        var asVideoItem: VideoItem {
            VideoItem(
                videoId: videoId,
                title: title,
                channelName: channelName,
                subtitle: subtitle,
                thumbnailURL: thumbnailURLString.flatMap(URL.init(string:)),
                channelAvatarURL: channelAvatarURLString.flatMap(URL.init(string:)),
                durationText: durationText,
                viewCountText: viewCountText,
                publishedTimeText: publishedTimeText
            )
        }
    }

    static func loadVideos(categoryId: String) -> [VideoItem]? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = memory[categoryId] {
            return hit.items.map(\.asVideoItem)
        }
        guard let data = try? Data(contentsOf: fileURL(for: categoryId)),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }
        memory[categoryId] = snapshot
        trimMemoryLocked()
        return snapshot.items.map(\.asVideoItem)
    }

    static func save(categoryId: String, videos: [VideoItem]) {
        guard !videos.isEmpty else { return }
        let snapshot = Snapshot(
            categoryId: categoryId,
            savedAt: .now,
            items: videos.map(Entry.init)
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
