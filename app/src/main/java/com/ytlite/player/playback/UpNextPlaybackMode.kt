package com.ytlite.player.playback

enum class UpNextPlaybackMode {
    REPEAT_ONE,
    SEQUENTIAL,
    SHUFFLE,
}

fun PlayQueueState.toUpNextPlaybackMode(): UpNextPlaybackMode = when {
    shuffleEnabled -> UpNextPlaybackMode.SHUFFLE
    repeatMode == QueueRepeatMode.ONE -> UpNextPlaybackMode.REPEAT_ONE
    else -> UpNextPlaybackMode.SEQUENTIAL
}
