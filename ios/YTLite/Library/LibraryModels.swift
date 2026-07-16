import Foundation
import SwiftData

/// Local catalogue row — mirrors Android `TrackEntity` / Supabase `tracks`.
/// Shared across owners (not bucketed).
@Model
final class LibraryTrack {
    @Attribute(.unique) var trackId: String
    var title: String
    var durationSeconds: Int
    var durationText: String?
    var thumbnailLow: String?
    var thumbnailMedium: String?
    var thumbnailHigh: String?
    var viewCount: Int64
    var viewCountText: String?
    var publishedText: String?
    var primaryArtistId: String?
    var primaryArtistName: String?
    var updatedAt: Date

    init(
        trackId: String,
        title: String,
        durationSeconds: Int = 0,
        durationText: String? = nil,
        thumbnailLow: String? = nil,
        thumbnailMedium: String? = nil,
        thumbnailHigh: String? = nil,
        viewCount: Int64 = 0,
        viewCountText: String? = nil,
        publishedText: String? = nil,
        primaryArtistId: String? = nil,
        primaryArtistName: String? = nil,
        updatedAt: Date = .now
    ) {
        self.trackId = trackId
        self.title = title
        self.durationSeconds = durationSeconds
        self.durationText = durationText
        self.thumbnailLow = thumbnailLow
        self.thumbnailMedium = thumbnailMedium
        self.thumbnailHigh = thumbnailHigh
        self.viewCount = viewCount
        self.viewCountText = viewCountText
        self.publishedText = publishedText
        self.primaryArtistId = primaryArtistId
        self.primaryArtistName = primaryArtistName
        self.updatedAt = updatedAt
    }

    var videoId: String { trackId }
    var channelName: String { primaryArtistName ?? "" }
    var thumbnailURLString: String? { thumbnailHigh ?? thumbnailMedium ?? thumbnailLow }

    var asVideoItem: VideoItem {
        VideoItem(
            videoId: trackId,
            title: title,
            channelName: channelName,
            subtitle: [channelName, viewCountText, publishedText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
            thumbnailURL: thumbnailURLString.flatMap(URL.init(string:)),
            durationText: durationText ?? DurationFormat.text(seconds: durationSeconds)
        )
    }
}

/// Mirrors Android `PlaylistEntity` — uniqueness is `(ownerKey, playlistId)` enforced in store.
@Model
final class LibraryPlaylist {
    /// Empty until first boot migration assigns guest/user.
    var ownerKey: String = ""
    var playlistId: String
    var name: String
    var coverUrlOrPath: String?
    var descriptionText: String?
    var systemType: String?
    var isPinned: Bool
    var isSynced: Bool
    var createdAt: Date?
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \LibraryPlaylistEntry.playlist)
    var entries: [LibraryPlaylistEntry]

    init(
        ownerKey: String,
        playlistId: String = UUID().uuidString,
        name: String,
        coverUrlOrPath: String? = nil,
        descriptionText: String? = nil,
        systemType: String? = nil,
        isPinned: Bool = false,
        isSynced: Bool = false,
        createdAt: Date? = .now,
        updatedAt: Date = .now,
        entries: [LibraryPlaylistEntry] = []
    ) {
        self.ownerKey = ownerKey
        self.playlistId = playlistId
        self.name = name
        self.coverUrlOrPath = coverUrlOrPath
        self.descriptionText = descriptionText
        self.systemType = systemType
        self.isPinned = isPinned
        self.isSynced = isSynced
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entries = entries
    }

    var trackCount: Int { entries.count }
    var sortCreatedAt: Date { createdAt ?? updatedAt }
}

@Model
final class LibraryPlaylistEntry {
    var position: Int
    var createdAt: Date
    var isSynced: Bool
    var track: LibraryTrack?
    var playlist: LibraryPlaylist?

    init(
        position: Int,
        track: LibraryTrack,
        createdAt: Date = .now,
        isSynced: Bool = false
    ) {
        self.position = position
        self.createdAt = createdAt
        self.isSynced = isSynced
        self.track = track
    }
}

@Model
final class PlaybackHistoryItem {
    @Attribute(.unique) var historyId: String
    var ownerKey: String = ""
    var trackId: String
    var playedAt: Date
    var progressMs: Int64
    var isSynced: Bool

    init(
        historyId: String = UUID().uuidString,
        ownerKey: String,
        trackId: String,
        playedAt: Date = .now,
        progressMs: Int64 = 0,
        isSynced: Bool = false
    ) {
        self.historyId = historyId
        self.ownerKey = ownerKey
        self.trackId = trackId
        self.playedAt = playedAt
        self.progressMs = progressMs
        self.isSynced = isSynced
    }
}

@Model
final class UserTrackLastPlayed {
    var ownerKey: String = ""
    var trackId: String
    var lastPlayedAt: Date
    var progressMs: Int64
    var isSynced: Bool

    init(
        ownerKey: String,
        trackId: String,
        lastPlayedAt: Date = .now,
        progressMs: Int64 = 0,
        isSynced: Bool = false
    ) {
        self.ownerKey = ownerKey
        self.trackId = trackId
        self.lastPlayedAt = lastPlayedAt
        self.progressMs = progressMs
        self.isSynced = isSynced
    }
}

@Model
final class UserTrackMetadata {
    var ownerKey: String = ""
    var trackId: String
    var customTitle: String?
    var customArtistName: String?
    var customThumbnailUrl: String?
    var customAlbum: String?
    var customYear: String?
    var updatedAt: Date
    var isSynced: Bool

    init(
        ownerKey: String,
        trackId: String,
        customTitle: String? = nil,
        customArtistName: String? = nil,
        customThumbnailUrl: String? = nil,
        customAlbum: String? = nil,
        customYear: String? = nil,
        updatedAt: Date = .now,
        isSynced: Bool = false
    ) {
        self.ownerKey = ownerKey
        self.trackId = trackId
        self.customTitle = customTitle
        self.customArtistName = customArtistName
        self.customThumbnailUrl = customThumbnailUrl
        self.customAlbum = customAlbum
        self.customYear = customYear
        self.updatedAt = updatedAt
        self.isSynced = isSynced
    }
}

@Model
final class UserSubscribedChannel {
    var ownerKey: String = ""
    var channelId: String
    var title: String
    var handle: String?
    var avatarUrl: String?
    var subscriberCountText: String?
    var descriptionText: String?
    var subscribedAt: Date
    var isSynced: Bool

    init(
        ownerKey: String,
        channelId: String,
        title: String,
        handle: String? = nil,
        avatarUrl: String? = nil,
        subscriberCountText: String? = nil,
        descriptionText: String? = nil,
        subscribedAt: Date = .now,
        isSynced: Bool = false
    ) {
        self.ownerKey = ownerKey
        self.channelId = channelId
        self.title = title
        self.handle = handle
        self.avatarUrl = avatarUrl
        self.subscriberCountText = subscriberCountText
        self.descriptionText = descriptionText
        self.subscribedAt = subscribedAt
        self.isSynced = isSynced
    }
}

@Model
final class NotInterestedItem {
    var ownerKey: String = ""
    var videoId: String
    var createdAt: Date

    init(ownerKey: String, videoId: String, createdAt: Date = .now) {
        self.ownerKey = ownerKey
        self.videoId = videoId
        self.createdAt = createdAt
    }
}

enum SystemPlaylistType {
    static let favorites = "favorites"
    static let watchLater = "watch_later"
}

typealias PlayHistoryItem = PlaybackHistoryItem
