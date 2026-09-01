import AVFoundation
import Foundation

/// Real-time peaking EQ for AVPlayer audio tap (10-band cascade).
final class PlaybackEqualizerProcessor: @unchecked Sendable {
    private struct Biquad {
        var b0: Float = 1
        var b1: Float = 0
        var b2: Float = 0
        var a1: Float = 0
        var a2: Float = 0
        var z1: Float = 0
        var z2: Float = 0

        mutating func resetState() {
            z1 = 0
            z2 = 0
        }

        mutating func setPeakingEQ(f0: Float, sampleRate: Float, q: Float, gainDB: Float) {
            guard abs(gainDB) > 0.001 else {
                b0 = 1
                b1 = 0
                b2 = 0
                a1 = 0
                a2 = 0
                resetState()
                return
            }
            let a = powf(10, gainDB / 40)
            let w0 = 2 * Float.pi * f0 / sampleRate
            let sinW0 = sinf(w0)
            let cosW0 = cosf(w0)
            let alpha = sinW0 / (2 * q)
            let nb0 = 1 + alpha * a
            let nb1 = -2 * cosW0
            let nb2 = 1 - alpha * a
            let a0 = 1 + alpha / a
            let na1 = -2 * cosW0
            let na2 = 1 - alpha / a
            b0 = nb0 / a0
            b1 = nb1 / a0
            b2 = nb2 / a0
            a1 = na1 / a0
            a2 = na2 / a0
            resetState()
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    private let lock = NSLock()
    private var leftFilters: [Biquad]
    private var rightFilters: [Biquad]
    private var enabled = false
    private var volumeBoost: Float = 1
    private var sampleRate: Float = 44_100
    private var isFloatPCM = true
    private var lastGains: [Float] = PlaybackEqualizerCatalog.flatGains()

    private static let limiterHeadroom: Float = 0.95

    init() {
        leftFilters = Array(repeating: Biquad(), count: PlaybackEqualizerCatalog.bandCount)
        rightFilters = Array(repeating: Biquad(), count: PlaybackEqualizerCatalog.bandCount)
        applyGainsLocked(lastGains, enabled: false, sampleRate: sampleRate)
    }

    func update(eqEnabled: Bool, gainsDb: [Float], volumeBoost: Float = 1, sampleRate: Float? = nil) {
        lock.lock()
        if let sampleRate, sampleRate > 0 {
            self.sampleRate = sampleRate
        }
        self.volumeBoost = min(max(volumeBoost, 1), PlaybackEqualizerCatalog.maxVolumeBoostPercent / 100)
        applyGainsLocked(normalizedGains(gainsDb), enabled: eqEnabled, sampleRate: self.sampleRate)
        lock.unlock()
    }

    func noteFormat(_ format: AudioStreamBasicDescription) {
        lock.lock()
        isFloatPCM = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        lock.unlock()
    }

    func noteSampleRate(_ sampleRate: Float) {
        lock.lock()
        if sampleRate > 0, abs(self.sampleRate - sampleRate) > 1 {
            self.sampleRate = sampleRate
            applyGainsLocked(lastGains, enabled: enabled, sampleRate: sampleRate)
        }
        lock.unlock()
    }

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: AVAudioFrameCount) {
        lock.lock()
        let eqActive = enabled
        let boost = volumeBoost
        let useFloat = isFloatPCM
        var left = leftFilters
        var right = rightFilters
        lock.unlock()
        guard frameCount > 0, eqActive || boost > 1.001 else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard buffers.first?.mData != nil else { return }
        let frames = Int(frameCount)

        if buffers.count > 1,
           let lData = buffers[0].mData,
           let rData = buffers[1].mData
        {
            var peak: Float = 1e-8
            if useFloat {
                let lFloat = lData.assumingMemoryBound(to: Float.self)
                let rFloat = rData.assumingMemoryBound(to: Float.self)
                for frame in 0..<frames {
                    var l = lFloat[frame]
                    var r = rFloat[frame]
                    if eqActive {
                        for index in left.indices {
                            l = left[index].process(l)
                            r = right[index].process(r)
                        }
                    }
                    lFloat[frame] = l
                    rFloat[frame] = r
                    peak = max(peak, abs(l), abs(r))
                }
                let gain = Self.effectiveGain(requested: boost, peak: peak)
                for frame in 0..<frames {
                    lFloat[frame] = Self.softLimit(lFloat[frame] * gain)
                    rFloat[frame] = Self.softLimit(rFloat[frame] * gain)
                }
            } else {
                let lInt16 = lData.assumingMemoryBound(to: Int16.self)
                let rInt16 = rData.assumingMemoryBound(to: Int16.self)
                var peak: Float = 1e-8
                var leftSamples = [Float](repeating: 0, count: frames)
                var rightSamples = [Float](repeating: 0, count: frames)
                for frame in 0..<frames {
                    var l = Float(lInt16[frame]) / 32_768
                    var r = Float(rInt16[frame]) / 32_768
                    if eqActive {
                        for index in left.indices {
                            l = left[index].process(l)
                            r = right[index].process(r)
                        }
                    }
                    leftSamples[frame] = l
                    rightSamples[frame] = r
                    peak = max(peak, abs(l), abs(r))
                }
                let gain = Self.effectiveGain(requested: boost, peak: peak)
                for frame in 0..<frames {
                    lInt16[frame] = Self.pcm16(fromNormalized: Self.softLimit(leftSamples[frame] * gain))
                    rInt16[frame] = Self.pcm16(fromNormalized: Self.softLimit(rightSamples[frame] * gain))
                }
            }
        } else if let monoData = buffers[0].mData {
            var peak: Float = 1e-8
            if useFloat {
                let mono = monoData.assumingMemoryBound(to: Float.self)
                for frame in 0..<frames {
                    var sample = mono[frame]
                    if eqActive {
                        for index in left.indices {
                            sample = left[index].process(sample)
                        }
                    }
                    mono[frame] = sample
                    peak = max(peak, abs(sample))
                }
                let gain = Self.effectiveGain(requested: boost, peak: peak)
                for frame in 0..<frames {
                    mono[frame] = Self.softLimit(mono[frame] * gain)
                }
            } else {
                let mono = monoData.assumingMemoryBound(to: Int16.self)
                var peak: Float = 1e-8
                var samples = [Float](repeating: 0, count: frames)
                for frame in 0..<frames {
                    var sample = Float(mono[frame]) / 32_768
                    if eqActive {
                        for index in left.indices {
                            sample = left[index].process(sample)
                        }
                    }
                    samples[frame] = sample
                    peak = max(peak, abs(sample))
                }
                let gain = Self.effectiveGain(requested: boost, peak: peak)
                for frame in 0..<frames {
                    mono[frame] = Self.pcm16(fromNormalized: Self.softLimit(samples[frame] * gain))
                }
            }
        }

        lock.lock()
        leftFilters = left
        rightFilters = right
        lock.unlock()
    }

