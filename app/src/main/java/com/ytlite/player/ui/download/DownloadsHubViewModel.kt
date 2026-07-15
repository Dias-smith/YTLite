package com.ytlite.player.ui.download

import android.app.Application
import android.net.Uri
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.local.entity.DownloadTaskEntity
import com.ytlite.player.data.local.entity.DownloadedItemEntity
import com.ytlite.player.download.DownloadRepository
import com.ytlite.player.playback.QueueItem
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File

@Immutable
data class DownloadsHubUiState(
    val tasks: List<DownloadTaskEntity> = emptyList(),
    val downloaded: List<DownloadedItemEntity> = emptyList(),
)

class DownloadsHubViewModel(
    private val downloadRepository: DownloadRepository,
) : ViewModel() {

    val uiState: StateFlow<DownloadsHubUiState> = combine(
        downloadRepository.observeActiveTasks(),
        downloadRepository.observeDownloaded(),
    ) { tasks, downloaded ->
        DownloadsHubUiState(tasks = tasks, downloaded = downloaded)
    }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        DownloadsHubUiState(),
    )

    fun pause(taskId: String) = downloadRepository.pause(taskId)
    fun resume(taskId: String) = downloadRepository.resume(taskId)
    fun cancel(taskId: String) = downloadRepository.cancel(taskId)
    fun retry(taskId: String) = downloadRepository.retry(taskId)

    fun deleteDownloaded(itemId: String) {
        viewModelScope.launch {
            downloadRepository.deleteDownloaded(itemId)
        }
    }

    fun downloadedToQueue(items: List<DownloadedItemEntity>, startIndex: Int): List<QueueItem> =
        items.map { it.toQueueItem() }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                DownloadsHubViewModel(DownloadRepository.getInstance(application))
            }
        }
    }
}

fun DownloadedItemEntity.toQueueItem(): QueueItem {
    val fileUri = Uri.fromFile(File(filePath)).toString()
    val durationText = durationSeconds.takeIf { it > 0 }?.let { sec ->
        val m = sec / 60
        val s = sec % 60
        "%d:%02d".format(m, s)
    }
    return QueueItem(
        videoId = videoId,
        title = title,
        channelName = channelName,
        thumbnailUrl = thumbnailUrl.orEmpty(),
        streamUrl = fileUri,
        durationText = durationText,
        itag = itag,
    )
}
