package com.ytlite.player.playback

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlin.random.Random

enum class QueueRepeatMode {
    OFF,
    ONE,
    ALL,
}

data class PlayQueueState(
    val items: List<QueueItem> = emptyList(),
    val currentIndex: Int = 0,
    val repeatMode: QueueRepeatMode = QueueRepeatMode.OFF,
    val shuffleEnabled: Boolean = false,
    val sourcePlaylistId: String? = null,
) {
    val currentItem: QueueItem? = items.getOrNull(currentIndex)
    val nextItem: QueueItem? = items.getOrNull(currentIndex + 1)
    val hasNext: Boolean get() = currentIndex + 1 < items.size
    val hasPrevious: Boolean get() = currentIndex > 0
}

object PlayQueueRepository {

    private val _state = MutableStateFlow(PlayQueueState())
    val state: StateFlow<PlayQueueState> = _state.asStateFlow()

    private var originalOrder: List<QueueItem>? = null

    fun setQueue(
        items: List<QueueItem>,
        startIndex: Int = 0,
        sourcePlaylistId: String? = null,
        preservePlaybackMode: Boolean = false,
        clearSourcePlaylist: Boolean = false,
    ) {
        val preserved = _state.value
        if (items.isEmpty()) {
            _state.value = if (preservePlaybackMode) {
                PlayQueueState(
                    repeatMode = preserved.repeatMode,
                    shuffleEnabled = preserved.shuffleEnabled,
                    sourcePlaylistId = if (clearSourcePlaylist) null else preserved.sourcePlaylistId,
                )
            } else {
                PlayQueueState()
            }
            originalOrder = null
            return
        }
        val safeIndex = startIndex.coerceIn(0, items.lastIndex)
        originalOrder = items
        _state.value = PlayQueueState(
            items = items,
            currentIndex = safeIndex,
            sourcePlaylistId = when {
                clearSourcePlaylist -> null
                else -> sourcePlaylistId ?: preserved.sourcePlaylistId
            },
            repeatMode = if (preservePlaybackMode) preserved.repeatMode else QueueRepeatMode.OFF,
            shuffleEnabled = if (preservePlaybackMode) preserved.shuffleEnabled else false,
        )
    }

    fun clearSourcePlaylistId() {
        _state.update { it.copy(sourcePlaylistId = null) }
    }

    fun replaceCurrentAndAppend(
        current: QueueItem,
        related: List<QueueItem>,
        maxRelated: Int = 20,
        clearSourcePlaylist: Boolean = false,
    ) {
        val mode = _state.value.toUpNextPlaybackMode()
        val tail = related
            .filter { it.videoId != current.videoId }
            .distinctBy { it.videoId }
            .take(maxRelated)
        // Current track is always index 0; recommendations follow.
        val items = listOf(current) + tail
        setQueue(
            items = items,
            startIndex = 0,
            preservePlaybackMode = true,
            clearSourcePlaylist = clearSourcePlaylist,
        )
        applyUpNextPlaybackMode(mode)
        // Re-assert current is first after mode apply (shuffle keeps current at head).
        _state.update { state ->
            val head = state.items.firstOrNull { it.videoId == current.videoId } ?: current
            val rest = state.items.filter { it.videoId != current.videoId }
            state.copy(
                items = listOf(head) + rest,
                currentIndex = 0,
                sourcePlaylistId = if (clearSourcePlaylist) null else state.sourcePlaylistId,
            )
        }
    }

    fun append(items: List<QueueItem>) {
        if (items.isEmpty()) return
        _state.update { state ->
            val existingIds = state.items.map { it.videoId }.toSet()
            val newItems = items.filter { it.videoId !in existingIds }
            if (newItems.isEmpty()) return@update state
            val merged = if (state.shuffleEnabled) {
                insertShuffled(state.items, newItems)
            } else {
                state.items + newItems
            }
            originalOrder = (originalOrder ?: state.items) + newItems
            state.copy(items = merged)
        }
    }

