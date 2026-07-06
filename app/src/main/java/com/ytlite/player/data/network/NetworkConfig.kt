package com.ytlite.player.data.network

object NetworkConfig {
    const val HOME_SEARCH_QUERY = "music"

    const val CONNECT_TIMEOUT_SEC = 15L
    const val READ_TIMEOUT_SEC = 30L
    const val WRITE_TIMEOUT_SEC = 15L
}

data class HttpResult(
    val success: Boolean,
    val result: String?,
    val errCode: Int,
    val errMsg: String,
)
