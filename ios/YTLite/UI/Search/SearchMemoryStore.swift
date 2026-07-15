import Foundation

@MainActor
final class SearchMemoryStore: ObservableObject {
    @Published private(set) var recentQueries: [String] = []
    @Published private(set) var recentVideos: [VideoItem] = []

    private let queriesKey = "search_history_queries"
    private let videosKey = "search_recent_videos"

    static let trendingDefaults = [
        "podcast", "lofi", "jazz", "rock", "indie", "classical", "asmr", "ost",
    ]

    init() {
        recentQueries = UserDefaults.standard.stringArray(forKey: queriesKey) ?? []
        if let data = UserDefaults.standard.data(forKey: videosKey),
           let decoded = try? JSONDecoder().decode([PersistedVideo].self, from: data) {
            recentVideos = decoded.map(\.asVideoItem)
        }
    }

    func record(query: String, results: [VideoItem]) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        recentQueries = ([q] + recentQueries.filter { $0.caseInsensitiveCompare(q) != .orderedSame }).prefix(20).map { $0 }
        UserDefaults.standard.set(recentQueries, forKey: queriesKey)

        if let first = results.first {
            let persisted = PersistedVideo(from: first)
            let list = Array(
                ([persisted] + recentVideos.map(PersistedVideo.init).filter { $0.videoId != first.videoId }).prefix(12)
            )
            recentVideos = list.map(\.asVideoItem)
            if let data = try? JSONEncoder().encode(list) {
                UserDefaults.standard.set(data, forKey: videosKey)
            }
        }
    }

    func clearQueries() {
        recentQueries = []
        UserDefaults.standard.removeObject(forKey: queriesKey)
    }

    func clearRecentVideos() {
        recentVideos = []
        UserDefaults.standard.removeObject(forKey: videosKey)
    }

    func removeQuery(_ query: String) {
        recentQueries.removeAll { $0 == query }
        UserDefaults.standard.set(recentQueries, forKey: queriesKey)
    }
}

private struct PersistedVideo: Codable {
    let videoId: String
    let title: String
    let channelName: String
    let thumbnailURLString: String?
    let channelAvatarURLString: String?
    let durationText: String?
    let viewCountText: String?
    let publishedTimeText: String?

    init(from item: VideoItem) {
        videoId = item.videoId
        title = item.title
        channelName = item.channelName
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
            thumbnailURL: thumbnailURLString.flatMap(URL.init(string:)),
            channelAvatarURL: channelAvatarURLString.flatMap(URL.init(string:)),
            durationText: durationText,
            viewCountText: viewCountText,
            publishedTimeText: publishedTimeText
        )
    }
}
