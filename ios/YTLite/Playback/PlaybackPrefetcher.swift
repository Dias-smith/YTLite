import Foundation

/// In-memory next-track stream prefetch (Android `PlaybackPrefetcher`).
/// Soft TTL + URL `expire` keep early prefetch from serving stale googlevideo URLs.
@MainActor
final class PlaybackPrefetcher {
    static let shared = PlaybackPrefetcher()

    /// Aligns with Android `PlaybackPrefetcher.TTL_MS`.
    private static let softTTL: TimeInterval = 5 * 60
    /// Re-extract while still "next" so long listens stay hot.
    private static let refreshAge: TimeInterval = 4 * 60
    /// Refuse URLs that expire within this margin.
    private static let expireSafetyMargin: TimeInterval = 90

    private enum Entry {
        case loading(UUID, Task<VideoPlayback?, Never>)
        case ready(Cached)
    }

    private struct Cached {
        let playback: VideoPlayback
        let extractedAt: Date
        let expireAt: Date?
    }

    private var entries: [String: Entry] = [:]

    private init() {}

    /// Start (or reuse) extract for `videoId`. No-op when a fresh ready entry exists.
    func prefetch(videoId: String, preferLiveHLS: Bool = false) {
        guard !videoId.isEmpty else { return }
        if case .ready(let cached) = entries[videoId], isFresh(cached) {
            return
        }
        if case .loading = entries[videoId] {
            return
        }
        PlayProbe.log(
            "prefetch.start",
            videoId: videoId,
            "\(preferLiveHLS ? "liveHLS" : "vod") \(PlayProbe.concurrencySnapshot())"
        )
        let requestId = UUID()
        let task = Task { () -> VideoPlayback? in
            do {
                let playback = try await Self.extractWithRetry(
                    videoId: videoId,
                    preferLiveHLS: preferLiveHLS
                )
                guard !Task.isCancelled else { return nil }
                let expireAt = Self.expireDate(from: playback)
                let cached = Cached(
                    playback: playback,
                    extractedAt: Date(),
                    expireAt: expireAt
                )
                await MainActor.run {
                    // Only store if this entry is still our in-flight request.
                    if case .loading(let id, _) = self.entries[videoId], id == requestId {
                        self.entries[videoId] = .ready(cached)
                    }
                }
                PlayProbe.log(
                    "prefetch.ready",
                    videoId: videoId,
                    expireAt.map { "expire=\(Int($0.timeIntervalSince1970))" } ?? "expire=none"
                )
                return playback
            } catch is CancellationError {
                return nil
            } catch {
                PlayProbe.log("prefetch.fail", videoId: videoId, error.localizedDescription)
                await MainActor.run {
                    if case .loading(let id, _) = self.entries[videoId], id == requestId {
                        self.entries.removeValue(forKey: videoId)
                    }
                }
                return nil
            }
        }
        entries[videoId] = .loading(requestId, task)
    }

    /// Non-destructive read of a fresh ready entry (for AVPlayerItem warm-up).
    func peekReady(videoId: String) -> VideoPlayback? {
        guard !videoId.isEmpty else { return nil }
        guard case .ready(let cached) = entries[videoId], isFresh(cached) else { return nil }
        return cached.playback
    }

    /// Wait until extract finishes without consuming the cache entry.
    func waitUntilReady(videoId: String) async -> VideoPlayback? {
        guard !videoId.isEmpty else { return nil }
        guard let entry = entries[videoId] else { return nil }
        switch entry {
        case .ready(let cached):
            return isFresh(cached) ? cached.playback : nil
        case .loading(_, let task):
            guard let playback = await task.value else { return nil }
            if case .ready(let cached) = entries[videoId] {
                return isFresh(cached) ? cached.playback : nil
            }
            // Entry may have been consumed while we awaited; still validate the payload.
            let cached = Cached(
                playback: playback,
                extractedAt: Date(),
                expireAt: Self.expireDate(from: playback)
            )
            return isFresh(cached) ? playback : nil
        }
    }

    /// Take a fresh result for playback. Awaits in-flight extract when needed.
    func consume(videoId: String) async -> VideoPlayback? {
        guard !videoId.isEmpty else { return nil }
        guard let entry = entries.removeValue(forKey: videoId) else {
            PlayProbe.log("prefetch.miss", videoId: videoId)
            return nil
        }
        switch entry {
        case .ready(let cached):
            if isFresh(cached) {
                PlayProbe.log("prefetch.hit", videoId: videoId)
                return cached.playback
            }
            PlayProbe.log("prefetch.stale", videoId: videoId, "ready")
            return nil
        case .loading(_, let task):
            PlayProbe.log("prefetch.await", videoId: videoId)
            guard let playback = await task.value else {
                PlayProbe.log("prefetch.miss", videoId: videoId, "await nil")
                return nil
            }
            let expireAt = Self.expireDate(from: playback)
            let cached = Cached(playback: playback, extractedAt: Date(), expireAt: expireAt)
            if isFresh(cached) {
                PlayProbe.log("prefetch.hit", videoId: videoId, "await")
                return playback
            }
            PlayProbe.log("prefetch.stale", videoId: videoId, "await")
            return nil
        }
    }

