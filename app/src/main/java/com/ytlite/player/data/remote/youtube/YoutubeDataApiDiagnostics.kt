package com.ytlite.player.data.remote.youtube

import com.ytlite.player.data.network.HttpResult
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import org.json.JSONObject

internal object YoutubeDataApiDiagnostics {

    fun logHttpFailure(endpoint: String, result: HttpResult) {
        val bodySnippet = result.result?.take(500).orEmpty()
        val errorReason = parseErrorReason(result.result)
        YoutubeDiagnostics.w(
            "DataApi",
            "$endpoint failed code=${result.errCode} reason=$errorReason body=$bodySnippet",
        )
    }

    private fun parseErrorReason(body: String?): String? {
        if (body.isNullOrBlank()) return null
        return runCatching {
            val json = JSONObject(body)
            val error = json.optJSONObject("error") ?: return@runCatching null
            val errors = error.optJSONArray("errors")
            if (errors != null && errors.length() > 0) {
                val first = errors.optJSONObject(0)
                listOfNotNull(
                    first?.optString("reason")?.takeIf { it.isNotBlank() },
                    first?.optString("message")?.takeIf { it.isNotBlank() },
                ).joinToString(": ")
            } else {
                error.optString("message").takeIf { it.isNotBlank() }
            }
        }.getOrNull()
    }
}
