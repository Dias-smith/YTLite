import Foundation

private struct PlaybackStoreEntry: Codable, Equatable {
    let videoId: String
    let storeKey: String
    let itag: Int
    let relativePath: String
    let fileSize: Int64
    var storedAt: Date
    var lastPlayedAt: Date
}

/// On-disk store for progressive streams watched past the progress threshold.
actor PlaybackMediaStore {
    static let shared = PlaybackMediaStore()

    private let fileManager = FileManager.default
    private var index: [String: PlaybackStoreEntry] = [:]
    private var inflightVideoIds: Set<String> = []
    private var persistTasks: [String: Task<Void, Never>] = [:]
    private var loadedIndex = false

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

    func schedulePersist(
        videoId: String,
        sourceURL: URL,
        itag: Int,
        mimeType: String
    ) {
        loadIndexIfNeeded()
        guard !inflightVideoIds.contains(videoId) else { return }
        if localFileURL(videoId: videoId) != nil { return }

        inflightVideoIds.insert(videoId)
        persistTasks[videoId]?.cancel()
        persistTasks[videoId] = Task {
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
    }

    func cancelPersist(videoId: String) {
        persistTasks[videoId]?.cancel()
        persistTasks.removeValue(forKey: videoId)
        inflightVideoIds.remove(videoId)
    }

    /// Wipes the entire progressive media cache (index + files).
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

    /// Deletes cached progressive media for a video (index + on-disk files).
    func remove(videoId: String) {
        loadIndexIfNeeded()
        cancelPersist(videoId: videoId)
        if let entry = index.removeValue(forKey: videoId) {
            let fileURL = rootDirectory.appendingPathComponent(entry.relativePath)
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: fileURL.appendingPathExtension("partial"))
            let dir = fileURL.deletingLastPathComponent()
            if let remaining = try? fileManager.contentsOfDirectory(atPath: dir.path), remaining.isEmpty {
                try? fileManager.removeItem(at: dir)
            }
        }
        let videoDir = rootDirectory.appendingPathComponent(videoId, isDirectory: true)
        if fileManager.fileExists(atPath: videoDir.path) {
            try? fileManager.removeItem(at: videoDir)
        }
        persistIndex()
    }

    // MARK: - Private

    private var rootDirectory: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(SaltedLiteral.playbackMediaFolder, isDirectory: true)
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

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        try Task.checkCancellation()

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard (200...299).contains(status) || status == 206 else {
            throw URLError(.badServerResponse)
        }

        if startByte > 0, status == 206 {
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }
            try handle.seekToEnd()
            let chunk = try Data(contentsOf: tempURL)
            try handle.write(contentsOf: chunk)
            try fileManager.removeItem(at: tempURL)
        } else {
            if fileManager.fileExists(atPath: partial.path) {
                try fileManager.removeItem(at: partial)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: tempURL, to: destination)
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
            let url = rootDirectory.appendingPathComponent(entry.relativePath)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
            index.removeValue(forKey: entry.videoId)
            total -= entry.fileSize
            PlayProbe.log(SaltedLiteral.probeEvict, videoId: entry.videoId)
        }
        persistIndex()
    }
}
