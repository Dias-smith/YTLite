import Foundation
import CryptoKit

/// Sandboxed storage for imported audio under Application Support/ImportMedia.
@MainActor
final class LocalMediaStore {
    static let shared = LocalMediaStore()

    private let fm = FileManager.default
    private let root: URL

    private init() {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        root = base.appendingPathComponent("ImportMedia", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var rootURL: URL { root }

    func directory(for trackId: String) -> URL {
        root.appendingPathComponent(trackId, isDirectory: true)
    }

    func audioURL(trackId: String, relativePath: String?) -> URL? {
        if let relativePath, !relativePath.isEmpty {
            let url = root.appendingPathComponent(relativePath)
            return fm.fileExists(atPath: url.path) ? url : nil
        }
        let dir = directory(for: trackId)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        return files.first { file in
            let name = file.lastPathComponent.lowercased()
            return name.hasPrefix("audio.") || Self.audioExtensions.contains(file.pathExtension.lowercased())
        }
    }

    /// Copies `source` into `{trackId}/audio.{ext}` and returns the relative path + content hash.
    @discardableResult
    func ingestCopy(
        from source: URL,
        trackId: String,
        preferredExtension: String? = nil
    ) throws -> (relativePath: String, contentHash: String, byteCount: Int64) {
        let dir = directory(for: trackId)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = (preferredExtension ?? source.pathExtension).lowercased()
        let safeExt = ext.isEmpty ? "bin" : ext
        let dest = dir.appendingPathComponent("audio.\(safeExt)")
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.stopAccessingSecurityScopedResource() }
        }
        try fm.copyItem(at: source, to: dest)
        let data = try Data(contentsOf: dest, options: [.mappedIfSafe])
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let rel = "\(trackId)/audio.\(safeExt)"
        let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? Int64(data.count)
        return (rel, hash, size)
    }

    /// Writes raw bytes (Wi‑Fi / cloud download) into the track folder.
    func ingestData(
        _ data: Data,
        trackId: String,
        fileExtension: String
    ) throws -> (relativePath: String, contentHash: String, byteCount: Int64) {
        let dir = directory(for: trackId)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeExt = fileExtension.isEmpty ? "bin" : fileExtension.lowercased()
        let dest = dir.appendingPathComponent("audio.\(safeExt)")
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try data.write(to: dest, options: .atomic)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ("\(trackId)/audio.\(safeExt)", hash, Int64(data.count))
    }

    func remove(trackId: String) {
        let dir = directory(for: trackId)
        try? fm.removeItem(at: dir)
    }

    func totalByteCount() -> Int64 {
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }

    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "caf", "ogg", "opus", "mp4", "mov", "m4v"
    ]
}