    fun insertNext(item: QueueItem) {
        _state.update { state ->
            if (state.items.any { it.videoId == item.videoId }) return@update state
            val insertAt = (state.currentIndex + 1).coerceAtMost(state.items.size)
            val mutable = state.items.toMutableList()
            mutable.add(insertAt, item)
            originalOrder = (originalOrder ?: state.items).toMutableList().apply {
                val origInsert = (state.currentIndex + 1).coerceAtMost(size)
                add(origInsert, item)
            }
            state.copy(items = mutable)
        }
    }

    fun addToEnd(item: QueueItem) {
        append(listOf(item))
    }

    fun removeItem(videoId: String): Boolean {
        var removed = false
        _state.update { state ->
            val index = state.items.indexOfFirst { it.videoId == videoId }
            if (index < 0) return@update state
            removed = true
            val mutable = state.items.toMutableList()
            mutable.removeAt(index)
            originalOrder = originalOrder?.filter { it.videoId != videoId }
            if (mutable.isEmpty()) {
                return@update PlayQueueState(
                    repeatMode = state.repeatMode,
                    shuffleEnabled = state.shuffleEnabled,
                    sourcePlaylistId = state.sourcePlaylistId,
                )
            }
            val currentId = state.currentItem?.videoId
            val newIndex = when {
                currentId == videoId -> index.coerceAtMost(mutable.lastIndex)
                index < state.currentIndex -> state.currentIndex - 1
                else -> state.currentIndex
            }
            state.copy(items = mutable, currentIndex = newIndex.coerceIn(0, mutable.lastIndex))
        }
        return removed
    }

    fun moveItem(fromIndex: Int, toIndex: Int) {
        _state.update { state ->
            if (fromIndex !in state.items.indices || toIndex !in state.items.indices) return@update state
            if (fromIndex == toIndex) return@update state
            val mutable = state.items.toMutableList()
            val item = mutable.removeAt(fromIndex)
            mutable.add(toIndex, item)
            val currentId = state.currentItem?.videoId
            val newCurrentIndex = currentId?.let { id -> mutable.indexOfFirst { it.videoId == id } } ?: state.currentIndex
            if (!state.shuffleEnabled) {
                originalOrder = mutable.toList()
            }
            state.copy(items = mutable, currentIndex = newCurrentIndex.coerceAtLeast(0))
        }
    }

    fun setCurrentIndex(index: Int) {
        _state.update { state ->
            if (index !in state.items.indices) return@update state
            state.copy(currentIndex = index)
        }
    }

    fun updateStreamUrl(videoId: String, streamUrl: String, itag: Int? = null) {
        _state.update { state ->
            val updated = state.items.map { item ->
                if (item.videoId == videoId) {
                    item.copy(streamUrl = streamUrl, itag = itag ?: item.itag)
                } else {
                    item
                }
            }
            originalOrder = originalOrder?.map { item ->
                if (item.videoId == videoId) {
                    item.copy(streamUrl = streamUrl, itag = itag ?: item.itag)
                } else {
                    item
                }
            }
            state.copy(items = updated)
        }
    }

    fun cycleRepeatMode(): QueueRepeatMode {
        var next = QueueRepeatMode.OFF
        _state.update { state ->
            next = when (state.repeatMode) {
                QueueRepeatMode.OFF -> QueueRepeatMode.ALL
                QueueRepeatMode.ALL -> QueueRepeatMode.ONE
                QueueRepeatMode.ONE -> QueueRepeatMode.OFF
            }
            state.copy(repeatMode = next)
        }
        return next
    }

    fun setRepeatMode(mode: QueueRepeatMode) {
        _state.update { it.copy(repeatMode = mode) }
    }

    fun setShuffleEnabled(enabled: Boolean) {
        if (_state.value.shuffleEnabled == enabled) return
        toggleShuffle()
    }

