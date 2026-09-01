import AVFoundation
import Foundation
import MediaToolbox

/// Attaches an in-place EQ tap to `AVPlayerItem` audio (VOD only — not live/HLS).
actor PlaybackEqualizerEngine {
    static let shared = PlaybackEqualizerEngine()

    private let processor = PlaybackEqualizerProcessor()
    private weak var attachedItem: AVPlayerItem?
    private var isEligible = true

    func attach(to item: AVPlayerItem, eligible: Bool) async {
        isEligible = eligible
        guard eligible else {
            await clearMix(on: item)
            return
        }
        guard let track = await loadPrimaryAudioTrack(for: item.asset) else {
            PlayProbe.log("eq.attach.skip", videoId: nil, "no audio track")
            return
        }
        guard let tap = Self.makeProcessingTap(processor: processor) else {
            PlayProbe.log("eq.attach.fail", videoId: nil, "tap create failed")
            return
        }
        let input = AVMutableAudioMixInputParameters(track: track)
        input.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [input]
        item.audioMix = mix
        attachedItem = item
        PlayProbe.log("eq.attach.ok", videoId: nil, "bands=\(PlaybackEqualizerCatalog.bandCount)")
    }

    func apply(enabled: Bool, gainsDb: [Float], volumeBoost: Float) {
        let boost = isEligible ? volumeBoost : 1
        processor.update(eqEnabled: enabled && isEligible, gainsDb: gainsDb, volumeBoost: boost)
    }

    func detach(from item: AVPlayerItem?) async {
        guard let item else { return }
        await clearMix(on: item)
    }

    // MARK: - Private

    private func clearMix(on item: AVPlayerItem) async {
        item.audioMix = nil
        if attachedItem === item {
            attachedItem = nil
        }
        processor.update(eqEnabled: false, gainsDb: PlaybackEqualizerCatalog.flatGains(), volumeBoost: 1)
    }

    private func loadPrimaryAudioTrack(for asset: AVAsset) async -> AVAssetTrack? {
        if #available(iOS 16.0, *) {
            let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            return tracks.first
        }
        return asset.tracks(withMediaType: .audio).first
    }

    private static func makeProcessingTap(processor: PlaybackEqualizerProcessor) -> MTAudioProcessingTap? {
        let clientInfo = Unmanaged.passRetained(TapClient(processor: processor)).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )
        guard status == noErr else { return nil }
        return tap
    }
}

enum PlaybackEqualizerSupport {
    static func isEligibleStreamURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let lower = url.absoluteString.lowercased()
        if lower.contains(".m3u8") || lower.contains("/manifest/hls") { return false }
        return true
    }
}

// MARK: - MTAudioProcessingTap

private final class TapClient {
    let processor: PlaybackEqualizerProcessor

    init(processor: PlaybackEqualizerProcessor) {
        self.processor = processor
    }
}

private func tapInit(
    tap: MTAudioProcessingTap,
    clientInfo: UnsafeMutableRawPointer?,
    storageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    storageOut.pointee = clientInfo
}

private func tapFinalize(tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<TapClient>.fromOpaque(storage).release()
}

private func tapPrepare(
    tap: MTAudioProcessingTap,
    maxFrames: CMItemCount,
    processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let client = Unmanaged<TapClient>.fromOpaque(storage).takeUnretainedValue()
    let sampleRate = Float(processingFormat.pointee.mSampleRate)
    client.processor.noteFormat(processingFormat.pointee)
    client.processor.noteSampleRate(sampleRate)
}

private func tapUnprepare(tap: MTAudioProcessingTap) {}

private func tapProcess(
    tap: MTAudioProcessingTap,
    numberFrames: CMItemCount,
    flags: MTAudioProcessingTapFlags,
    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        nil,
        numberFramesOut
    )
    guard status == noErr else { return }
    let storage = MTAudioProcessingTapGetStorage(tap)
    let client = Unmanaged<TapClient>.fromOpaque(storage).takeUnretainedValue()
    client.processor.process(
        bufferList: bufferListInOut,
        frameCount: AVAudioFrameCount(numberFramesOut.pointee)
    )
}
