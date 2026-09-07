import Foundation

/// Shared Watch ↔ iPhone message envelope for Mixtube companion MVP.
/// Wire format may evolve; keep Codable and backward-compatible raw values.
enum WatchConnectivityProtocol {
    static let suiteName = "YTLiteWatchConnectivity"
    static let protocolVersion = 1

    // MARK: - Envelope

    struct Envelope: Codable, Sendable, Equatable {
        var version: Int
        var id: String
        var kind: Kind
        var payload: Data?

        init(kind: Kind, payload: Data? = nil, id: String = UUID().uuidString, version: Int = WatchConnectivityProtocol.protocolVersion) {
            self.version = version
            self.id = id
            self.kind = kind
            self.payload = payload
        }

        func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
            guard let payload else {
                throw ProtocolError.missingPayload
            }
            return try JSONDecoder().decode(type, from: payload)
        }

        static func make<T: Encodable>(kind: Kind, body: T) throws -> Envelope {
            let data = try JSONEncoder().encode(body)
            return Envelope(kind: kind, payload: data)
        }
    }

    enum Kind: String, Codable, Sendable {
        // Watch → iPhone
        case syncRequestSnapshot = "sync.requestSnapshot"
        case transportPlayPause = "transport.playPause"
        case transportNext = "transport.next"
        case transportPrevious = "transport.previous"
        case transportSeek = "transport.seek"
        case transportSetShuffle = "transport.setShuffle"
        case transportCycleRepeat = "transport.cycleRepeat"
        case transportSetSpeed = "transport.setSpeed"
        case transportSetVolume = "transport.setVolume"
        case queuePlayIndex = "queue.play"
        case queueRemove = "queue.remove"
        case queuePlayNext = "queue.playNext"
        case queueAppend = "queue.append"
        case libraryLike = "library.like"
        case libraryUnlike = "library.unlike"
        case libraryAddToPlaylist = "library.addToPlaylist"
        case libraryRemoveFromPlaylist = "library.removeFromPlaylist"
        case libraryCreatePlaylist = "library.createPlaylist"
        case libraryRenamePlaylist = "library.renamePlaylist"
        case libraryDeletePlaylist = "library.deletePlaylist"
        case libraryEditTrackMetadata = "library.editTrackMetadata"
        case libraryRemoveFromHistory = "library.removeFromHistory"
        case libraryNotInterested = "library.notInterested"
        case libraryPlayPlaylist = "library.playPlaylist"
        case libraryPlayHistory = "library.playHistory"
        case libraryShufflePlay = "library.shufflePlay"
        case librarySetPinned = "library.setPinned"
        case libraryQueuePlayNext = "library.queuePlayNext"
        case libraryQueueAppend = "library.queueAppend"
        case sharePresent = "share.present"

        // iPhone → Watch
        case playbackSnapshot = "playback.snapshot"
        case queueSnapshot = "queue.snapshot"
        case librarySnapshot = "library.snapshot"
        case libraryDelta = "library.delta"
        case authSnapshot = "auth.snapshot"
        case hostUnavailable = "host.unavailable"
        case shareResult = "share.result"
        case ack = "ack"
        case error = "error"
    }

    enum ProtocolError: Error {
        case missingPayload
        case unsupportedVersion(Int)
    }

    // MARK: - Common payloads (Phase 1 stubs; expanded in later phases)

    struct EmptyBody: Codable, Sendable, Equatable {}

    struct SeekBody: Codable, Sendable, Equatable {
        var position: Double
    }

    struct BoolBody: Codable, Sendable, Equatable {
        var value: Bool
    }

    struct SpeedBody: Codable, Sendable, Equatable {
        var speed: Float
    }

    struct VolumeBody: Codable, Sendable, Equatable {
        /// iPhone system output volume, 0…1.
        var volume: Float
    }

    struct IndexBody: Codable, Sendable, Equatable {
        var index: Int
    }

    struct VideoIdBody: Codable, Sendable, Equatable {
        var videoId: String
    }

    struct IdsBody: Codable, Sendable, Equatable {
        var ids: [String]
    }

    struct AuthSnapshot: Codable, Sendable, Equatable {
        var isGuest: Bool
        var displayName: String?
    }

    struct PlaybackSnapshot: Codable, Sendable, Equatable {
        var videoId: String?
        var title: String?
        var artist: String?
        var thumbnailURL: String?
        var position: Double
        var duration: Double?
        var isPlaying: Bool
        var shuffleEnabled: Bool
        var repeatMode: String
        var speed: Float
        var isExtracting: Bool
        var isSeekable: Bool
        var errorMessage: String?
        /// iPhone system output volume 0…1 (Watch can set via `transport.setVolume`).
        var outputVolume: Float?

        /// Speeds accepted by iPhone `PlaybackController.speedOptions`.
        static let speedOptions: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 5, 8]
    }

    struct QueueTrackDTO: Codable, Sendable, Equatable, Identifiable {
        var id: String { videoId }
        var videoId: String
        var title: String
        var artist: String
        var thumbnailURL: String?
        var durationText: String?
        var isLive: Bool
    }

    struct QueueSnapshot: Codable, Sendable, Equatable {
        var currentIndex: Int
        var items: [QueueTrackDTO]
    }

    struct LibraryTrackDTO: Codable, Sendable, Equatable, Identifiable {
        var id: String { videoId }
        var videoId: String
        var title: String
        var artist: String
        var thumbnailURL: String?
        var durationText: String?
    }

    struct LibraryPlaylistDTO: Codable, Sendable, Equatable, Identifiable {
        var id: String { playlistId }
        var playlistId: String
        var name: String
        var coverURL: String?
        var systemType: String?
        var trackCount: Int
        var canEdit: Bool
        var isPinned: Bool
        var tracks: [LibraryTrackDTO]
    }

    struct LibrarySnapshot: Codable, Sendable, Equatable {
        var playlists: [LibraryPlaylistDTO]
        var history: [LibraryTrackDTO]
        /// Favorite ids (may exceed tracks embedded in the favorites playlist DTO).
        var favoriteVideoIds: [String]
        var authIsGuest: Bool
        var authDisplayName: String?
        var updatedAt: TimeInterval
    }

    struct PlayPlaylistBody: Codable, Sendable, Equatable {
        var playlistId: String
        var index: Int
    }

    struct PlaylistIdBody: Codable, Sendable, Equatable {
        var playlistId: String
    }

    struct RenamePlaylistBody: Codable, Sendable, Equatable {
        var playlistId: String
        var name: String
    }

    struct CreatePlaylistBody: Codable, Sendable, Equatable {
        var name: String
    }

    struct AddToPlaylistBody: Codable, Sendable, Equatable {
        var videoId: String
        var playlistId: String
    }

    struct RemoveFromPlaylistBody: Codable, Sendable, Equatable {
        var videoId: String
        var playlistId: String
    }

    struct SetPinnedBody: Codable, Sendable, Equatable {
        var playlistId: String
        var pinned: Bool
    }

    struct EditMetadataBody: Codable, Sendable, Equatable {
        var videoId: String
        var title: String?
        var artist: String?
        var album: String?
        var year: String?
        var thumbnailURL: String?
    }

    struct ShareResultBody: Codable, Sendable, Equatable {
        var requestId: String?
        var ok: Bool
        var message: String?
    }

    struct HostUnavailable: Codable, Sendable, Equatable {
        var reason: String
    }

    struct AckBody: Codable, Sendable, Equatable {
        var requestId: String
        var ok: Bool
        var message: String?
    }

    struct ErrorBody: Codable, Sendable, Equatable {
        var requestId: String?
        var code: String
        var message: String
    }
}
