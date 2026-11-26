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

#if DEBUG || targetEnvironment(macCatalyst)
/// Downloads a stream to disk and reports byte progress. The temp file must be moved
/// before `didFinishDownloadingTo` returns.
private final class PlaybackFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Result: Sendable {
        let fileURL: URL
        let statusCode: Int
    }

    private let startByte: Int64
    private let progressHandler: (@Sendable (Double) -> Void)?
    private let scratchURL: URL
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Result, Error>?
    private var movedURL: URL?
    private var moveError: Error?
    private var lastReported = -1.0
    private let fileManager = FileManager.default

    init(startByte: Int64, onProgress: (@Sendable (Double) -> Void)?) {
        self.startByte = startByte
        self.progressHandler = onProgress
        self.scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytlite-dl-\(UUID().uuidString)")
        super.init()
    }

    func download(_ request: URLRequest) async throws -> Result {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 20 * 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            let task = session.downloadTask(with: request)
            self.task = task
            task.resume()
        }
    }

    func cancel() {
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let fraction: Double
        if status == 206, startByte > 0 {
            fraction = Double(startByte + totalBytesWritten) / Double(startByte + totalBytesExpectedToWrite)
        } else {
            fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        }
        let clamped = min(0.99, max(0, fraction))
        guard abs(clamped - lastReported) >= 0.01 else { return }
        lastReported = clamped
        progressHandler?(clamped)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if fileManager.fileExists(atPath: scratchURL.path) {
                try fileManager.removeItem(at: scratchURL)
            }
            try fileManager.moveItem(at: location, to: scratchURL)
            movedURL = scratchURL
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return }
        if let error {
            try? fileManager.removeItem(at: scratchURL)
            continuation.resume(throwing: error)
            return
        }
        if let moveError {
            continuation.resume(throwing: moveError)
            return
        }
        guard let file = movedURL, let http = task.response as? HTTPURLResponse else {
            continuation.resume(throwing: URLError(.badServerResponse))
            return
        }
        continuation.resume(returning: Result(fileURL: file, statusCode: http.statusCode))
    }
}
#endif

/// ***
actor PlaybackMediaStore {
    static let shared = PlaybackMediaStore()

    private let fileManager = FileManager.default
    private var index: [String: PlaybackStoreEntry] = [:]
    private var inflightVideoIds: Set<String> = []
    private var persistTasks: [String: Task<Bool, Never>] = [:]
    private var loadedIndex = false

    /// Completed offline copies. Partial downloads are not included.
    func cachedSnapshots() -> [(videoId: String, fileSize: Int64)] {
        loadIndexIfNeeded()
        return index.values.map { ($0.videoId, $0.fileSize) }
    }

    #if DEBUG || targetEnvironment(macCatalyst)
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

    func touchLastPlayed(videoId: String) {
        loadIndexIfNeeded()
        guard var entry = index[videoId] else { return }
        entry.lastPlayedAt = Date()
        index[videoId] = entry
        persistIndex()
    }
    #endif

    func localCoverURL(videoId: String) -> URL? {
        PlaybackCachedCover.resolveURL(videoId: videoId)
    }

    #if DEBUG || targetEnvironment(macCatalyst)
    @discardableResult
    func schedulePersist(
        videoId: String,
        sourceURL: URL,
        itag: Int,
        mimeType: String,
        thumbnailURL: URL? = nil
    ) async -> Bool {
        loadIndexIfNeeded()
        if localFileURL(videoId: videoId) != nil {
            await persistCoverIfNeeded(videoId: videoId, thumbnailURL: thumbnailURL)
            return true
        }
        if inflightVideoIds.contains(videoId) {
            await persistTasks[videoId]?.value
            return localFileURL(videoId: videoId) != nil
        }

        inflightVideoIds.insert(videoId)
        persistTasks[videoId]?.cancel()
        let task = Task { () -> Bool in
            var saved = false
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
                saved = self.localFileURL(videoId: videoId) != nil
                PlayProbe.log(SaltedLiteral.probeSaved, videoId: videoId, "itag=\(itag)")
                await self.persistCoverIfNeeded(videoId: videoId, thumbnailURL: thumbnailURL)
            } catch is CancellationError {
                PlayProbe.log(SaltedLiteral.probeCancelled, videoId: videoId)
            } catch let error as URLError where error.code == .cancelled {
                PlayProbe.log(SaltedLiteral.probeCancelled, videoId: videoId)
            } catch {
                PlayProbe.log(
                    SaltedLiteral.probeFail,
                    videoId: videoId,
                    error.localizedDescription
                )
            }
            #if targetEnvironment(macCatalyst)
            if !saved {
                let id = videoId
                Task { @MainActor in
                    MacCachedMediaIndex.shared.clearFraction(videoId: id)
                }
            }
            #endif
            return saved
        }
        persistTasks[videoId] = task
        return await task.value
    }
    #endif

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
        #if targetEnvironment(macCatalyst)
        publishCachedIdsToUI(clearProgress: true)
        #endif
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
        #if targetEnvironment(macCatalyst)
        publishCachedIdsToUI()
        #endif
    }

    #if targetEnvironment(macCatalyst)
    func publishCachedIdsToUI(clearProgress: Bool = false) {
        let ids = Set(cachedSnapshots().map(\.videoId))
        Task { @MainActor in
            if clearProgress {
                MacCachedMediaIndex.shared.removeAll()
            } else {
                MacCachedMediaIndex.shared.replace(ids)
            }
        }
    }
    #endif

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

    #if DEBUG || targetEnvironment(macCatalyst)
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

        let downloader = PlaybackFileDownloader(startByte: startByte) { fraction in
            #if targetEnvironment(macCatalyst)
            let id = videoId
            Task { @MainActor in
                MacCachedMediaIndex.shared.setFraction(videoId: id, fraction)
            }
            #endif
        }
        let result = try await withTaskCancellationHandler {
            try await downloader.download(request)
        } onCancel: {
            downloader.cancel()
        }
        try Task.checkCancellation()

        let status = result.statusCode
        guard (200...299).contains(status) || status == 206 else {
            try? fileManager.removeItem(at: result.fileURL)
            throw URLError(.badServerResponse)
        }

        if startByte > 0, status == 206 {
            if !fileManager.fileExists(atPath: partial.path) {
                fileManager.createFile(atPath: partial.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }
            try handle.seekToEnd()
            let incoming = try FileHandle(forReadingFrom: result.fileURL)
            defer { try? incoming.close() }
            while let chunk = try incoming.read(upToCount: 256 * 1024), !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
            }
            try? fileManager.removeItem(at: result.fileURL)
        } else {
            try? fileManager.removeItem(at: partial)
            try moveReplacingItem(at: result.fileURL, to: destination)
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
        try moveReplacingItem(at: partial, to: destination)
        registerEntry(
            videoId: videoId,
            itag: itag,
            relativePath: relativePath,
            fileURL: destination
        )
    }

    private func moveReplacingItem(at source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            try fileManager.copyItem(at: source, to: destination)
            try? fileManager.removeItem(at: source)
        }
    }

    /// Download remote artwork into `{videoId}/cover.jpg` once media is cached.
    func ensureCover(videoId: String, thumbnailURL: URL?) async -> URL? {
        await persistCoverIfNeeded(videoId: videoId, thumbnailURL: thumbnailURL)
        let url = PlaybackCachedCover.fileURL(videoId: videoId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

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
    #endif
}