    /// If a ready entry is older than `refreshAge`, replace it with a new extract.
    func refreshIfStale(videoId: String, preferLiveHLS: Bool = false) {
        guard !videoId.isEmpty else { return }
        guard case .ready(let cached) = entries[videoId] else { return }
        let age = Date().timeIntervalSince(cached.extractedAt)
        guard age >= Self.refreshAge else { return }
        PlayProbe.log(
            "prefetch.refresh",
            videoId: videoId,
            "age=\(Int(age))s"
        )
        entries.removeValue(forKey: videoId)
        NextTrackWarmup.shared.invalidate(videoId: videoId)
        prefetch(videoId: videoId, preferLiveHLS: preferLiveHLS)
    }

    /// Near-end health check. Returns true only when extraction has completed and
    /// the cached stream URL is still usable. Missing/stale entries are restarted.
    @discardableResult
    func ensureCompletedAndValid(
        videoId: String,
        preferLiveHLS: Bool = false
    ) -> Bool {
        guard !videoId.isEmpty else { return false }
        guard let entry = entries[videoId] else {
            PlayProbe.log("prefetch.near_end.missing", videoId: videoId)
            prefetch(videoId: videoId, preferLiveHLS: preferLiveHLS)
            return false
        }

        switch entry {
        case .loading:
            PlayProbe.log("prefetch.near_end.pending", videoId: videoId)
            return false
        case .ready(let cached):
            guard isFresh(cached) else {
                PlayProbe.log("prefetch.near_end.invalid", videoId: videoId)
                entries.removeValue(forKey: videoId)
                NextTrackWarmup.shared.invalidate(videoId: videoId)
                prefetch(videoId: videoId, preferLiveHLS: preferLiveHLS)
                return false
            }
            PlayProbe.log("prefetch.near_end.valid", videoId: videoId)
            return true
        }
    }

    func invalidate(videoId: String) {
        guard let entry = entries.removeValue(forKey: videoId) else { return }
        if case .loading(_, let task) = entry {
            task.cancel()
        }
        NextTrackWarmup.shared.invalidate(videoId: videoId)
    }

    /// Keep at most one entry (the track about to play); drop everything else.
    func retainOnly(videoId: String) {
        let keys = Array(entries.keys)
        for key in keys where key != videoId {
            invalidate(videoId: key)
        }
        NextTrackWarmup.shared.retainOnly(videoId: videoId)
    }

    func clear() {
        for (_, entry) in entries {
            if case .loading(_, let task) = entry {
                task.cancel()
            }
        }
        entries.removeAll()
        NextTrackWarmup.shared.clear()
    }

    // MARK: - Freshness

    private func isFresh(_ cached: Cached) -> Bool {
        let now = Date()
        if now.timeIntervalSince(cached.extractedAt) > Self.softTTL {
            return false
        }
        if let expireAt = cached.expireAt,
           expireAt.timeIntervalSince(now) < Self.expireSafetyMargin
        {
            return false
        }
        // Must still have a playable URL.
        return cached.playback.preferredStreamURL(preferVideo: true) != nil
            || cached.playback.preferredStreamURL(preferVideo: false) != nil
    }

    static func expireDate(from playback: VideoPlayback) -> Date? {
        let url = playback.preferredStreamURL(preferVideo: true)
            ?? playback.preferredStreamURL(preferVideo: false)
        return url.flatMap(expireDate(from:))
    }

    static func expireDate(from url: URL) -> Date? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        for key in ["expire", "expireat"] {
            if let raw = items.first(where: { $0.name.lowercased() == key })?.value,
               let seconds = TimeInterval(raw),
               seconds > 1_000_000_000
            {
                return Date(timeIntervalSince1970: seconds)
            }
        }
        return nil
    }

    private static func extractWithRetry(
        videoId: String,
        preferLiveHLS: Bool
    ) async throws -> VideoPlayback {
        do {
            return try await ExtractorBridge.shared.extractPlayback(
                videoId: videoId,
                preferLiveHLS: preferLiveHLS
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if case ExtractorBridge.ExtractorError.timeout = error { throw error }
            let lower = error.localizedDescription.lowercased()
            if lower.contains("timed out") || lower.contains("timeout") { throw error }
            try await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { throw CancellationError() }
            return try await ExtractorBridge.shared.extractPlayback(
                videoId: videoId,
                preferLiveHLS: preferLiveHLS
            )
        }
    }
}
