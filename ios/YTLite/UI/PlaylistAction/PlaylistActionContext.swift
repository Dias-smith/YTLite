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
    /// Virtual Imported row (no `LibraryPlaylist` entity in the Playlists list).
    let isImported: Bool

    enum CoverKind: Hashable, Sendable {
        case liked
        case watchLater
        case history
        case imported
        case custom
    }

    var canEdit: Bool { !isHistory && !isImported && systemType == nil }
    var canDelete: Bool { canEdit }

    static func from(playlist: LibraryPlaylist, title: String, coverKind: CoverKind) -> PlaylistActionContext {
        PlaylistActionContext(
            playlistId: playlist.playlistId,
            title: title,
            coverURL: playlist.coverUrlOrPath.flatMap(URL.init(string:)),
            coverKind: coverKind,
            systemType: playlist.systemType,
            isHistory: false,
            isImported: false
        )
    }

    static func history(songCountIgnored _: Int = 0) -> PlaylistActionContext {
        PlaylistActionContext(
            playlistId: "system:history",
            title: L("library.history"),
            coverURL: nil,
            coverKind: .history,
            systemType: "history",
            isHistory: true,
            isImported: false
        )
    }

    static func imported(songCountIgnored _: Int = 0) -> PlaylistActionContext {
        PlaylistActionContext(
            playlistId: "system:imported",
            title: L("import.list.title"),
            coverURL: nil,
            coverKind: .imported,
            systemType: SystemPlaylistType.imported,
            isHistory: false,
            isImported: true
        )
    }
}
