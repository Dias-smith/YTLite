package com.ytlite.player.data.network

import okhttp3.Call
import okhttp3.Dispatcher
import okhttp3.EventListener
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.ByteArrayInputStream
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.zip.GZIPInputStream
import com.ytlite.player.data.youtube.YoutubeDiagnostics

/**
 * Shared OkHttp client used by the JS extractor native HTTP bridge and Data API / InnerTube.
 */
class YouTubeHttpClient {

    private val slowCallThresholdMs = 3_000L
    private val callStartNanos = ConcurrentHashMap<Call, Long>()

    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .cookieJar(YoutubeCookieJar)
        .dispatcher(
            Dispatcher().apply {
                maxRequests = MAX_REQUESTS
                maxRequestsPerHost = MAX_REQUESTS_PER_HOST
            },
        )
        .eventListenerFactory {
            object : EventListener() {
                override fun callStart(call: Call) {
                    callStartNanos[call] = System.nanoTime()
                }

                override fun callEnd(call: Call) {
                    logIfSlow(call, null)
                }

                override fun callFailed(call: Call, ioe: IOException) {
                    logIfSlow(call, ioe)
                }

                private fun logIfSlow(call: Call, error: IOException?) {
                    val started = callStartNanos.remove(call) ?: return
                    val elapsedMs = (System.nanoTime() - started) / 1_000_000L
                    if (elapsedMs < slowCallThresholdMs && error == null) return
                    val host = call.request().url.host
                    YoutubeDiagnostics.w(
                        "Http",
                        "call host=$host elapsedMs=$elapsedMs err=${error?.message}",
                    )
                }
            }
        }
        .connectTimeout(NetworkConfig.CONNECT_TIMEOUT_SEC, TimeUnit.SECONDS)
        .readTimeout(NetworkConfig.READ_TIMEOUT_SEC, TimeUnit.SECONDS)
        .writeTimeout(NetworkConfig.WRITE_TIMEOUT_SEC, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    fun request(
        url: String,
        method: String,
        headers: Map<String, String>,
        body: String?,
    ): HttpResult {
        return try {
            val requestBuilder = Request.Builder().url(url)
            headers.forEach { (key, value) ->
                if (key.isNotBlank() && value.isNotBlank()) {
                    requestBuilder.header(key, value)
                }
            }

            when (method.uppercase()) {
                "GET" -> requestBuilder.get()
                "POST" -> {
                    val contentType = headers.entries
                        .firstOrNull { it.key.equals("content-type", ignoreCase = true) }
                        ?.value
                        ?.substringBefore(";")
                        ?.trim()
                        ?: "application/json"
                    val mediaType = contentType.toMediaType()
                    val requestBody = (body ?: "").toRequestBody(mediaType)
                    requestBuilder.post(requestBody)
                }
                else -> requestBuilder.method(method.uppercase(), null)
            }

            httpClient.newCall(requestBuilder.build()).execute().use { response ->
                val rawBytes = response.body?.bytes() ?: ByteArray(0)
                val decodedBytes = decompressIfNeeded(
                    data = rawBytes,
                    contentEncoding = response.header("Content-Encoding"),
                )
                val responseBody = stripYouTubeJsonPrefix(String(decodedBytes, Charsets.UTF_8))
                if (response.isSuccessful) {
                    HttpResult(
                        success = true,
                        result = responseBody,
                        errCode = 0,
                        errMsg = "",
                    )
                } else {
                    HttpResult(
                        success = false,
                        result = responseBody,
                        errCode = response.code,
                        errMsg = "HTTP ${response.code}",
                    )
                }
            }
        } catch (e: Exception) {
            HttpResult(
                success = false,
                result = null,
                errCode = -1,
                errMsg = e.message ?: "Network error",
            )
        }
    }

    private fun decompressIfNeeded(data: ByteArray, contentEncoding: String?): ByteArray {
        if (data.isEmpty()) return data
        val isGzip = contentEncoding?.contains("gzip", ignoreCase = true) == true ||
            (data.size >= 2 && data[0] == GZIP_MAGIC_FIRST && data[1] == GZIP_MAGIC_SECOND)
        if (!isGzip) return data
        return GZIPInputStream(ByteArrayInputStream(data)).use { input ->
            input.readBytes()
        }
    }

    private fun stripYouTubeJsonPrefix(body: String): String {
        val trimmed = body.trimStart()
        if (trimmed.startsWith(")]}'")) {
            return trimmed.removePrefix(")]}'").trimStart()
        }
        return body
    }

    companion object {
        private const val GZIP_MAGIC_FIRST: Byte = 0x1f
        private const val GZIP_MAGIC_SECOND: Byte = 0x8b.toByte()
        private const val MAX_REQUESTS = 64
        private const val MAX_REQUESTS_PER_HOST = 8

        @Volatile
        private var instance: YouTubeHttpClient? = null

        fun getInstance(): YouTubeHttpClient =
            instance ?: synchronized(this) {
                instance ?: YouTubeHttpClient().also { instance = it }
            }
    }
}

class YouTubeNetworkException(message: String, cause: Throwable? = null) :
    Exception(message, cause)