    fun applyUpNextPlaybackMode(mode: UpNextPlaybackMode) {
        when (mode) {
            UpNextPlaybackMode.REPEAT_ONE -> {
                if (_state.value.shuffleEnabled) setShuffleEnabled(false)
                setRepeatMode(QueueRepeatMode.ONE)
            }
            UpNextPlaybackMode.SEQUENTIAL -> {
                if (_state.value.shuffleEnabled) setShuffleEnabled(false)
                setRepeatMode(QueueRepeatMode.ALL)
            }
            UpNextPlaybackMode.SHUFFLE -> {
                setRepeatMode(QueueRepeatMode.OFF)
                if (!_state.value.shuffleEnabled) setShuffleEnabled(true)
            }
        }
    }

    fun toggleShuffle(): Boolean {
        var enabled = false
        _state.update { state ->
            enabled = !state.shuffleEnabled
            if (enabled) {
                originalOrder = originalOrder ?: state.items
                val current = state.currentItem
                val tail = state.items.filter { it.videoId != current?.videoId }.shuffled(Random.Default)
                val shuffled = listOfNotNull(current) + tail
                state.copy(items = shuffled, shuffleEnabled = true, currentIndex = 0)
            } else {
                val restored = originalOrder ?: state.items
                val currentId = state.currentItem?.videoId
                val newIndex = currentId?.let { id -> restored.indexOfFirst { it.videoId == id } } ?: 0
                state.copy(
                    items = restored,
                    shuffleEnabled = false,
                    currentIndex = newIndex.coerceIn(0, restored.lastIndex.coerceAtLeast(0)),
                )
            }
        }
        return enabled
    }

    fun advanceToNext(): QueueItem? {
        val state = _state.value
        if (state.repeatMode == QueueRepeatMode.ONE) {
            return state.currentItem
        }
        if (!state.hasNext) {
            if (state.repeatMode == QueueRepeatMode.ALL && state.items.isNotEmpty()) {
                _state.value = state.copy(currentIndex = 0)
                return _state.value.currentItem
            }
            return null
        }
        val nextIndex = state.currentIndex + 1
        _state.value = state.copy(currentIndex = nextIndex)
        return _state.value.currentItem
    }

    fun skipToPrevious(): QueueItem? {
        val state = _state.value
        if (state.currentIndex > 0) {
            val prevIndex = state.currentIndex - 1
            _state.value = state.copy(currentIndex = prevIndex)
            return _state.value.currentItem
        }
        if (state.repeatMode == QueueRepeatMode.ALL && state.items.isNotEmpty()) {
            _state.value = state.copy(currentIndex = state.items.lastIndex)
            return _state.value.currentItem
        }
        return null
    }

    fun clear() {
        _state.value = PlayQueueState()
        originalOrder = null
    }

    fun updateItemMetadata(
        videoId: String,
        title: String,
        channelName: String,
        thumbnailUrl: String,
        album: String? = null,
        year: String? = null,
    ) {
        _state.update { state ->
            val updated = state.items.map { item ->
                if (item.videoId != videoId) item else {
                    item.copy(
                        title = title,
                        channelName = channelName,
                        thumbnailUrl = thumbnailUrl,
                        album = album,
                        year = year,
                    )
                }
            }
            originalOrder = originalOrder?.map { item ->
                if (item.videoId != videoId) item else {
                    item.copy(
                        title = title,
                        channelName = channelName,
                        thumbnailUrl = thumbnailUrl,
                        album = album,
                        year = year,
                    )
                }
            }
            state.copy(items = updated)
        }
    }

    private fun insertShuffled(existing: List<QueueItem>, newItems: List<QueueItem>): List<QueueItem> {
        val mutable = existing.toMutableList()
        newItems.shuffled(Random.Default).forEach { item ->
            val insertAt = if (mutable.isEmpty()) 0 else Random.nextInt(mutable.size + 1)
            mutable.add(insertAt, item)
        }
        return mutable
    }
}
