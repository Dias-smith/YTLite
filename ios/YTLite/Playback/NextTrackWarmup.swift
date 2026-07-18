import AVFoundation
import Foundation

/// Preloads the next track's `AVURLAsset` / `AVPlayerItem` so auto-advance
/// can `replaceCurrentItem` without a cold googlevideo open.
@MainActor
final class NextTrackWarmup {
    static let shared = NextTrackWarmup()

    struct Prepared {
        let videoId: String
        let playback: VideoPlayback
        let url: URL
        let playerItem: AVPlayerItem
    }

    private var prepared: Prepared?
    private var warmingVideoId: String?
    private var warmTask: Task<Void, Never>?
    private var generation = 0

    private init() {}

    var readyVideoId: String? { prepared?.videoId }

    /// Start (or reuse) asset load for `playback`. No-op when already ready for this id+url.
    func warm(videoId: String, playback: VideoPlayback) {
        guard !videoId.isEmpty else { return }
        guard let url = playback.preferredStreamURL(preferVideo: true)
            ?? playback.preferredStreamURL(preferVideo: false)
        else {
            PlayProbe.log("warmup.skip", videoId: videoId, "no url")
            return
        }

        if let prepared,
           prepared.videoId == videoId,
           prepared.url == url,
           prepared.playerItem.status != .failed
        {
            return
        }
        if warmingVideoId == videoId, warmTask != nil {
            return
        }

        cancelWarmTask()
        prepared = nil
        warmingVideoId = videoId
        generation += 1
        let gen = generation
        PlayProbe.log("warmup.start", videoId: videoId, "host=\(url.host ?? "?")")

        warmTask = Task { [weak self] in
            guard let self else { return }
            do {
                let asset = AVURLAsset(
                    url: url,
                    options: ["AVURLAssetHTTPHeaderFieldsKey": YouTubeConstants.streamPlaybackHeaders]
                )
                let isPlayable = try await asset.load(.isPlayable)
                guard !Task.isCancelled, gen == self.generation else { return }
                guard isPlayable else {
                    PlayProbe.log("warmup.fail", videoId: videoId, "not playable")
                    self.finishWarming(videoId: videoId)
                    return
                }
                let item = AVPlayerItem(asset: asset)
                // Pull a little media ahead so auto-advance has buffered samples ready.
                item.preferredForwardBufferDuration = 8
                self.prepared = Prepared(
                    videoId: videoId,
                    playback: playback,
                    url: url,
                    playerItem: item
                )
                self.finishWarming(videoId: videoId)
                PlayProbe.log("warmup.ready", videoId: videoId)
            } catch is CancellationError {
                return
            } catch {
                guard gen == self.generation else { return }
                PlayProbe.log("warmup.fail", videoId: videoId, error.localizedDescription)
                self.finishWarming(videoId: videoId)
            }
        }
    }

    /// Take a warmed item for immediate playback. Clears the cache entry.
    func consume(videoId: String) -> Prepared? {
        guard let prepared, prepared.videoId == videoId else { return nil }
        defer {
            self.prepared = nil
            cancelWarmTask()
            warmingVideoId = nil
        }
        if prepared.playerItem.status == .failed {
            PlayProbe.log("warmup.miss", videoId: videoId, "item failed")
            return nil
        }
        PlayProbe.log(
            "warmup.hit",
            videoId: videoId,
            "status=\(Self.statusLabel(prepared.playerItem.status))"
        )
        return prepared
    }

    func invalidate(videoId: String) {
        if prepared?.videoId == videoId {
            prepared = nil
        }
        if warmingVideoId == videoId {
            cancelWarmTask()
            warmingVideoId = nil
        }
    }

    func retainOnly(videoId: String) {
        if let prepared, prepared.videoId != videoId {
            self.prepared = nil
        }
        if let warmingVideoId, warmingVideoId != videoId {
            cancelWarmTask()
            self.warmingVideoId = nil
        }
    }

    func clear() {
        prepared = nil
        cancelWarmTask()
        warmingVideoId = nil
        generation += 1
    }

    private func finishWarming(videoId: String) {
        if warmingVideoId == videoId {
            warmingVideoId = nil
        }
        warmTask = nil
    }

    private func cancelWarmTask() {
        warmTask?.cancel()
        warmTask = nil
    }

    private static func statusLabel(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "other"
        }
    }
}
