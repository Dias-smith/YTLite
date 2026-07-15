package com.ytlite.player.playback

import android.os.SystemClock
import android.util.Log
import java.util.ArrayDeque

/**
 * Playback path timings. Samples stay in an in-memory ring for session inspection
 * (logcat + [recentSamples] / [percentileMs]).
 */
object PlaybackTiming {

    private const val TAG = "PlaybackTiming"
    private const val RING_CAPACITY = 64

    data class Sample(
        val videoId: String,
        val label: String,
        val elapsedMs: Long,
        val atElapsedRealtimeMs: Long,
    )

    @Volatile
    private var sessionStartMs: Long = 0L
    @Volatile
    private var videoId: String? = null

    @Volatile
    private var playerReadyLogged = false

    private val ringLock = Any()
    private val ring = ArrayDeque<Sample>(RING_CAPACITY)

    fun beginSession(id: String) {
        videoId = id
        sessionStartMs = SystemClock.elapsedRealtime()
        playerReadyLogged = false
        Log.d(TAG, "session_start videoId=$id")
    }

    fun logWebViewReady() {
        logElapsed("webview_ready_ms")
    }

    fun logExtractComplete() {
        logElapsed("extract_ms")
    }

    fun logPlayStart() {
        logElapsed("play_start_ms")
    }

    fun logPlayerReady() {
        if (playerReadyLogged) return
        playerReadyLogged = true
        logElapsed("player_ready_ms")
    }

    fun recentSamples(): List<Sample> = synchronized(ringLock) {
        ring.toList()
    }

    /** Percentile of [label] samples in the ring; null if fewer than [minCount]. */
    fun percentileMs(label: String, percentile: Double, minCount: Int = 3): Long? {
        require(percentile in 0.0..100.0)
        val values = synchronized(ringLock) {
            ring.filter { it.label == label }.map { it.elapsedMs }.sorted()
        }
        if (values.size < minCount) return null
        val index = ((percentile / 100.0) * (values.size - 1))
            .toInt()
            .coerceIn(0, values.lastIndex)
        return values[index]
    }

    private fun logElapsed(label: String) {
        val id = videoId ?: return
        val elapsed = SystemClock.elapsedRealtime() - sessionStartMs
        val sample = Sample(
            videoId = id,
            label = label,
            elapsedMs = elapsed,
            atElapsedRealtimeMs = SystemClock.elapsedRealtime(),
        )
        synchronized(ringLock) {
            if (ring.size >= RING_CAPACITY) {
                ring.removeFirst()
            }
            ring.addLast(sample)
        }
        val p50 = percentileMs(label, 50.0)
        val p95 = percentileMs(label, 95.0)
        Log.d(
            TAG,
            "$label=$elapsed videoId=$id ring=${synchronized(ringLock) { ring.size }} " +
                "p50=$p50 p95=$p95",
        )
    }
}
