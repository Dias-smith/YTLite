package com.ytlite.player.data.model

sealed class ExtractionResult<out T> {
    data class Success<T>(val data: T) : ExtractionResult<T>()
    data class Error(
        val message: String,
        val cause: Throwable? = null,
    ) : ExtractionResult<Nothing>()
}
