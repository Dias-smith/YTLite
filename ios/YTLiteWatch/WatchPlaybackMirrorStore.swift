import Foundation

/// Persists last Now Playing so the Watch home screen can paint immediately on launch.
enum WatchPlaybackMirrorStore {
    private static let fileName = "watch_playback_mirror.json"

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(fileName)
    }

    static func save(_ snapshot: WatchConnectivityProtocol.PlaybackSnapshot) {
        guard let videoId = snapshot.videoId, !videoId.isEmpty else {
            clear()
            return
        }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Best-effort.
        }
    }

    static func load() -> WatchConnectivityProtocol.PlaybackSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WatchConnectivityProtocol.PlaybackSnapshot.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
