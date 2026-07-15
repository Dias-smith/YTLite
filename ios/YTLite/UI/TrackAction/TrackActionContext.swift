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

    init(
        videoId: String,
        title: String,
        channelName: String,
        thumbnailURL: URL? = nil,
        durationText: String? = nil,
        playlistId: String? = nil,
        canRemoveFromPlaylist: Bool = false
    ) {
        self.videoId = videoId
        self.title = title
        self.channelName = channelName
        self.thumbnailURL = thumbnailURL
        self.durationText = durationText
        self.playlistId = playlistId
        self.canRemoveFromPlaylist = canRemoveFromPlaylist
    }

    init(
        item: VideoItem,
        playlistId: String? = nil,
        canRemoveFromPlaylist: Bool = false
    ) {
        self.init(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURL: item.thumbnailURL,
            durationText: item.durationText,
            playlistId: playlistId,
            canRemoveFromPlaylist: canRemoveFromPlaylist
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
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }
}
