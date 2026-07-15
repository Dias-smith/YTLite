import Foundation
import SwiftData

/// Local catalogue row — mirrors Android `TrackEntity` / Supabase `tracks`.
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

    /// Compatibility aliases used across UI / playback.
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

/// Mirrors Android `PlaylistEntity` sync fields / Supabase `playlists`.
@Model
final class LibraryPlaylist {
    @Attribute(.unique) var playlistId: String
    var name: String
    var coverUrlOrPath: String?
    var descriptionText: String?
    var systemType: String?
    var isPinned: Bool
    var isSynced: Bool
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \LibraryPlaylistEntry.playlist)
    var entries: [LibraryPlaylistEntry]

    init(
        playlistId: String = UUID().uuidString,
        name: String,
        coverUrlOrPath: String? = nil,
        descriptionText: String? = nil,
        systemType: String? = nil,
        isPinned: Bool = false,
        isSynced: Bool = false,
        updatedAt: Date = .now,
        entries: [LibraryPlaylistEntry] = []
    ) {
        self.playlistId = playlistId
        self.name = name
        self.coverUrlOrPath = coverUrlOrPath
        self.descriptionText = descriptionText
        self.systemType = systemType
        self.isPinned = isPinned
        self.isSynced = isSynced
        self.updatedAt = updatedAt
        self.entries = entries
    }

    var trackCount: Int { entries.count }
}

/// Mirrors Android `PlaylistTrackEntity` / Supabase `playlist_track_cross_ref`.
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

/// Mirrors Android `PlaybackHistoryEntity` / Supabase `playback_history`.
/// Display metadata lives on `LibraryTrack`, not denormalized here.
@Model
final class PlaybackHistoryItem {
    @Attribute(.unique) var historyId: String
    var trackId: String
    var playedAt: Date
    var progressMs: Int64
    var isSynced: Bool

    init(
        historyId: String = UUID().uuidString,
        trackId: String,
        playedAt: Date = .now,
        progressMs: Int64 = 0,
        isSynced: Bool = false
    ) {
        self.historyId = historyId
        self.trackId = trackId
        self.playedAt = playedAt
        self.progressMs = progressMs
        self.isSynced = isSynced
    }
}

/// Mirrors Android `UserTrackLastPlayedEntity` / Supabase `user_track_last_played`.
@Model
final class UserTrackLastPlayed {
    @Attribute(.unique) var trackId: String
    var lastPlayedAt: Date
    var progressMs: Int64
    var isSynced: Bool

    init(
        trackId: String,
        lastPlayedAt: Date = .now,
        progressMs: Int64 = 0,
        isSynced: Bool = false
    ) {
        self.trackId = trackId
        self.lastPlayedAt = lastPlayedAt
        self.progressMs = progressMs
        self.isSynced = isSynced
    }
}

/// Mirrors Android `UserTrackMetadataEntity` / Supabase `user_track_metadata`.
@Model
final class UserTrackMetadata {
    @Attribute(.unique) var trackId: String
    var customTitle: String?
    var customArtistName: String?
    var customThumbnailUrl: String?
    var customAlbum: String?
    var customYear: String?
    var updatedAt: Date
    var isSynced: Bool

    init(
        trackId: String,
        customTitle: String? = nil,
        customArtistName: String? = nil,
        customThumbnailUrl: String? = nil,
        customAlbum: String? = nil,
        customYear: String? = nil,
        updatedAt: Date = .now,
        isSynced: Bool = false
    ) {
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

/// Mirrors Android `UserSubscribedChannelEntity` / Supabase `user_subscribed_channels`.
@Model
final class UserSubscribedChannel {
    @Attribute(.unique) var channelId: String
    var title: String
    var handle: String?
    var avatarUrl: String?
    var subscriberCountText: String?
    var descriptionText: String?
    var subscribedAt: Date
    var isSynced: Bool

    init(
        channelId: String,
        title: String,
        handle: String? = nil,
        avatarUrl: String? = nil,
        subscriberCountText: String? = nil,
        descriptionText: String? = nil,
        subscribedAt: Date = .now,
        isSynced: Bool = false
    ) {
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

/// Local-only hide list — mirrors Android `NotInterestedEntity` (not synced).
@Model
final class NotInterestedItem {
    @Attribute(.unique) var videoId: String
    var createdAt: Date

    init(videoId: String, createdAt: Date = .now) {
        self.videoId = videoId
        self.createdAt = createdAt
    }
}

enum SystemPlaylistType {
    static let favorites = "favorites"
    static let watchLater = "watch_later"
}

/// Backward-compatible name used by older call sites.
typealias PlayHistoryItem = PlaybackHistoryItem
