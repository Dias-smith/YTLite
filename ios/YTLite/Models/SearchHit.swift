import Foundation

enum SearchResultTab: String, CaseIterable, Identifiable {
    case all = "All"
    case videos = "Videos"
    case channels = "Channels"
    case playlists = "Playlists"

    var id: String { rawValue }

    /// InnerTube search `params`. `nil` = mixed / All.
    var innerTubeParams: String? {
        switch self {
        case .all: return nil
        case .videos: return "EgIQAQ%3D%3D"
        case .channels: return "EgIQAg%3D%3D"
        case .playlists: return "EgIQAw%3D%3D"
        }
    }
}

enum SearchHit: Identifiable, Hashable, Sendable {
    case video(VideoItem)
    case channel(ChannelItem)
    case playlist(PlaylistPreview)

    var id: String {
        switch self {
        case .video(let v): return "v:\(v.videoId)"
        case .channel(let c): return "c:\(c.channelId)"
        case .playlist(let p): return "p:\(p.playlistId)"
        }
    }

    var asVideoItem: VideoItem? {
        if case .video(let v) = self { return v }
        return nil
    }
}
