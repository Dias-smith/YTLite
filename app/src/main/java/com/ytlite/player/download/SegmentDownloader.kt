package com.ytlite.player.download

import android.util.Log
import com.ytlite.player.data.network.InnerTubeConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.coroutineContext

class SegmentDownloader(
    private val httpClient: OkHttpClient = defaultClient,
) {
    data class Progress(
        val downloadedBytes: Long,
        val totalBytes: Long,
    )

    suspend fun download(
        url: String,
        destination: File,
        threadCount: Int,
        resumeEnabled: Boolean,
        onProgress: (Progress) -> Unit,
    ): Result<File> = withContext(Dispatchers.IO) {
        runCatching {
            val partial = DownloadPaths.partialFile(destination)
            if (!resumeEnabled) {
                if (partial.exists()) partial.delete()
                if (destination.exists()) destination.delete()
            }

            val probe = probe(url)
            val total = probe.contentLength
            val threads = if (probe.acceptRanges && total > 0L) {
                threadCount.coerceIn(1, 8)
            } else {
                1
            }

            if (threads == 1) {
                downloadSingle(
                    url = url,
                    partial = partial,
                    resume = resumeEnabled && probe.acceptRanges,
                    knownTotal = total,
                    onProgress = onProgress,
                )
            } else {
                runCatching {
                    downloadMulti(url, partial, threads, total, onProgress)
                }.getOrElse { multiError ->
                    Log.w(TAG, "multi-thread download failed, falling back to single", multiError)
                    if (partial.exists()) partial.delete()
                    downloadSingle(
                        url = url,
                        partial = partial,
                        resume = false,
                        knownTotal = total,
                        onProgress = onProgress,
                    )
                }
            }

            verifyComplete(partial, total)
            if (destination.exists()) destination.delete()
            if (!partial.renameTo(destination)) {
                partial.copyTo(destination, overwrite = true)
                partial.delete()
            }
            verifyComplete(destination, total)
            destination
        }
    }

    private data class Probe(val contentLength: Long, val acceptRanges: Boolean)

    /**
     * Prefer a single Range probe — googlevideo often answers HEAD poorly, and Range
     * proves Accept-Ranges with one round-trip.
     */
    private fun probe(url: String): Probe {
        val rangeReq = requestBuilder(url)
            .header("Range", "bytes=0-0")
            .get()
            .build()
        httpClient.newCall(rangeReq).execute().use { response ->
            val contentRange = response.header("Content-Range")
            val total = contentRange
                ?.substringAfterLast('/')
                ?.toLongOrNull()
                ?: response.header("Content-Length")?.toLongOrNull()
                ?: -1L
            val accept = response.code == 206 || contentRange != null
            if (total > 0 || accept) {
                return Probe(total, accept)
            }
        }

        val head = requestBuilder(url).head().build()
        httpClient.newCall(head).execute().use { response ->
            if (response.isSuccessful) {
                val length = response.header("Content-Length")?.toLongOrNull() ?: -1L
                val accept = response.header("Accept-Ranges")
                    ?.contains("bytes", ignoreCase = true) == true
                return Probe(length, accept)
            }
        }
        return Probe(-1L, false)
    }

    private suspend fun downloadSingle(
        url: String,
        partial: File,
        resume: Boolean,
        knownTotal: Long,
        onProgress: (Progress) -> Unit,
    ) {
        partial.parentFile?.mkdirs()
        val existing = if (resume && partial.exists()) partial.length() else 0L
        if (!resume && partial.exists()) partial.delete()

        val requestBuilder = requestBuilder(url).get()
        if (existing > 0L) {
            requestBuilder.header("Range", "bytes=$existing-")
        }
        httpClient.newCall(requestBuilder.build()).execute().use { response ->
            if (!response.isSuccessful && response.code != 206) {
                error("HTTP ${response.code}")
            }
            val body = response.body ?: error("Empty body")
            val total = when {
                knownTotal > 0 -> knownTotal
                response.code == 206 -> {
                    response.header("Content-Range")
                        ?.substringAfterLast('/')
                        ?.toLongOrNull()
                        ?: (existing + body.contentLength())
                }
                else -> body.contentLength().takeIf { it > 0 } ?: -1L
            }
            RandomAccessFile(partial, "rw").use { raf ->
                if (existing > 0 && response.code == 206) {
                    raf.seek(existing)
                } else if (existing > 0 && response.code != 206) {
                    raf.setLength(0)
                    raf.seek(0)
                }
                val buffer = ByteArray(DEFAULT_BUFFER)
                var downloaded = if (response.code == 206) existing else 0L
                val progress = ProgressThrottler(onProgress)
                body.byteStream().use { input ->
                    while (coroutineContext.isActive) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        raf.write(buffer, 0, read)
                        downloaded += read
                        progress.emit(downloaded, total)
                    }
                }
                progress.emit(downloaded, total, force = true)
                if (total > 0L && downloaded != total) {
                    error("Incomplete download: got $downloaded of $total bytes")
                }
            }
        }
    }

    private suspend fun downloadMulti(
        url: String,
        partial: File,
        threadCount: Int,
        total: Long,
        onProgress: (Progress) -> Unit,
    ) = coroutineScope {
        require(total > 0)
        partial.parentFile?.mkdirs()
        if (partial.exists()) partial.delete()
        // Keep RAF open for the whole multi-download so the shared FileChannel stays valid.
        RandomAccessFile(partial, "rw").use { raf ->
            raf.setLength(total)
            val channel = raf.channel
            val downloaded = AtomicLong(0L)
            val progress = ProgressThrottler(onProgress)
            val partSize = total / threadCount

            val jobs = (0 until threadCount).map { index ->
                async(Dispatchers.IO) {
                    val start = index * partSize
                    val end = if (index == threadCount - 1) total - 1 else (start + partSize - 1)
                    val expected = end - start + 1
                    val written = downloadRangeToChannel(
                        url = url,
                        channel = channel,
                        start = start,
                        end = end,
                    ) { chunk ->
                        val current = downloaded.addAndGet(chunk)
                        progress.emit(current, total)
                    }
                    if (written != expected) {
                        error("Range $start-$end incomplete: wrote $written of $expected")
                    }
                }
            }
            jobs.awaitAll()
            progress.emit(downloaded.get(), total, force = true)
        }
        ensureActive()
        if (partial.length() != total) {
            error("Multi-thread file size mismatch: ${partial.length()} != $total")
        }
    }

    private fun downloadRangeToChannel(
        url: String,
        channel: FileChannel,
        start: Long,
        end: Long,
        onChunk: (Long) -> Unit,
    ): Long {
        val request = requestBuilder(url)
            .header("Range", "bytes=$start-$end")
            .get()
            .build()
        httpClient.newCall(request).execute().use { response ->
            if (response.code != 206) {
                error("Expected HTTP 206 for range $start-$end, got ${response.code}")
            }
            val body = response.body ?: error("Empty body")
            val expected = end - start + 1
            val buffer = ByteArray(DEFAULT_BUFFER)
            var written = 0L
            var position = start
            body.byteStream().use { input ->
                while (written < expected) {
                    val toRead = minOf(buffer.size.toLong(), expected - written).toInt()
                    val read = input.read(buffer, 0, toRead)
                    if (read < 0) break
                    // Positioned FileChannel writes to non-overlapping ranges are thread-safe;
                    // avoid a global lock that serializes all segment writers.
                    var offset = 0
                    while (offset < read) {
                        val n = channel.write(ByteBuffer.wrap(buffer, offset, read - offset), position + offset)
                        if (n <= 0) error("FileChannel write failed at ${position + offset}")
                        offset += n
                    }
                    position += read
                    written += read
                    onChunk(read.toLong())
                }
            }
            return written
        }
    }

    private fun requestBuilder(url: String): Request.Builder =
        Request.Builder()
            .url(url)
            .header("User-Agent", InnerTubeConfig.USER_AGENT)
            .header("Referer", "${InnerTubeConfig.BASE_URL}/")
            .header("Origin", InnerTubeConfig.BASE_URL)
            .header("Accept-Encoding", "identity")

    private fun verifyComplete(file: File, expectedTotal: Long) {
        if (!file.exists() || file.length() <= 0L) {
            error("Download produced an empty file")
        }
        if (expectedTotal > 0L && file.length() != expectedTotal) {
            error("Download size mismatch: ${file.length()} != $expectedTotal")
        }
    }

    private class ProgressThrottler(
        private val onProgress: (Progress) -> Unit,
    ) {
        private val lastEmitAt = AtomicLong(0L)
        private val lastBytes = AtomicLong(-1L)

        fun emit(downloaded: Long, total: Long, force: Boolean = false) {
            val now = System.currentTimeMillis()
            val lastAt = lastEmitAt.get()
            val last = lastBytes.get()
            val dueByTime = now - lastAt >= PROGRESS_INTERVAL_MS
            val dueByBytes = downloaded - last >= PROGRESS_BYTES
            if (!force && !dueByTime && !dueByBytes) return
            if (!lastEmitAt.compareAndSet(lastAt, now) && !force) return
            lastBytes.set(downloaded)
            onProgress(Progress(downloaded, total))
        }
    }

    companion object {
        private const val TAG = "SegmentDownloader"
        private const val DEFAULT_BUFFER = 256 * 1024
        private const val PROGRESS_INTERVAL_MS = 400L
        private const val PROGRESS_BYTES = 512L * 1024L

        private val defaultClient: OkHttpClient = OkHttpClient.Builder()
            .dispatcher(
                Dispatcher().apply {
                    maxRequests = 64
                    maxRequestsPerHost = 16
                },
            )
            .connectionPool(ConnectionPool(8, 5, TimeUnit.MINUTES))
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS) // large media streams; rely on TCP keepalive
            .writeTimeout(30, TimeUnit.SECONDS)
            .callTimeout(0, TimeUnit.MILLISECONDS)
            .retryOnConnectionFailure(true)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }
}
