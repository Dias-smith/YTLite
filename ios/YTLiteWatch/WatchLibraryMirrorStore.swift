import Foundation

/// Persists the last successful library mirror for disconnected browse on Watch.
enum WatchLibraryMirrorStore {
    private static let fileName = "watch_library_mirror.json"

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(fileName)
    }

    static func save(_ snapshot: WatchConnectivityProtocol.LibrarySnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Best-effort cache.
        }
    }

    static func load() -> WatchConnectivityProtocol.LibrarySnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WatchConnectivityProtocol.LibrarySnapshot.self, from: data)
    }
}
