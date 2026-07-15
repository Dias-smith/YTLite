package com.ytlite.player.download

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import androidx.core.content.ContextCompat
import com.ytlite.player.data.local.YTLiteDatabase
import com.ytlite.player.data.local.entity.DownloadTaskEntity
import com.ytlite.player.data.local.entity.DownloadTaskStatus
import com.ytlite.player.data.local.entity.DownloadedItemEntity
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.preferences.DownloadPreferences
import com.ytlite.player.data.repository.ExtractionRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class DownloadRepository private constructor(
    private val appContext: Context,
) {
    private val downloadDao = YTLiteDatabase.getInstance(appContext).downloadDao()
    private val preferences = DownloadPreferences.getInstance(appContext)
    private val extractor = ExtractionRepository.getInstance()
    private val downloader = SegmentDownloader()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val scheduleMutex = Mutex()
    private val runningJobs = ConcurrentHashMap<String, Job>()

    fun observeActiveTasks(): Flow<List<DownloadTaskEntity>> = downloadDao.observeActiveTasks()
    fun observeDownloaded(): Flow<List<DownloadedItemEntity>> = downloadDao.observeDownloaded()

    fun observeDownloadedVideoIds(): Flow<Set<String>> =
        downloadDao.observeDownloaded()
            .map { items ->
                items.asSequence()
                    .filter { File(it.filePath).exists() }
                    .map { it.videoId }
                    .toSet()
            }
            .distinctUntilChanged()

    suspend fun enqueue(request: DownloadEnqueueRequest): EnqueueResult = withContext(Dispatchers.IO) {
        val existingDownloaded = downloadDao.findDownloaded(request.videoId, request.format.itag)
        if (existingDownloaded != null && File(existingDownloaded.filePath).exists()) {
            return@withContext EnqueueResult.AlreadyDownloaded(existingDownloaded.id)
        }
        val existingTask = downloadDao.findTaskByVideoAndItag(request.videoId, request.format.itag)
        if (existingTask != null &&
            existingTask.status in setOf(
                DownloadTaskStatus.QUEUED,
                DownloadTaskStatus.RUNNING,
                DownloadTaskStatus.PAUSED,
            )
        ) {
            return@withContext EnqueueResult.AlreadyRunning(existingTask.id)
        }

        if (preferences.peekWifiOnly() && !isOnWifi()) {
            return@withContext EnqueueResult.Error("wifi_only")
        }

        val now = System.currentTimeMillis()
        val finalFile = DownloadPaths.finalFile(
            appContext.filesDir,
            request.videoId,
            request.format.itag,
            request.format.mimeType,
        )
        val task = DownloadTaskEntity(
            id = UUID.randomUUID().toString(),
            videoId = request.videoId,
            title = request.title.ifBlank { request.videoId },
            channelName = request.channelName,
            thumbnailUrl = request.thumbnailUrl,
            itag = request.format.itag,
            mimeType = request.format.mimeType,
            url = request.format.url,
            filePath = finalFile.absolutePath,
            totalBytes = request.format.contentLengthBytes,
            downloadedBytes = 0L,
            status = DownloadTaskStatus.QUEUED,
            createdAt = now,
            updatedAt = now,
            durationSeconds = request.durationSeconds,
        )
        downloadDao.upsertTask(task)
        pumpQueue()
        EnqueueResult.Started(task.id)
    }

    fun pause(taskId: String) {
        scope.launch {
            runningJobs[taskId]?.cancel()
            runningJobs.remove(taskId)
            val task = downloadDao.getTask(taskId) ?: return@launch
            if (task.status == DownloadTaskStatus.RUNNING || task.status == DownloadTaskStatus.QUEUED) {
                downloadDao.updateTask(
                    task.copy(status = DownloadTaskStatus.PAUSED, updatedAt = System.currentTimeMillis()),
                )
            }
            pumpQueue()
        }
    }

    fun resume(taskId: String) {
        scope.launch {
            val task = downloadDao.getTask(taskId) ?: return@launch
            if (task.status == DownloadTaskStatus.PAUSED || task.status == DownloadTaskStatus.FAILED) {
                downloadDao.updateTask(
                    task.copy(
                        status = DownloadTaskStatus.QUEUED,
                        errorMessage = null,
                        updatedAt = System.currentTimeMillis(),
                    ),
                )
                pumpQueue()
            }
        }
    }

    fun cancel(taskId: String) {
        scope.launch {
            runningJobs[taskId]?.cancel()
            runningJobs.remove(taskId)
            val task = downloadDao.getTask(taskId)
            if (task != null) {
                DownloadPaths.partialFile(File(task.filePath)).delete()
                downloadDao.deleteTask(taskId)
            }
            pumpQueue()
        }
    }

    fun retry(taskId: String) = resume(taskId)

    suspend fun deleteDownloaded(itemId: String) = withContext(Dispatchers.IO) {
        val item = downloadDao.getDownloaded(itemId) ?: return@withContext
        File(item.filePath).delete()
        DownloadPaths.partialFile(File(item.filePath)).delete()
        downloadDao.deleteDownloaded(itemId)
        val dir = File(item.filePath).parentFile
        if (dir != null && dir.isDirectory && dir.list().isNullOrEmpty()) {
            dir.delete()
        }
    }

    suspend fun findLocalPath(videoId: String): String? = withContext(Dispatchers.IO) {
        val item = downloadDao.findAnyDownloaded(videoId) ?: return@withContext null
        val file = File(item.filePath)
        if (file.exists()) file.absolutePath else null
    }

    suspend fun hasActiveWork(): Boolean = withContext(Dispatchers.IO) {
        downloadDao.countActiveWork() > 0
    }

    fun pumpQueue() {
        scope.launch {
            scheduleMutex.withLock {
                val running = downloadDao.countRunning()
                val slots = (MAX_CONCURRENT - running).coerceAtLeast(0)
                if (slots > 0) {
                    val runnable = downloadDao.getRunnableTasks()
                        .filter { it.status == DownloadTaskStatus.QUEUED }
                        .take(slots)
                    runnable.forEach { startTask(it) }
                }
                // Only keep / start FGS while there is real work — avoids
                // startForegroundService ↔ stopSelf thrash that can kill the process.
                if (downloadDao.countActiveWork() > 0) {
                    ensureService()
                }
            }
        }
    }

    private fun startTask(task: DownloadTaskEntity) {
        if (runningJobs.containsKey(task.id)) return
        val job = scope.launch {
            try {
                downloadDao.updateTask(
                    task.copy(
                        status = DownloadTaskStatus.RUNNING,
                        updatedAt = System.currentTimeMillis(),
                    ),
                )
                ensureService()
                var working = task
                var attempt = 0
                val lastProgressAt = java.util.concurrent.atomic.AtomicLong(0L)
                while (attempt < 2) {
                    attempt++
                    val result = downloader.download(
                        url = working.url,
                        destination = File(working.filePath),
                        threadCount = preferences.peekThreadCount(),
                        resumeEnabled = preferences.peekResumeEnabled(),
                    ) { progress ->
                        val now = System.currentTimeMillis()
                        val last = lastProgressAt.get()
                        val isComplete = progress.totalBytes > 0 &&
                            progress.downloadedBytes >= progress.totalBytes
                        if (!isComplete && now - last < PROGRESS_THROTTLE_MS) return@download
                        if (!lastProgressAt.compareAndSet(last, now) && !isComplete) return@download
                        scope.launch {
                            val latest = downloadDao.getTask(working.id) ?: return@launch
                            if (latest.status != DownloadTaskStatus.RUNNING) return@launch
                            downloadDao.updateTask(
                                latest.copy(
                                    downloadedBytes = progress.downloadedBytes,
                                    totalBytes = if (progress.totalBytes > 0) {
                                        progress.totalBytes
                                    } else {
                                        latest.totalBytes
                                    },
                                    updatedAt = System.currentTimeMillis(),
                                ),
                            )
                        }
                    }
                    if (result.isSuccess) break
                    val refreshed = refreshUrl(working)
                    if (refreshed == null || attempt >= 2) {
                        val err = result.exceptionOrNull()?.message ?: "download_failed"
                        downloadDao.updateTask(
                            working.copy(
                                status = DownloadTaskStatus.FAILED,
                                errorMessage = err,
                                updatedAt = System.currentTimeMillis(),
                            ),
                        )
                        return@launch
                    }
                    working = refreshed
                    downloadDao.updateTask(working)
                }

                val finished = downloadDao.getTask(working.id) ?: return@launch
                val file = File(finished.filePath)
                val now = System.currentTimeMillis()
                downloadDao.upsertDownloaded(
                    DownloadedItemEntity(
                        id = finished.id,
                        videoId = finished.videoId,
                        title = finished.title,
                        channelName = finished.channelName,
                        thumbnailUrl = finished.thumbnailUrl,
                        itag = finished.itag,
                        mimeType = finished.mimeType,
                        filePath = finished.filePath,
                        contentLength = file.length(),
                        durationSeconds = finished.durationSeconds,
                        completedAt = now,
                    ),
                )
                downloadDao.deleteTask(finished.id)
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                val latest = downloadDao.getTask(task.id)
                if (latest != null && latest.status == DownloadTaskStatus.RUNNING) {
                    downloadDao.updateTask(
                        latest.copy(
                            status = DownloadTaskStatus.PAUSED,
                            updatedAt = System.currentTimeMillis(),
                        ),
                    )
                }
                throw cancelled
            } catch (t: Throwable) {
                Log.w(TAG, "download failed ${task.id}", t)
                val latest = downloadDao.getTask(task.id) ?: return@launch
                downloadDao.updateTask(
                    latest.copy(
                        status = DownloadTaskStatus.FAILED,
                        errorMessage = t.message ?: "error",
                        updatedAt = System.currentTimeMillis(),
                    ),
                )
            } finally {
                runningJobs.remove(task.id)
                pumpQueue()
            }
        }
        runningJobs[task.id] = job
    }

    private suspend fun refreshUrl(task: DownloadTaskEntity): DownloadTaskEntity? {
        return when (val result = extractor.fetchVideoPlayback(task.videoId)) {
            is ExtractionResult.Success -> {
                val format = result.data.formats.firstOrNull { it.itag == task.itag } ?: return null
                task.copy(
                    url = format.url,
                    mimeType = format.mimeType.ifBlank { task.mimeType },
                    totalBytes = format.contentLengthBytes.takeIf { it > 0 } ?: task.totalBytes,
                    updatedAt = System.currentTimeMillis(),
                )
            }
            is ExtractionResult.Error -> null
        }
    }

    private fun ensureService() {
        try {
            val intent = Intent(appContext, DownloadForegroundService::class.java)
            ContextCompat.startForegroundService(appContext, intent)
        } catch (t: Throwable) {
            Log.w(TAG, "ensureService failed", t)
        }
    }

    private fun isOnWifi(): Boolean {
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    companion object {
        private const val TAG = "DownloadRepository"
        private const val MAX_CONCURRENT = 2
        private const val PROGRESS_THROTTLE_MS = 300L

        @Volatile
        private var instance: DownloadRepository? = null

        fun getInstance(context: Context): DownloadRepository =
            instance ?: synchronized(this) {
                instance ?: DownloadRepository(context.applicationContext).also { instance = it }
            }
    }
}