    private static func effectiveGain(requested: Float, peak: Float) -> Float {
        let safePeak = max(peak, 1e-6)
        let antiClipGain = limiterHeadroom / safePeak
        if requested > 1.001 {
            return min(requested, antiClipGain)
        }
        return min(1, antiClipGain)
    }

    /// Smooth saturation — avoids hard-clip harmonics from naive `min/max`.
    private static func softLimit(_ sample: Float) -> Float {
        tanh(sample)
    }

    private static func pcm16(fromNormalized sample: Float) -> Int16 {
        let clamped = min(max(sample, -1), 1)
        return Int16(clamped * 32_767)
    }

    private func applyGainsLocked(_ gains: [Float], enabled: Bool, sampleRate: Float) {
        self.enabled = enabled
        lastGains = gains
        let rate = max(sampleRate, 8_000)
        let q: Float = 1.1
        for (index, frequency) in PlaybackEqualizerCatalog.bandFrequenciesHz.enumerated()
            where index < leftFilters.count
        {
            let gain = enabled ? gains[index] : 0
            leftFilters[index].setPeakingEQ(
                f0: Float(frequency),
                sampleRate: rate,
                q: q,
                gainDB: gain
            )
            rightFilters[index].setPeakingEQ(
                f0: Float(frequency),
                sampleRate: rate,
                q: q,
                gainDB: gain
            )
        }
    }

    private func normalizedGains(_ gainsDb: [Float]) -> [Float] {
        var gains = gainsDb
        if gains.count < PlaybackEqualizerCatalog.bandCount {
            gains.append(contentsOf: Array(repeating: 0, count: PlaybackEqualizerCatalog.bandCount - gains.count))
        }
        if gains.count > PlaybackEqualizerCatalog.bandCount {
            gains = Array(gains.prefix(PlaybackEqualizerCatalog.bandCount))
        }
        return gains.map { min(max($0, PlaybackEqualizerCatalog.minGainDb), PlaybackEqualizerCatalog.maxGainDb) }
    }
}
