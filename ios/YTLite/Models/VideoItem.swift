import Foundation

struct VideoItem: Identifiable, Hashable, Sendable {
    var id: String { videoId }
    let videoId: String
    let title: String
    let channelName: String
    let subtitle: String
    let thumbnailURL: URL?
    let durationText: String?

    init(
        videoId: String,
        title: String,
        channelName: String,
        subtitle: String = "",
        thumbnailURL: URL? = nil,
        durationText: String? = nil
    ) {
        self.videoId = videoId
        self.title = title
        self.channelName = channelName
        self.subtitle = subtitle.isEmpty ? channelName : subtitle
        self.thumbnailURL = thumbnailURL
            ?? URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
        self.durationText = durationText
    }

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }
}

typealias SearchVideoItem = VideoItem
