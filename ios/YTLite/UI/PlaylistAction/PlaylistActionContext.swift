import Foundation

/// Context for the playlist rich menu — mirrors Android `PlaylistActionContext`.
struct PlaylistActionContext: Identifiable, Hashable, Sendable {
    var id: String { playlistId }
    let playlistId: String
    let title: String
    let coverURL: URL?
    let coverKind: CoverKind
    let systemType: String?
    /// Virtual History row (no `LibraryPlaylist` entity).
    let isHistory: Bool

    enum CoverKind: Hashable, Sendable {
        case liked
        case watchLater
        case history
        case custom
    }

    var canEdit: Bool { !isHistory && systemType == nil }
    var canDelete: Bool { canEdit }

    static func from(playlist: LibraryPlaylist, title: String, coverKind: CoverKind) -> PlaylistActionContext {
        PlaylistActionContext(
            playlistId: playlist.playlistId,
            title: title,
            coverURL: playlist.coverUrlOrPath.flatMap(URL.init(string:)),
            coverKind: coverKind,
            systemType: playlist.systemType,
            isHistory: false
        )
    }

    static func history(songCountIgnored _: Int = 0) -> PlaylistActionContext {
        PlaylistActionContext(
            playlistId: "system:history",
            title: L("library.history"),
            coverURL: nil,
            coverKind: .history,
            systemType: "history",
            isHistory: true
        )
    }
}
