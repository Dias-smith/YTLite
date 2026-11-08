import Foundation

/// Context for the track rich menu — mirrors Android `TrackActionContext`.
struct TrackActionContext: Identifiable, Equatable, Sendable {
    var id: String { videoId }

    let videoId: String
    let title: String
    let channelName: String
    let thumbnailURL: URL?
    let durationText: String?
    /// When set and `canRemoveFromPlaylist` is true, show Remove from playlist.
    let playlistId: String?
    let canRemoveFromPlaylist: Bool
    /// When true, show Remove from Up next / queue.
    let canRemoveFromQueue: Bool
    /// When true (Library Songs), show Delete from library.
    let canDeleteFromLibrary: Bool
    /// When true (History detail), show Remove from history.
    let canRemoveFromHistory: Bool

    init(
        videoId: String,
        title: String,
        channelName: String,
        thumbnailURL: URL? = nil,
        durationText: String? = nil,
        playlistId: String? = nil,
        canRemoveFromPlaylist: Bool = false,
        canRemoveFromQueue: Bool = false,
        canDeleteFromLibrary: Bool = false,
        canRemoveFromHistory: Bool = false
    ) {
        self.videoId = videoId
        self.title = title
        self.channelName = channelName
        self.thumbnailURL = thumbnailURL
        self.durationText = durationText
        self.playlistId = playlistId
        self.canRemoveFromPlaylist = canRemoveFromPlaylist
        self.canRemoveFromQueue = canRemoveFromQueue
        self.canDeleteFromLibrary = canDeleteFromLibrary
        self.canRemoveFromHistory = canRemoveFromHistory
    }

    init(
        item: VideoItem,
        playlistId: String? = nil,
        canRemoveFromPlaylist: Bool = false,
        canRemoveFromQueue: Bool = false,
        canDeleteFromLibrary: Bool = false,
        canRemoveFromHistory: Bool = false
    ) {
        self.init(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURL: item.thumbnailURL,
            durationText: item.durationText,
            playlistId: playlistId,
            canRemoveFromPlaylist: canRemoveFromPlaylist,
            canRemoveFromQueue: canRemoveFromQueue,
            canDeleteFromLibrary: canDeleteFromLibrary,
            canRemoveFromHistory: canRemoveFromHistory
        )
    }

    var asVideoItem: VideoItem {
        VideoItem(
            videoId: videoId,
            title: title,
            channelName: channelName,
            thumbnailURL: thumbnailURL,
            durationText: durationText
        )
    }

    var watchURL: URL {
        URL(string: CatalogURL.watchURL(videoId: videoId))!
    }
}
