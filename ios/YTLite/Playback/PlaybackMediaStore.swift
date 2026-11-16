import Foundation
import UIKit

private struct PlaybackStoreEntry: Codable, Equatable {
    let videoId: String
    let storeKey: String
    let itag: Int
    let relativePath: String
    let fileSize: Int64
    var storedAt: Date
    var lastPlayedAt: Date
}

/// Local cover JPEG kept next to kickoff-cached media (`{videoId}/cover.jpg`).
enum PlaybackCachedCover {
    static let fileName = "cover.jpg"

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(SaltedLiteral.playbackMediaFolder, isDirectory: true)
    }

    static func fileURL(videoId: String) -> URL {
        rootDirectory
            .appendingPathComponent(videoId, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// File URL when a cached cover exists (cache-busted for `RemoteImage`).
    static func resolveURL(videoId: String) -> URL? {
        guard !videoId.isEmpty else { return nil }
        let url = fileURL(videoId: videoId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return cacheBustedFileURL(url)
    }

    /// Prefer on-disk cover for media-cached tracks; otherwise keep the remote URL.
    static func resolvedThumbnail(videoId: String, remote: URL?) -> URL? {
        resolveURL(videoId: videoId) ?? remote
    }

    private static func cacheBustedFileURL(_ url: URL) -> URL {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)?
            .timeIntervalSince1970 ?? Date().timeIntervalSince1970
        let stamp = Int(mtime * 1000)
        return URL(string: "\(url.absoluteString)#v=\(stamp)") ?? url
    }
}

/// ***
actor PlaybackMediaStore {
    static let shared = PlaybackMediaStore()

    private let fileManager = FileManager.default
    private var index: [String: PlaybackStoreEntry] = [:]
    private var inflightVideoIds: Set<String> = []
    private var persistTasks: [String: Task<Void, Never>] = [:]
    private var loadedIndex = false

    /// Completed offline copies. Partial downloads are not included.
    func cachedSnapshots() -> [(videoId: String, fileSize: Int64)] {
        loadIndexIfNeeded()
        return index.values.map { ($0.videoId, $0.fileSize) }
    }

    func localFileURL(videoId: String) -> URL? {
        loadIndexIfNeeded()
        guard let entry = index[videoId] else { return nil }
        let url = rootDirectory.appendingPathComponent(entry.relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            index.removeValue(forKey: videoId)
            persistIndex()
            return nil
        }
        return url
    }

    func localCoverURL(videoId: String) -> URL? {
        PlaybackCachedCover.resolveURL(videoId: videoId)
    }

    func touchLastPlayed(videoId: String) {
        loadIndexIfNeeded()
        guard var entry = index[videoId] else { return }
        entry.lastPlayedAt = Date()
        index[videoId] = entry
        persistIndex()
    }

    func schedulePersist(
        videoId: String,
        sourceURL: URL,
        itag: Int,
        mimeType: String,
        thumbnailURL: URL? = nil
    ) async {
        loadIndexIfNeeded()
        if localFileURL(videoId: videoId) != nil {
            await persistCoverIfNeeded(videoId: videoId, thumbnailURL: thumbnailURL)
            return
        }
        guard !inflightVideoIds.contains(videoId) else { return }

        inflightVideoIds.insert(videoId)
        persistTasks[videoId]?.cancel()
        let task = Task {
            defer {
                Task { await self.clearInflight(videoId: videoId) }
            }
            do {
                try await self.fetchRemoteBytes(
                    videoId: videoId,
                    sourceURL: sourceURL,
                    itag: itag,
                    mimeType: mimeType
                )
                PlayProbe.log(SaltedLiteral.probeSaved, videoId: videoId, "itag=\(itag)")
                await self.persistCoverIfNeeded(videoId: videoId, thumbnailURL: thumbnailURL)
            } catch is CancellationError {
                PlayProbe.log(SaltedLiteral.probeCancelled, videoId: videoId)
            } catch {
                PlayProbe.log(
                    SaltedLiteral.probeFail,
                    videoId: videoId,
                    error.localizedDescription
                )
            }
        }
        persistTasks[videoId] = task
        await task.value
    }

    func cancelPersist(videoId: String) {
        persistTasks[videoId]?.cancel()
        persistTasks.removeValue(forKey: videoId)
        inflightVideoIds.remove(videoId)
    }

    /// ***
    func clearAll() {
        loadIndexIfNeeded()
        for videoId in Array(persistTasks.keys) {
            cancelPersist(videoId: videoId)
        }
        inflightVideoIds.removeAll()
        index.removeAll()
        if fileManager.fileExists(atPath: rootDirectory.path) {
            try? fileManager.removeItem(at: rootDirectory)
        }
        loadedIndex = false
    }

    /// ***
    func remove(videoId: String) {
        loadIndexIfNeeded()
        cancelPersist(videoId: videoId)
        if let entry = index.removeValue(forKey: videoId) {
            let fileURL = rootDirectory.appendingPathComponent(entry.relativePath)
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: fileURL.appendingPathExtension("partial"))
        }
        let videoDir = rootDirectory.appendingPathComponent(videoId, isDirectory: true)
        if fileManager.fileExists(atPath: videoDir.path) {
            try? fileManager.removeItem(at: videoDir)
        }
        persistIndex()
    }

    // MARK: - Private

    private var rootDirectory: URL {
        PlaybackCachedCover.rootDirectory
    }

    private var indexURL: URL {
        rootDirectory.appendingPathComponent(SaltedLiteral.indexFileName)
    }

    private func clearInflight(videoId: String) {
        inflightVideoIds.remove(videoId)
        persistTasks.removeValue(forKey: videoId)
    }

    private func loadIndexIfNeeded() {
        guard !loadedIndex else { return }
        loadedIndex = true
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([PlaybackStoreEntry].self, from: data)
        else { return }
        index = Dictionary(uniqueKeysWithValues: decoded.map { ($0.videoId, $0) })
        pruneMissingFiles()
    }

    private func persistIndex() {
        let entries = index.values.sorted { $0.videoId < $1.videoId }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func pruneMissingFiles() {
        var changed = false
        for (videoId, entry) in index {
            let url = rootDirectory.appendingPathComponent(entry.relativePath)
            if !fileManager.fileExists(atPath: url.path) {
                index.removeValue(forKey: videoId)
                changed = true
            }
        }
        if changed { persistIndex() }
    }

    private func destinationRelativePath(videoId: String, itag: Int, mimeType: String) -> String {
        let ext = PlaybackStorePolicy.fileExtension(for: mimeType)
        return "\(videoId)/\(itag).\(ext)"
    }

    private func fetchRemoteBytes(
        videoId: String,
        sourceURL: URL,
        itag: Int,
        mimeType: String
    ) async throws {
        let relativePath = destinationRelativePath(videoId: videoId, itag: itag, mimeType: mimeType)
        let destination = rootDirectory.appendingPathComponent(relativePath)
        let partial = destination.appendingPathExtension("partial")
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var request = URLRequest(url: sourceURL)
        request.httpMethod = "GET"
        for (key, value) in CatalogConstants.streamPlaybackHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var startByte: Int64 = 0
        if fileManager.fileExists(atPath: partial.path) {
            let attrs = try fileManager.attributesOfItem(atPath: partial.path)
            startByte = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            if startByte > 0 {
                request.setValue("bytes=\(startByte)-", forHTTPHeaderField: "Range")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard (200...299).contains(status) || status == 206 else {
            throw URLError(.badServerResponse)
        }

        if startByte > 0, status == 206 {
            if !fileManager.fileExists(atPath: partial.path) {
                fileManager.createFile(atPath: partial.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            if fileManager.fileExists(atPath: partial.path) {
                try fileManager.removeItem(at: partial)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try data.write(to: destination, options: .atomic)
            registerEntry(
                videoId: videoId,
                itag: itag,
                relativePath: relativePath,
                fileURL: destination
            )
            return
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: partial, to: destination)
        registerEntry(
            videoId: videoId,
            itag: itag,
            relativePath: relativePath,
            fileURL: destination
        )
    }

    /// Download remote artwork into `{videoId}/cover.jpg` once media is cached.
    private func persistCoverIfNeeded(videoId: String, thumbnailURL: URL?) async {
        let dest = PlaybackCachedCover.fileURL(videoId: videoId)
        if fileManager.fileExists(atPath: dest.path) { return }

        guard let thumbnailURL else { return }
        // Already a durable local file (import / custom thumb) — copy if needed.
        if thumbnailURL.isFileURL {
            let sourcePath = thumbnailURL.path
            guard fileManager.fileExists(atPath: sourcePath), sourcePath != dest.path else { return }
            try? fileManager.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.copyItem(at: URL(fileURLWithPath: sourcePath), to: dest)
            await invalidateCoverImageCache(at: dest)
            return
        }

        do {
            var request = URLRequest(url: thumbnailURL)
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            if let host = thumbnailURL.host,
               host.contains("ggpht.com") || host.contains("googleusercontent.com")
            {
                request.setValue(SaltedLiteral.refererSlash, forHTTPHeaderField: "Referer")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), !data.isEmpty else { return }

            try fileManager.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Normalize to JPEG so UIImage / RemoteImage always decode.
            let jpeg: Data
            if let image = UIImage(data: data), let encoded = image.jpegData(compressionQuality: 0.9) {
                jpeg = encoded
            } else {
                jpeg = data
            }
            try jpeg.write(to: dest, options: .atomic)
            await invalidateCoverImageCache(at: dest)
            PlayProbe.log("play.cover_saved", videoId: videoId)
        } catch is CancellationError {
            return
        } catch {
            PlayProbe.log("play.cover_fail", videoId: videoId, error.localizedDescription)
        }
    }

    private func invalidateCoverImageCache(at dest: URL) async {
        await MainActor.run {
            ImageStore.shared.invalidate(url: dest)
            if let busted = PlaybackCachedCover.resolveURL(
                videoId: dest.deletingLastPathComponent().lastPathComponent
            ) {
                ImageStore.shared.invalidate(url: busted)
            }
        }
    }

    private func registerEntry(
        videoId: String,
        itag: Int,
        relativePath: String,
        fileURL: URL
    ) {
        let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let now = Date()
        let entry = PlaybackStoreEntry(
            videoId: videoId,
            storeKey: PlaybackStorePolicy.storeKey(videoId: videoId, itag: itag),
            itag: itag,
            relativePath: relativePath,
            fileSize: size,
            storedAt: now,
            lastPlayedAt: now
        )
        index[videoId] = entry
        persistIndex()
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        let limit = PlaybackStorePolicy.maxStoreBytesForDevice
        var total = index.values.reduce(Int64(0)) { $0 + $1.fileSize }
        guard total > limit else { return }

        let sorted = index.values.sorted { $0.lastPlayedAt < $1.lastPlayedAt }
        for entry in sorted where total > limit {
            let videoDir = rootDirectory.appendingPathComponent(entry.videoId, isDirectory: true)
            if fileManager.fileExists(atPath: videoDir.path) {
                try? fileManager.removeItem(at: videoDir)
            } else {
                let url = rootDirectory.appendingPathComponent(entry.relativePath)
                try? fileManager.removeItem(at: url)
            }
            index.removeValue(forKey: entry.videoId)
            total -= entry.fileSize
            PlayProbe.log(SaltedLiteral.probeEvict, videoId: entry.videoId)
        }
        persistIndex()
    }
}
