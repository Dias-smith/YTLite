import Foundation

/// In-memory next-track stream prepare (Android PlaybackPreparer).
/// Soft TTL + URL `expire` keep early prepare from serving stale googlevideo URLs.
@MainActor
final class PlaybackPreparer {
    static let shared = PlaybackPreparer()

    /// Aligns with Android PlaybackPreparer TTL.
    private static let softTTL: TimeInterval = 5 * 60
    /// Re-resolve while still "next" so long listens stay hot.
    private static let refreshAge: TimeInterval = 4 * 60
    /// Refuse URLs that expire within this margin.
    private static let expireSafetyMargin: TimeInterval = 90

    private enum Entry {
        case loading(UUID, Task<VideoPlayback?, Never>)
        case ready(Stored)
    }

    private struct Stored {
        let playback: VideoPlayback
        let resolvedAt: Date
        let expireAt: Date?
    }

    private var entries: [String: Entry] = [:]

    private init() {}

    /// Start (or reuse) resolve for `videoId`. No-op when a fresh ready entry exists.
    func prepare(videoId: String, preferLiveHLS: Bool = false) {
        guard !videoId.isEmpty else { return }
        if case .ready(let stored) = entries[videoId], isFresh(stored) {
            return
        }
        if case .loading = entries[videoId] {
            return
        }
        PlayProbe.log(
            "prepare.start",
            videoId: videoId,
            "\(preferLiveHLS ? "liveHLS" : "vod") \(PlayProbe.concurrencySnapshot())"
        )
        let requestId = UUID()
        let task = Task { () -> VideoPlayback? in
            do {
                let playback = try await Self.resolveWithRetry(
                    videoId: videoId,
                    preferLiveHLS: preferLiveHLS
                )
                guard !Task.isCancelled else { return nil }
                let expireAt = Self.expireDate(from: playback)
                let stored = Stored(
                    playback: playback,
                    resolvedAt: Date(),
                    expireAt: expireAt
                )
                await MainActor.run {
                    // Only store if this entry is still our in-flight request.
                    if case .loading(let id, _) = self.entries[videoId], id == requestId {
                        self.entries[videoId] = .ready(stored)
                    }
                }
                PlayProbe.log(
                    "prepare.ready",
                    videoId: videoId,
                    expireAt.map { "expire=\(Int($0.timeIntervalSince1970))" } ?? "expire=none"
                )
                return playback
            } catch is CancellationError {
                return nil
            } catch {
                PlayProbe.log("prepare.fail", videoId: videoId, error.localizedDescription)
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

    /// Non-destructive read of a fresh ready entry (for AVPlayerItem prime).
    func peekReady(videoId: String) -> VideoPlayback? {
        guard !videoId.isEmpty else { return nil }
        guard case .ready(let stored) = entries[videoId], isFresh(stored) else { return nil }
        return stored.playback
    }

    /// Wait until resolve finishes without consuming the store entry.
    func waitUntilReady(videoId: String) async -> VideoPlayback? {
        guard !videoId.isEmpty else { return nil }
        guard let entry = entries[videoId] else { return nil }
        switch entry {
        case .ready(let stored):
            return isFresh(stored) ? stored.playback : nil
        case .loading(_, let task):
            guard let playback = await task.value else { return nil }
            if case .ready(let stored) = entries[videoId] {
                return isFresh(stored) ? stored.playback : nil
            }
            // Entry may have been consumed while we awaited; still validate the payload.
            let stored = Stored(
                playback: playback,
                resolvedAt: Date(),
                expireAt: Self.expireDate(from: playback)
            )
            return isFresh(stored) ? playback : nil
        }
    }

    /// Take a fresh result for playback. Awaits in-flight resolve when needed.
    func consume(videoId: String) async -> VideoPlayback? {
        guard !videoId.isEmpty else { return nil }
        guard let entry = entries.removeValue(forKey: videoId) else {
            PlayProbe.log("prepare.miss", videoId: videoId)
            return nil
        }
        switch entry {
        case .ready(let stored):
            if isFresh(stored) {
                PlayProbe.log("prepare.hit", videoId: videoId)
                return stored.playback
            }
            PlayProbe.log("prepare.stale", videoId: videoId, "ready")
            return nil
        case .loading(_, let task):
            PlayProbe.log("prepare.await", videoId: videoId)
            guard let playback = await task.value else {
                PlayProbe.log("prepare.miss", videoId: videoId, "await nil")
                return nil
            }
            let expireAt = Self.expireDate(from: playback)
            let stored = Stored(playback: playback, resolvedAt: Date(), expireAt: expireAt)
            if isFresh(stored) {
                PlayProbe.log("prepare.hit", videoId: videoId, "await")
                return playback
            }
            PlayProbe.log("prepare.stale", videoId: videoId, "await")
            return nil
        }
    }

    /// If a ready entry is older than `refreshAge`, replace it with a new resolve.
    func refreshIfStale(videoId: String, preferLiveHLS: Bool = false) {
        guard !videoId.isEmpty else { return }
        guard case .ready(let stored) = entries[videoId] else { return }
        let age = Date().timeIntervalSince(stored.resolvedAt)
        guard age >= Self.refreshAge else { return }
        PlayProbe.log(
            "prepare.refresh",
            videoId: videoId,
            "age=\(Int(age))s"
        )
        entries.removeValue(forKey: videoId)
        NextTrackPrimer.shared.invalidate(videoId: videoId)
        prepare(videoId: videoId, preferLiveHLS: preferLiveHLS)
    }

    /// Near-end health check. Returns true only when resolve has completed and
    /// the stored stream URL is still usable. Missing/stale entries are restarted.
    @discardableResult
    func ensureCompletedAndValid(
        videoId: String,
        preferLiveHLS: Bool = false
    ) -> Bool {
        guard !videoId.isEmpty else { return false }
        guard let entry = entries[videoId] else {
            PlayProbe.log("prepare.near_end.missing", videoId: videoId)
            prepare(videoId: videoId, preferLiveHLS: preferLiveHLS)
            return false
        }

        switch entry {
        case .loading:
            PlayProbe.log("prepare.near_end.pending", videoId: videoId)
            return false
        case .ready(let stored):
            guard isFresh(stored) else {
                PlayProbe.log("prepare.near_end.invalid", videoId: videoId)
                entries.removeValue(forKey: videoId)
                NextTrackPrimer.shared.invalidate(videoId: videoId)
                prepare(videoId: videoId, preferLiveHLS: preferLiveHLS)
                return false
            }
            PlayProbe.log("prepare.near_end.valid", videoId: videoId)
            return true
        }
    }

    func invalidate(videoId: String) {
        if case .loading(_, let task) = entries.removeValue(forKey: videoId) {
            task.cancel()
        }
        // Prime can outlive the resolve store entry after it was consumed.
        NextTrackPrimer.shared.invalidate(videoId: videoId)
    }

    /// Keep at most one entry (the track about to play); drop everything else.
    func retainOnly(videoId: String) {
        let keys = Array(entries.keys)
        for key in keys where key != videoId {
            invalidate(videoId: key)
        }
        NextTrackPrimer.shared.retainOnly(videoId: videoId)
    }

    func clear() {
        for (_, entry) in entries {
            if case .loading(_, let task) = entry {
                task.cancel()
            }
        }
        entries.removeAll()
        NextTrackPrimer.shared.clear()
    }

    // MARK: - Freshness

    private func isFresh(_ stored: Stored) -> Bool {
        let now = Date()
        if now.timeIntervalSince(stored.resolvedAt) > Self.softTTL {
            return false
        }
        if let expireAt = stored.expireAt,
           expireAt.timeIntervalSince(now) < Self.expireSafetyMargin
        {
            return false
        }
        // Must still have a playable URL.
        return stored.playback.preferredStreamURL(preferVideo: true) != nil
            || stored.playback.preferredStreamURL(preferVideo: false) != nil
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

    private static func resolveWithRetry(
        videoId: String,
        preferLiveHLS: Bool
    ) async throws -> VideoPlayback {
        do {
            return try await StreamResolver.shared.resolvePlayback(
                videoId: videoId,
                preferLiveHLS: preferLiveHLS
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if case StreamResolver.StreamResolverError.timeout = error { throw error }
            let lower = error.localizedDescription.lowercased()
            if lower.contains("timed out") || lower.contains("timeout") { throw error }
            try await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { throw CancellationError() }
            return try await StreamResolver.shared.resolvePlayback(
                videoId: videoId,
                preferLiveHLS: preferLiveHLS
            )
        }
    }
}
