import Foundation

/// Persisted playback queue — mirrors Android `PlaybackSessionSnapshot`.
struct PlaybackSessionSnapshot: Codable, Equatable {
    var items: [PersistedQueueItem]
    var currentIndex: Int
    var sourcePlaylistId: String?
    var positionSeconds: Double
    var durationSeconds: Double
    var channelId: String?
    var channelAvatarURL: String?
    var repeatMode: QueueRepeatMode
    var shuffleEnabled: Bool
    var originalOrder: [PersistedQueueItem]?

    enum CodingKeys: String, CodingKey {
        case items, currentIndex, sourcePlaylistId, positionSeconds, durationSeconds
        case channelId, channelAvatarURL, repeatMode, shuffleEnabled, originalOrder
    }

    init(
        items: [PersistedQueueItem],
        currentIndex: Int,
        sourcePlaylistId: String? = nil,
        positionSeconds: Double = 0,
        durationSeconds: Double = 0,
        channelId: String? = nil,
        channelAvatarURL: String? = nil,
        repeatMode: QueueRepeatMode = .off,
        shuffleEnabled: Bool = false,
        originalOrder: [PersistedQueueItem]? = nil
    ) {
        self.items = items
        self.currentIndex = currentIndex
        self.sourcePlaylistId = sourcePlaylistId
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.channelId = channelId
        self.channelAvatarURL = channelAvatarURL
        self.repeatMode = repeatMode
        self.shuffleEnabled = shuffleEnabled
        self.originalOrder = originalOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([PersistedQueueItem].self, forKey: .items)
        currentIndex = try c.decode(Int.self, forKey: .currentIndex)
        sourcePlaylistId = try c.decodeIfPresent(String.self, forKey: .sourcePlaylistId)
        positionSeconds = try c.decodeIfPresent(Double.self, forKey: .positionSeconds) ?? 0
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        channelAvatarURL = try c.decodeIfPresent(String.self, forKey: .channelAvatarURL)
        if let raw = try c.decodeIfPresent(String.self, forKey: .repeatMode),
           let mode = QueueRepeatMode(rawValue: raw)
        {
            repeatMode = mode
        } else if let mode = try c.decodeIfPresent(QueueRepeatMode.self, forKey: .repeatMode) {
            repeatMode = mode
        } else {
            repeatMode = .off
        }
        shuffleEnabled = try c.decodeIfPresent(Bool.self, forKey: .shuffleEnabled) ?? false
        originalOrder = try c.decodeIfPresent([PersistedQueueItem].self, forKey: .originalOrder)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encode(currentIndex, forKey: .currentIndex)
        try c.encodeIfPresent(sourcePlaylistId, forKey: .sourcePlaylistId)
        try c.encode(positionSeconds, forKey: .positionSeconds)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encodeIfPresent(channelId, forKey: .channelId)
        try c.encodeIfPresent(channelAvatarURL, forKey: .channelAvatarURL)
        try c.encode(repeatMode.rawValue, forKey: .repeatMode)
        try c.encode(shuffleEnabled, forKey: .shuffleEnabled)
        try c.encodeIfPresent(originalOrder, forKey: .originalOrder)
    }
}

struct PersistedQueueItem: Codable, Equatable {
    var videoId: String
    var title: String
    var channelName: String
    var thumbnailURL: String?
    var durationText: String?

    static func from(_ item: VideoItem) -> PersistedQueueItem {
        PersistedQueueItem(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURL: item.thumbnailURL?.absoluteString,
            durationText: item.durationText
        )
    }

    func toVideoItem() -> VideoItem {
        VideoItem(
            videoId: videoId,
            title: title,
            channelName: channelName,
            thumbnailURL: thumbnailURL.flatMap(URL.init(string:)),
            durationText: durationText
        )
    }
}

enum PlaybackSessionStore {
    private static let key = "playback_session_v1"

    static func load() -> PlaybackSessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PlaybackSessionSnapshot.self, from: data)
    }

    static func save(_ snapshot: PlaybackSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
