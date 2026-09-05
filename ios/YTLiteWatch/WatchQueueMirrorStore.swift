import Foundation

/// Persists last queue snapshot for disconnected readonly browse.
enum WatchQueueMirrorStore {
    private static let fileName = "watch_queue_mirror.json"

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(fileName)
    }

    static func save(_ snapshot: WatchConnectivityProtocol.QueueSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Best-effort.
        }
    }

    static func load() -> WatchConnectivityProtocol.QueueSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WatchConnectivityProtocol.QueueSnapshot.self, from: data)
    }
}
