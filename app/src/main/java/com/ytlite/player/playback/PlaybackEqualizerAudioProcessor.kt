package com.ytlite.player.playback

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

@UnstableApi
class PlaybackEqualizerAudioProcessor : BaseAudioProcessor() {

    private data class Biquad(
        var b0: Float = 1f,
        var b1: Float = 0f,
        var b2: Float = 0f,
        var a1: Float = 0f,
        var a2: Float = 0f,
        var z1: Float = 0f,
        var z2: Float = 0f,
    ) {
        fun resetState() {
            z1 = 0f
            z2 = 0f
        }

        fun setPeakingEQ(f0: Float, sampleRate: Float, q: Float, gainDb: Float) {
            if (abs(gainDb) <= 0.001f) {
                b0 = 1f
                b1 = 0f
                b2 = 0f
                a1 = 0f
                a2 = 0f
                resetState()
                return
            }
            val a = 10f.pow(gainDb / 40f)
            val w0 = 2f * PI.toFloat() * f0 / sampleRate
            val sinW0 = sin(w0)
            val cosW0 = cos(w0)
            val alpha = sinW0 / (2f * q)
            val nb0 = 1f + alpha * a
            val nb1 = -2f * cosW0
            val nb2 = 1f - alpha * a
            val a0 = 1f + alpha / a
            val na1 = -2f * cosW0
            val na2 = 1f - alpha / a
            b0 = nb0 / a0
            b1 = nb1 / a0
            b2 = nb2 / a0
            a1 = na1 / a0
            a2 = na2 / a0
            resetState()
        }

        fun process(x: Float): Float {
            val y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    private val lock = Any()
    private var eqEnabled = false
    private var volumeBoost = 1f
    private var sampleRate = 44_100
    private var channelCount = 2
    private var encoding = C.ENCODING_PCM_16BIT
    private var leftFilters = Array(PlaybackEqualizerCatalog.BAND_COUNT) { Biquad() }
    private var rightFilters = Array(PlaybackEqualizerCatalog.BAND_COUNT) { Biquad() }
    private var lastGains = PlaybackEqualizerCatalog.flatGains()

    fun update(eqEnabled: Boolean, gainsDb: FloatArray, volumeBoost: Float = 1f) {
        synchronized(lock) {
            this.volumeBoost = volumeBoost.coerceIn(1f, PlaybackEqualizerCatalog.MAX_VOLUME_BOOST_PERCENT / 100f)
            applyGainsLocked(normalizeGains(gainsDb), eqEnabled, sampleRate)
        }
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (
            inputAudioFormat.encoding != C.ENCODING_PCM_16BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT
        ) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        sampleRate = inputAudioFormat.sampleRate
        channelCount = inputAudioFormat.channelCount.coerceAtLeast(1)
        encoding = inputAudioFormat.encoding
        synchronized(lock) {
            applyGainsLocked(lastGains, eqEnabled, sampleRate)
        }
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val outputBuffer = replaceOutputBuffer(inputBuffer.remaining())
        val eqActive: Boolean
        val boost: Float
        synchronized(lock) {
            eqActive = eqEnabled
            boost = volumeBoost
        }
        if (!eqActive && boost <= 1.001f) {
            outputBuffer.put(inputBuffer).flip()
            return
        }

        inputBuffer.order(ByteOrder.LITTLE_ENDIAN)
        outputBuffer.order(ByteOrder.LITTLE_ENDIAN)

        synchronized(lock) {
            val left = leftFilters.copyOf()
            val right = rightFilters.copyOf()
            if (encoding == C.ENCODING_PCM_FLOAT) {
                processFloat(inputBuffer, outputBuffer, left, right, eqActive, boost)
            } else {
                processPcm16(inputBuffer, outputBuffer, left, right, eqActive, boost)
            }
            leftFilters = left
            rightFilters = right
        }
        outputBuffer.flip()
    }

    private fun clampSample(sample: Float): Float = sample.coerceIn(-1f, 1f)

    private fun processPcm16(
        inputBuffer: ByteBuffer,
        outputBuffer: ByteBuffer,
        left: Array<Biquad>,
        right: Array<Biquad>,
        eqActive: Boolean,
        boost: Float,
    ) {
        if (channelCount == 1) {
            while (inputBuffer.hasRemaining()) {
                var sample = inputBuffer.short / 32768f
                if (eqActive) {
                    for (index in left.indices) {
                        sample = left[index].process(sample)
                    }
                }
                sample = clampSample(sample * boost)
                outputBuffer.putShort((sample * 32767f).toInt().coerceIn(-32768, 32767).toShort())
            }
            return
        }
        while (inputBuffer.hasRemaining()) {
            var l = inputBuffer.short / 32768f
            var r = inputBuffer.short / 32768f
            if (eqActive) {
                for (index in left.indices) {
                    l = left[index].process(l)
                    r = right[index].process(r)
                }
            }
            l = clampSample(l * boost)
            r = clampSample(r * boost)
            outputBuffer.putShort((l * 32767f).toInt().coerceIn(-32768, 32767).toShort())
            outputBuffer.putShort((r * 32767f).toInt().coerceIn(-32768, 32767).toShort())
        }
    }

    private fun processFloat(
        inputBuffer: ByteBuffer,
        outputBuffer: ByteBuffer,
        left: Array<Biquad>,
        right: Array<Biquad>,
        eqActive: Boolean,
        boost: Float,
    ) {
        if (channelCount == 1) {
            while (inputBuffer.hasRemaining()) {
                var sample = inputBuffer.float
                if (eqActive) {
                    for (index in left.indices) {
                        sample = left[index].process(sample)
                    }
                }
                outputBuffer.putFloat(clampSample(sample * boost))
            }
            return
        }
        while (inputBuffer.hasRemaining()) {
            var l = inputBuffer.float
            var r = inputBuffer.float
            if (eqActive) {
                for (index in left.indices) {
                    l = left[index].process(l)
                    r = right[index].process(r)
                }
            }
            outputBuffer.putFloat(clampSample(l * boost))
            outputBuffer.putFloat(clampSample(r * boost))
        }
    }

    private fun applyGainsLocked(gains: FloatArray, eqEnabled: Boolean, sampleRate: Int) {
        this.eqEnabled = eqEnabled
        lastGains = gains
        val rate = sampleRate.coerceAtLeast(8_000).toFloat()
        val q = 1.1f
        val frequencies = intArrayOf(
            32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
        )
        for (index in leftFilters.indices) {
            val gain = if (eqEnabled) gains[index] else 0f
            val frequency = frequencies.getOrElse(index) { 1000 }.toFloat()
            leftFilters[index].setPeakingEQ(frequency, rate, q, gain)
            rightFilters[index].setPeakingEQ(frequency, rate, q, gain)
        }
    }

    private fun normalizeGains(gainsDb: FloatArray): FloatArray {
        val gains = gainsDb.copyOf(PlaybackEqualizerCatalog.BAND_COUNT)
        if (gains.size < PlaybackEqualizerCatalog.BAND_COUNT) {
            return gains + FloatArray(PlaybackEqualizerCatalog.BAND_COUNT - gains.size)
        }
        return FloatArray(PlaybackEqualizerCatalog.BAND_COUNT) { index ->
            gains[index].coerceIn(PlaybackEqualizerCatalog.MIN_GAIN_DB, PlaybackEqualizerCatalog.MAX_GAIN_DB)
        }
    }
}
