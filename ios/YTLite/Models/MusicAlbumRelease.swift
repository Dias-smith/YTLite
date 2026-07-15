import Foundation

/// YouTube Music album / EP / single card from `FEmusic_new_releases_albums`.
struct MusicAlbumRelease: Identifiable, Hashable, Sendable {
    var id: String { browseId }
    let browseId: String
    let title: String
    let artistName: String
    let thumbnailURL: URL?
    let releaseType: String
    let playlistId: String?

    var isSingle: Bool {
        let lower = releaseType.lowercased()
        return lower == "single"
            || releaseType == "单曲"
            || releaseType == "シングル"
    }
}

/// Home feed row: playable track or album card (Android `HomeFeedItem` parity).
enum HomeFeedEntry: Identifiable, Hashable, Sendable {
    case track(VideoItem)
    case album(MusicAlbumRelease)

    var id: String {
        switch self {
        case .track(let video): return "t:\(video.videoId)"
        case .album(let album): return "a:\(album.browseId)"
        }
    }

    var asVideoItem: VideoItem? {
        if case .track(let video) = self { return video }
        return nil
    }
}
