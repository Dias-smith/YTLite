package com.ytlite.player.download

import com.ytlite.player.data.model.StreamFormat
import java.io.File
import java.util.Locale

object DownloadPaths {
    fun rootDir(filesDir: File): File = File(filesDir, "downloads").also { it.mkdirs() }

    fun videoDir(filesDir: File, videoId: String): File =
        File(rootDir(filesDir), videoId).also { it.mkdirs() }

    fun finalFile(filesDir: File, videoId: String, itag: Int, mimeType: String): File {
        val ext = extensionForMime(mimeType)
        return File(videoDir(filesDir, videoId), "$itag.$ext")
    }

    fun partialFile(finalFile: File): File = File(finalFile.absolutePath + ".partial")

    fun extensionForMime(mimeType: String): String {
        val mime = mimeType.lowercase(Locale.US)
        return when {
            "audio/mp4" in mime || "audio/aac" in mime || "audio/m4a" in mime -> "m4a"
            "audio/mpeg" in mime || "audio/mp3" in mime -> "mp3"
            "video/mp4" in mime || "mp4" in mime -> "mp4"
            else -> "bin"
        }
    }
}

data class DownloadEnqueueRequest(
    val videoId: String,
    val title: String,
    val channelName: String,
    val thumbnailUrl: String?,
    val format: StreamFormat,
    val durationSeconds: Long = 0L,
)

sealed class EnqueueResult {
    data class Started(val taskId: String) : EnqueueResult()
    data class AlreadyDownloaded(val itemId: String) : EnqueueResult()
    data class AlreadyRunning(val taskId: String) : EnqueueResult()
    data class Error(val message: String) : EnqueueResult()
}
