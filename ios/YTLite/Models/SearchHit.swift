import Foundation

enum SearchResultTab: String, CaseIterable, Identifiable {
    case all
    case videos
    case channels
    case playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("search.tab.all")
        case .videos: return L("search.tab.videos")
        case .channels: return L("search.tab.channels")
        case .playlists: return L("search.tab.playlists")
        }
    }

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
