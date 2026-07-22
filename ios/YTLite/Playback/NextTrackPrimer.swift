import AVFoundation
import Foundation

/// Preloads the next track's `AVURLAsset` / `AVPlayerItem` so auto-advance
/// can `replaceCurrentItem` without a cold googlevideo open.
@MainActor
final class NextTrackPrimer {
    static let shared = NextTrackPrimer()

    struct Prepared {
        let videoId: String
        let playback: VideoPlayback
        let url: URL
        let playerItem: AVPlayerItem
    }

    private var prepared: Prepared?
    private var primingVideoId: String?
    private var primeTask: Task<Void, Never>?
    private var generation = 0

    private init() {}

    var readyVideoId: String? { prepared?.videoId }

    /// Start (or reuse) asset load for `playback`. No-op when already ready for this id+url.
    func prime(videoId: String, playback: VideoPlayback) {
        guard !videoId.isEmpty else { return }
        guard let url = playback.preferredStreamURL(preferVideo: true)
            ?? playback.preferredStreamURL(preferVideo: false)
        else {
            PlayProbe.log("prime.skip", videoId: videoId, "no url")
            return
        }

        if let prepared,
           prepared.videoId == videoId,
           prepared.url == url,
           prepared.playerItem.status != .failed
        {
            return
        }
        if primingVideoId == videoId, primeTask != nil {
            return
        }

        cancelPrimeTask()
        prepared = nil
        primingVideoId = videoId
        generation += 1
        let gen = generation
        let t0 = PlayProbe.now()
        PlayProbe.log(
            "prime.start",
            videoId: videoId,
            PlayProbe.streamSummary(url: url)
        )

        primeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let asset = AVURLAsset(
                    url: url,
                    options: ["AVURLAssetHTTPHeaderFieldsKey": YouTubeConstants.streamPlaybackHeaders]
                )
                let isPlayable = try await asset.load(.isPlayable)
                guard !Task.isCancelled, gen == self.generation else { return }
                guard isPlayable else {
                    PlayProbe.log(
                        "prime.fail",
                        videoId: videoId,
                        "not playable ms=\(PlayProbe.ms(since: t0)) isTimeout=0 \(PlayProbe.streamSummary(url: url))"
                    )
                    self.finishPriming(videoId: videoId)
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
                self.finishPriming(videoId: videoId)
                PlayProbe.log(
                    "prime.ready",
                    videoId: videoId,
                    "ms=\(PlayProbe.ms(since: t0)) \(PlayProbe.streamSummary(url: url))"
                )
            } catch is CancellationError {
                return
            } catch {
                guard gen == self.generation else { return }
                PlayProbe.log(
                    "prime.fail",
                    videoId: videoId,
                    "\(PlayProbe.networkFailFlags(error)) ms=\(PlayProbe.ms(since: t0)) err=\(error.localizedDescription) \(PlayProbe.streamSummary(url: url))"
                )
                self.finishPriming(videoId: videoId)
            }
        }
    }

    /// Take a primed item for immediate playback. Clears the store entry.
    func consume(videoId: String) -> Prepared? {
        guard let prepared, prepared.videoId == videoId else { return nil }
        defer {
            self.prepared = nil
            cancelPrimeTask()
            primingVideoId = nil
        }
        if prepared.playerItem.status == .failed {
            PlayProbe.log("prime.miss", videoId: videoId, "item failed")
            return nil
        }
        PlayProbe.log(
            "prime.hit",
            videoId: videoId,
            "status=\(Self.statusLabel(prepared.playerItem.status))"
        )
        return prepared
    }

    func invalidate(videoId: String) {
        if prepared?.videoId == videoId {
            prepared = nil
        }
        if primingVideoId == videoId {
            cancelPrimeTask()
            primingVideoId = nil
        }
    }

    func retainOnly(videoId: String) {
        if let prepared, prepared.videoId != videoId {
            self.prepared = nil
        }
        if let primingVideoId, primingVideoId != videoId {
            cancelPrimeTask()
            self.primingVideoId = nil
        }
    }

    func clear() {
        prepared = nil
        cancelPrimeTask()
        primingVideoId = nil
        generation += 1
    }

    private func finishPriming(videoId: String) {
        if primingVideoId == videoId {
            primingVideoId = nil
        }
        primeTask = nil
    }

    private func cancelPrimeTask() {
        primeTask?.cancel()
        primeTask = nil
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
