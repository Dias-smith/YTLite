import Foundation

struct VideoItem: Identifiable, Hashable, Sendable {
    var id: String { videoId }
    let videoId: String
    let title: String
    let channelName: String
    let subtitle: String
    let thumbnailURL: URL?

    init(
        videoId: String,
        title: String,
        channelName: String,
        subtitle: String = "",
        thumbnailURL: URL? = nil
    ) {
        self.videoId = videoId
        self.title = title
        self.channelName = channelName
        self.subtitle = subtitle.isEmpty ? channelName : subtitle
        self.thumbnailURL = thumbnailURL
            ?? URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
    }

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }
}

typealias SearchVideoItem = VideoItem
