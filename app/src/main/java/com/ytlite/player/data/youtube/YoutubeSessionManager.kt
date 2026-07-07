package com.ytlite.player.data.youtube

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.network.YoutubeCookieJar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

@SuppressLint("SetJavaScriptEnabled")
class YoutubeSessionManager private constructor(
    appContext: Context,
) {
    private val context = appContext.applicationContext
    private val authRepository = AuthRepository.getInstance(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bootstrapMutex = Mutex()

    private val _state = MutableStateFlow<YoutubeSessionState>(YoutubeSessionState.Disconnected)
    val state: StateFlow<YoutubeSessionState> = _state.asStateFlow()

    private val _loginUiState = MutableStateFlow<YoutubeLoginUiState?>(null)
    val loginUiState: StateFlow<YoutubeLoginUiState?> = _loginUiState.asStateFlow()

    private var activeContinuation: kotlinx.coroutines.CancellableContinuation<Boolean>? = null
    private var attachedWebView: WebView? = null
    private var phase = BootstrapPhase.GOOGLE_LOGIN
    private var youtubeLoadRequested = false
    private var exchangeFinished = false

    suspend fun bootstrapFromGoogleAccount() = bootstrapMutex.withLock {
        withContext(Dispatchers.IO) {
            YoutubeDiagnostics.d("Session", "bootstrapFromGoogleAccount start state=${_state.value}")
            YoutubeCookieJar.syncFromWebView()
            YoutubeDiagnostics.logCookieJarState("bootstrap/pre-check")
            YoutubeDiagnostics.logWebViewRawCookies("bootstrap/pre-check")
            if (YoutubeCookieJar.hasAuthCookies()) {
                YoutubeDiagnostics.d("Session", "bootstrap skipped: cookies already present")
                _state.value = YoutubeSessionState.Ready
                authRepository.notifyYoutubeCookiesReady()
                return@withContext
            }

            val email = currentUserEmail()
            val loginUrl = buildLoginUrl(email)
            _state.value = YoutubeSessionState.AwaitingInteractiveLogin
            _loginUiState.value = YoutubeLoginUiState(
                initialUrl = loginUrl,
                emailHint = email,
            )
            YoutubeDiagnostics.d(
                "Session",
                "starting interactive WebView cookie exchange timeout=${BOOTSTRAP_TIMEOUT_MS}ms url=$loginUrl",
            )

            runCatching {
                val success = withTimeoutOrNull(BOOTSTRAP_TIMEOUT_MS) {
                    suspendCancellableCoroutine { continuation ->
                        resetExchangeState()
                        activeContinuation = continuation
                        continuation.invokeOnCancellation {
                            YoutubeDiagnostics.w("WebView", "cookie exchange cancelled")
                            finishExchange(success = false, userCancelled = true)
                        }
                    }
                } ?: false

                _loginUiState.value = null
                YoutubeDiagnostics.d("Session", "WebView exchange finished success=$success timedOut=${!success}")
                YoutubeCookieJar.persistFromWebView()
                YoutubeDiagnostics.logCookieJarState("bootstrap/post-webview")
                YoutubeDiagnostics.logWebViewRawCookies("bootstrap/post-webview")
                if (success && YoutubeCookieJar.hasYoutubeApiSidCookie()) {
                    YoutubeDiagnostics.d("Session", "bootstrap success: __Secure-3PAPISID present")
                    _state.value = YoutubeSessionState.Ready
                    authRepository.notifyYoutubeCookiesReady()
                } else if (success && YoutubeCookieJar.hasAuthCookies()) {
                    YoutubeDiagnostics.w("Session", "bootstrap partial: hasAuthCookies but missing __Secure-3PAPISID")
                    _state.value = YoutubeSessionState.Ready
                    authRepository.notifyYoutubeCookiesReady()
                } else {
                    YoutubeDiagnostics.e(
                        "Session",
                        "bootstrap failed: success=$success " +
                            "apiSid=${YoutubeCookieJar.hasYoutubeApiSidCookie()} " +
                            "hasAuth=${YoutubeCookieJar.hasAuthCookies()} " +
                            "googleAuth=${YoutubeCookieJar.hasGoogleAuthCookies()} " +
                            "ytSession=${YoutubeCookieJar.hasYoutubeSessionCookies()}",
                    )
                    _state.value = YoutubeSessionState.Error(
                        "未获取到 YouTube 登录 Cookie，请确保使用同一 Google 账号完成授权",
                    )
                }
            }.onFailure { error ->
                _loginUiState.value = null
                YoutubeDiagnostics.e("Session", "bootstrap exception: ${error.message}", error)
                _state.value = YoutubeSessionState.Error(
                    error.message ?: "YouTube 会话初始化失败",
                )
            }
        }
    }

    /**
     * Called from the visible login sheet when its WebView is created.
     * Must run on the main thread.
     */
    fun attachWebView(webView: WebView) {
        mainHandler.post {
            if (_loginUiState.value == null || exchangeFinished) return@post
            YoutubeDiagnostics.d("WebView", "attachWebView")
            attachedWebView = webView
            _state.value = YoutubeSessionState.Connecting

            val cookieManager = CookieManager.getInstance()
            cookieManager.setAcceptCookie(true)
            cookieManager.setAcceptThirdPartyCookies(webView, true)

            webView.settings.javaScriptEnabled = true
            webView.settings.domStorageEnabled = true

            webView.webViewClient = createWebViewClient(webView)

            val url = _loginUiState.value?.initialUrl ?: buildLoginUrl(currentUserEmail())
            YoutubeDiagnostics.d("WebView", "loadUrl start=$url")
            webView.loadUrl(url)
        }
    }

    fun detachWebView() {
        mainHandler.post {
            attachedWebView = null
        }
    }

    fun cancelInteractiveLogin() {
        mainHandler.post {
            YoutubeDiagnostics.d("WebView", "cancelInteractiveLogin")
            finishExchange(success = false, userCancelled = true)
        }
    }

    fun disconnect() {
        finishExchange(success = false, userCancelled = true)
        YoutubeCookieJar.clear()
        _loginUiState.value = null
        _state.value = YoutubeSessionState.Disconnected
    }

    fun markReadyIfCookiesPresent() {
        YoutubeCookieJar.syncFromWebView()
        if (YoutubeCookieJar.hasAuthCookies()) {
            _state.value = YoutubeSessionState.Ready
        }
    }

    private fun createWebViewClient(webView: WebView): WebViewClient =
        object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                YoutubeDiagnostics.d("WebView", "onPageStarted phase=$phase url=$url")
                if (phase == BootstrapPhase.GOOGLE_LOGIN && isGoogleLoginComplete(url)) {
                    YoutubeDiagnostics.d("WebView", "onPageStarted: google login complete")
                    requestYoutubeExchange(view)
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                YoutubeDiagnostics.d(
                    "WebView",
                    "onPageFinished phase=$phase url=$url " +
                        "apiSid=${YoutubeCookieJar.hasYoutubeApiSidCookie()}",
                )
                handlePageEvent(url, view)
                if (phase == BootstrapPhase.YOUTUBE_EXCHANGE &&
                    isYoutubeUrl(url) &&
                    YoutubeCookieJar.hasYoutubeApiSidCookie()
                ) {
                    phase = BootstrapPhase.DONE
                    finishExchange(success = true)
                }
            }
        }

    private fun handlePageEvent(url: String?, view: WebView?) {
        YoutubeDiagnostics.d("WebView", "handlePageEvent phase=$phase url=$url")
        YoutubeCookieJar.syncFromWebView()
        YoutubeDiagnostics.logCookieJarState("webview/page-event")

        when (phase) {
            BootstrapPhase.GOOGLE_LOGIN -> {
                if (isGoogleLoginComplete(url)) {
                    requestYoutubeExchange(view)
                }
            }
            BootstrapPhase.YOUTUBE_EXCHANGE -> {
                if (isYoutubeUrl(url) && YoutubeCookieJar.hasYoutubeApiSidCookie()) {
                    phase = BootstrapPhase.DONE
                    finishExchange(success = true)
                }
            }
            BootstrapPhase.DONE -> Unit
        }
    }

    private fun requestYoutubeExchange(view: WebView?) {
        if (youtubeLoadRequested) return
        youtubeLoadRequested = true
        phase = BootstrapPhase.YOUTUBE_EXCHANGE
        YoutubeDiagnostics.d("WebView", "google login detected, loading $YOUTUBE_MOBILE_URL")
        YoutubeDiagnostics.logCookieJarState("webview/pre-youtube")
        view?.loadUrl(YOUTUBE_MOBILE_URL)
    }

    private fun finishExchange(success: Boolean, userCancelled: Boolean = false) {
        if (exchangeFinished) return
        exchangeFinished = true

        val webView = attachedWebView
        attachedWebView = null
        if (webView != null) {
            webView.stopLoading()
            webView.destroy()
        }

        val continuation = activeContinuation
        activeContinuation = null
        if (continuation != null && continuation.isActive) {
            continuation.resume(success)
        }

        if (userCancelled && !success && _state.value !is YoutubeSessionState.Ready) {
            _loginUiState.value = null
            _state.value = YoutubeSessionState.Error("YouTube 账号连接已取消")
        }
    }

    private fun resetExchangeState() {
        exchangeFinished = false
        phase = BootstrapPhase.GOOGLE_LOGIN
        youtubeLoadRequested = false
        attachedWebView = null
    }

    private fun currentUserEmail(): String? =
        (authRepository.currentSession() as? UserSession.Authenticated)?.profile?.email

    private fun buildLoginUrl(email: String?): String {
        val builder = Uri.parse(GOOGLE_LOGIN_BASE).buildUpon()
            .appendQueryParameter("service", "youtube")
            .appendQueryParameter("uilel", "3")
            .appendQueryParameter("continue", YOUTUBE_MOBILE_URL)
        if (!email.isNullOrBlank()) {
            builder.appendQueryParameter("Email", email)
        }
        return builder.build().toString()
    }

    private fun isGoogleLoginComplete(url: String?): Boolean {
        if (url.isNullOrBlank() || !url.contains("google.com")) return false
        if (url.contains("/signin/") && !YoutubeCookieJar.hasGoogleAuthCookies()) {
            YoutubeDiagnostics.d("WebView", "isGoogleLoginComplete=false still on signin url=$url")
            return false
        }
        YoutubeCookieJar.syncFromWebView()
        val complete = YoutubeCookieJar.hasGoogleAuthCookies()
        YoutubeDiagnostics.d("WebView", "isGoogleLoginComplete=$complete url=$url")
        return complete
    }

    private fun isYoutubeUrl(url: String?): Boolean =
        url != null && url.contains("youtube.com")

    private enum class BootstrapPhase {
        GOOGLE_LOGIN,
        YOUTUBE_EXCHANGE,
        DONE,
    }

    companion object {
        private const val BOOTSTRAP_TIMEOUT_MS = 300_000L

        private const val GOOGLE_LOGIN_BASE = "https://accounts.google.com/ServiceLogin"
        private const val YOUTUBE_MOBILE_URL = "https://m.youtube.com"

        @Volatile
        private var instance: YoutubeSessionManager? = null

        fun getInstance(context: Context): YoutubeSessionManager =
            instance ?: synchronized(this) {
                instance ?: YoutubeSessionManager(context.applicationContext).also { instance = it }
            }
    }
}
