package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
data class StreamFormat(
    val itag: Int,
    val width: Int,
    val height: Int,
    val hasAudio: Boolean,
    val hasVideo: Boolean,
    val url: String,
    val mimeType: String = "",
)
