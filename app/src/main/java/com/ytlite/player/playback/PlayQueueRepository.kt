package com.ytlite.player.playback

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

data class PlayQueueState(
    val items: List<QueueItem> = emptyList(),
    val currentIndex: Int = 0,
) {
    val currentItem: QueueItem? = items.getOrNull(currentIndex)
    val nextItem: QueueItem? = items.getOrNull(currentIndex + 1)
    val hasNext: Boolean get() = currentIndex + 1 < items.size
}

object PlayQueueRepository {

    private val _state = MutableStateFlow(PlayQueueState())
    val state: StateFlow<PlayQueueState> = _state.asStateFlow()

    fun setQueue(items: List<QueueItem>, startIndex: Int = 0) {
        if (items.isEmpty()) {
            _state.value = PlayQueueState()
            return
        }
        val safeIndex = startIndex.coerceIn(0, items.lastIndex)
        _state.value = PlayQueueState(items = items, currentIndex = safeIndex)
    }

    fun replaceCurrentAndAppend(current: QueueItem, related: List<QueueItem>, maxRelated: Int = 20) {
        val tail = related
            .filter { it.videoId != current.videoId }
            .take(maxRelated)
        setQueue(listOf(current) + tail, startIndex = 0)
    }

    fun append(items: List<QueueItem>) {
        if (items.isEmpty()) return
        _state.update { state ->
            val existingIds = state.items.map { it.videoId }.toSet()
            val newItems = items.filter { it.videoId !in existingIds }
            if (newItems.isEmpty()) return@update state
            state.copy(items = state.items + newItems)
        }
    }

    fun insertNext(item: QueueItem) {
        _state.update { state ->
            if (state.items.any { it.videoId == item.videoId }) return@update state
            val insertAt = (state.currentIndex + 1).coerceAtMost(state.items.size)
            val mutable = state.items.toMutableList()
            mutable.add(insertAt, item)
            state.copy(items = mutable)
        }
    }

    fun addToEnd(item: QueueItem) {
        _state.update { state ->
            if (state.items.any { it.videoId == item.videoId }) return@update state
            state.copy(items = state.items + item)
        }
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
            state.copy(items = mutable, currentIndex = newCurrentIndex.coerceAtLeast(0))
        }
    }

    fun setCurrentIndex(index: Int) {
        _state.update { state ->
            if (index !in state.items.indices) return@update state
            state.copy(currentIndex = index)
        }
    }

    fun updateStreamUrl(videoId: String, streamUrl: String) {
        _state.update { state ->
            state.copy(
                items = state.items.map { item ->
                    if (item.videoId == videoId) item.copy(streamUrl = streamUrl) else item
                },
            )
        }
    }

    fun advanceToNext(): QueueItem? {
        val state = _state.value
        if (!state.hasNext) return null
        val nextIndex = state.currentIndex + 1
        _state.value = state.copy(currentIndex = nextIndex)
        return _state.value.currentItem
    }

    fun skipToPrevious(): QueueItem? {
        val state = _state.value
        if (state.currentIndex <= 0) return null
        val prevIndex = state.currentIndex - 1
        _state.value = state.copy(currentIndex = prevIndex)
        return _state.value.currentItem
    }

    fun clear() {
        _state.value = PlayQueueState()
    }
}
