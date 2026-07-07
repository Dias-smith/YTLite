package com.ytlite.player.data.youtube

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import com.ytlite.player.data.network.YoutubeCookieJar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

@SuppressLint("SetJavaScriptEnabled")
class YoutubeSessionManager private constructor(
    appContext: Context,
) {
    private val context = appContext.applicationContext

    private val _state = MutableStateFlow<YoutubeSessionState>(YoutubeSessionState.Disconnected)
    val state: StateFlow<YoutubeSessionState> = _state.asStateFlow()

    suspend fun bootstrapFromGoogleAccount() = withContext(Dispatchers.IO) {
        _state.value = YoutubeSessionState.Connecting
        runCatching {
            withContext(Dispatchers.Main) {
                suspendCancellableCoroutine { continuation ->
                    val webView = WebView(context)
                    webView.settings.javaScriptEnabled = true
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
                    webView.webViewClient = object : WebViewClient() {
                        override fun onPageFinished(view: WebView?, url: String?) {
                            if (!continuation.isActive) return
                            YoutubeCookieJar.syncFromWebView()
                            webView.destroy()
                            if (YoutubeCookieJar.hasAuthCookies()) {
                                continuation.resume(Unit)
                            } else {
                                continuation.resume(Unit)
                            }
                        }
                    }
                    webView.loadUrl(YOUTUBE_ACCOUNT_URL)
                    continuation.invokeOnCancellation { webView.destroy() }
                }
            }
            YoutubeCookieJar.syncFromWebView()
            if (YoutubeCookieJar.hasAuthCookies()) {
                _state.value = YoutubeSessionState.Ready
            } else {
                _state.value = YoutubeSessionState.Error("未获取到 YouTube 登录 Cookie，请确保设备已登录同一 Google 账号")
            }
        }.onFailure { error ->
            _state.value = YoutubeSessionState.Error(
                error.message ?: "YouTube 会话初始化失败",
            )
        }
    }

    fun disconnect() {
        YoutubeCookieJar.clear()
        _state.value = YoutubeSessionState.Disconnected
    }

    companion object {
        private const val YOUTUBE_ACCOUNT_URL = "https://www.youtube.com/feed/library"

        @Volatile
        private var instance: YoutubeSessionManager? = null

        fun getInstance(context: Context): YoutubeSessionManager =
            instance ?: synchronized(this) {
                instance ?: YoutubeSessionManager(context.applicationContext).also { instance = it }
            }
    }
}
