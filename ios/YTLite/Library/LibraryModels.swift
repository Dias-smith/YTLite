import Foundation
import SwiftData

@Model
final class LibraryTrack {
    @Attribute(.unique) var videoId: String
    var title: String
    var channelName: String
    var thumbnailURLString: String?
    var durationSeconds: Int
    var updatedAt: Date

    init(
        videoId: String,
        title: String,
        channelName: String,
        thumbnailURLString: String? = nil,
        durationSeconds: Int = 0,
        updatedAt: Date = .now
    ) {
        self.videoId = videoId
        self.title = title
        self.channelName = channelName
        self.thumbnailURLString = thumbnailURLString
        self.durationSeconds = durationSeconds
        self.updatedAt = updatedAt
    }

    var asVideoItem: VideoItem {
        VideoItem(
            videoId: videoId,
            title: title,
            channelName: channelName,
            thumbnailURL: thumbnailURLString.flatMap(URL.init(string:))
        )
    }
}

@Model
final class LibraryPlaylist {
    @Attribute(.unique) var playlistId: String
    var name: String
    var systemType: String?
    var isPinned: Bool
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \LibraryPlaylistEntry.playlist)
    var entries: [LibraryPlaylistEntry]

    init(
        playlistId: String = UUID().uuidString,
        name: String,
        systemType: String? = nil,
        isPinned: Bool = false,
        updatedAt: Date = .now,
        entries: [LibraryPlaylistEntry] = []
    ) {
        self.playlistId = playlistId
        self.name = name
        self.systemType = systemType
        self.isPinned = isPinned
        self.updatedAt = updatedAt
        self.entries = entries
    }

    var trackCount: Int { entries.count }
}

@Model
final class LibraryPlaylistEntry {
    var position: Int
    var createdAt: Date
    var track: LibraryTrack?
    var playlist: LibraryPlaylist?

    init(position: Int, track: LibraryTrack, createdAt: Date = .now) {
        self.position = position
        self.createdAt = createdAt
        self.track = track
    }
}

@Model
final class PlayHistoryItem {
    var videoId: String
    var title: String
    var channelName: String
    var thumbnailURLString: String?
    var playedAt: Date

    init(
        videoId: String,
        title: String,
        channelName: String,
        thumbnailURLString: String? = nil,
        playedAt: Date = .now
    ) {
        self.videoId = videoId
        self.title = title
        self.channelName = channelName
        self.thumbnailURLString = thumbnailURLString
        self.playedAt = playedAt
    }

    var asVideoItem: VideoItem {
        VideoItem(
            videoId: videoId,
            title: title,
            channelName: channelName,
            thumbnailURL: thumbnailURLString.flatMap(URL.init(string:))
        )
    }
}

enum SystemPlaylistType {
    static let favorites = "favorites"
    static let watchLater = "watch_later"
}
