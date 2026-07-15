package com.ytlite.player.ui.auth

import android.annotation.SuppressLint
import android.os.Build
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.ytlite.player.R
import com.ytlite.player.data.network.YoutubeCookieJar
import com.ytlite.player.data.network.YoutubeCookieSessionStore
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import kotlin.coroutines.resume
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.net.URLEncoder

/**
 * Temporary WebView Google / YouTube login to harvest cookies for InnerTube (History / WL).
 *
 * Important: do **not** intercept http(s) navigations and re-loadUrl them. That converts
 * Google POST/redirect chains into GETs and triggers the "Cookie settings problem" page.
 *
 * @see prd/产品技术文档1.0 §3.4
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun YoutubeWebLoginScreen(
    onSuccess: () -> Unit,
    onDismiss: () -> Unit,
    loginHintEmail: String? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val cookieStore = remember { YoutubeCookieSessionStore.getInstance(context) }
    var progress by remember { mutableFloatStateOf(0f) }
    var pageTitle by remember { mutableStateOf(context.getString(R.string.youtube_web_login_title)) }
    var completed by remember { mutableStateOf(false) }
    var webViewReady by remember { mutableStateOf(false) }
    var webViewRef by remember { mutableStateOf<WebView?>(null) }

    LaunchedEffect(Unit) {
        prepareFreshCookieJar(cookieStore)
        webViewReady = true
    }

    fun finishSuccess() {
        if (completed) return
        completed = true
        YoutubeCookieJar.persistFromWebView()
        YoutubeDiagnostics.d(
            "YoutubeWebLogin",
            "cookie login success jar=${YoutubeCookieJar.debugJarCookieNames()}",
        )
        scope.launch {
            cookieStore.saveFromJar()
            onSuccess()
        }
    }

    fun checkCookiesAndMaybeFinish(url: String?) {
        if (completed) return
        YoutubeCookieJar.syncFromWebView()
        YoutubeDiagnostics.logWebViewRawCookies("YoutubeWebLogin")
        val host = url.orEmpty().lowercase()
        if (host.contains("cookiemismatch") ||
            host.contains("cookie_help") ||
            host.contains("cookiesdisabled")
        ) {
            YoutubeDiagnostics.w("YoutubeWebLogin", "landed on cookie error page url=$url")
            return
        }
        val onYoutube = host.contains("youtube.com") &&
            !host.contains("accounts.google") &&
            !host.contains("accounts.youtube")
        if (onYoutube && YoutubeCookieJar.hasAuthCookies()) {
            finishSuccess()
        }
    }

    BackHandler(onBack = onDismiss)

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = pageTitle,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.player_back),
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onDismiss) {
                        Icon(
                            imageVector = Icons.Filled.Close,
                            contentDescription = stringResource(R.string.youtube_web_login_close),
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            Text(
                text = stringResource(R.string.youtube_web_login_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            if (!webViewReady) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
                return@Column
            }
            if (progress in 0f..<1f) {
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Box(modifier = Modifier.fillMaxSize()) {
                AndroidView(
                    factory = { ctx ->
                        @SuppressLint("SetJavaScriptEnabled")
                        WebView(ctx).apply {
                            layoutParams = ViewGroup.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT,
                            )
                            configureForGoogleLogin(this)

                            webChromeClient = object : WebChromeClient() {
                                override fun onProgressChanged(view: WebView?, newProgress: Int) {
                                    progress = newProgress / 100f
                                }

                                override fun onReceivedTitle(view: WebView?, title: String?) {
                                    if (!title.isNullOrBlank()) {
                                        pageTitle = title
                                    }
                                }
                            }
                            webViewClient = object : WebViewClient() {
                                override fun shouldOverrideUrlLoading(
                                    view: WebView,
                                    request: WebResourceRequest,
                                ): Boolean {
                                    val next = request.url?.toString().orEmpty()
                                    // Only block non-http schemes (intent:, market:, …).
                                    // Never re-loadUrl http(s) — that breaks Google OAuth/cookies.
                                    if (next.startsWith("http://") || next.startsWith("https://")) {
                                        return false
                                    }
                                    YoutubeDiagnostics.d("YoutubeWebLogin", "blocked non-http nav=$next")
                                    return true
                                }

                                override fun onPageFinished(view: WebView?, url: String?) {
                                    checkCookiesAndMaybeFinish(url)
                                }
                            }
                            clearCache(true)
                            clearHistory()
                            loadUrl(buildLoginUrl(loginHintEmail))
                            webViewRef = this
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                    update = { /* keep */ },
                )
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            webViewRef?.apply {
                stopLoading()
                loadUrl("about:blank")
                clearHistory()
                removeAllViews()
                destroy()
            }
            webViewRef = null
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
private fun configureForGoogleLogin(webView: WebView) {
    val cookieManager = CookieManager.getInstance()
    cookieManager.setAcceptCookie(true)
    cookieManager.setAcceptThirdPartyCookies(webView, true)

    val settings = webView.settings
    settings.javaScriptEnabled = true
    settings.domStorageEnabled = true
    settings.databaseEnabled = true
    settings.loadWithOverviewMode = true
    settings.useWideViewPort = true
    settings.javaScriptCanOpenWindowsAutomatically = false
    settings.setSupportMultipleWindows(false)
    settings.cacheMode = WebSettings.LOAD_DEFAULT
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
    }
    settings.userAgentString = browserLikeUserAgent(settings.userAgentString)
    YoutubeDiagnostics.d("YoutubeWebLogin", "ua=${settings.userAgentString}")
}

private suspend fun prepareFreshCookieJar(cookieStore: YoutubeCookieSessionStore) {
    cookieStore.clear()
    YoutubeCookieJar.clear()
    runCatching { WebStorage.getInstance().deleteAllData() }
    val manager = CookieManager.getInstance()
    manager.setAcceptCookie(true)
    suspendCancellableCoroutine { cont ->
        manager.removeAllCookies {
            manager.flush()
            if (cont.isActive) cont.resume(Unit)
        }
    }
    YoutubeDiagnostics.d("YoutubeWebLogin", "cleared WebView cookies/storage for fresh Google login")
}

/**
 * Strip WebView markers (`; wv`) Google uses to treat the client as an embedded WebView.
 */
private fun browserLikeUserAgent(defaultUa: String?): String {
    val raw = defaultUa.orEmpty()
    val cleaned = raw
        .replace("; wv", "")
        .replace("; Version/4.0", "")
        .trim()
    if (cleaned.contains("Chrome/") && cleaned.contains("Mobile")) {
        return cleaned
    }
    // Fallback if the system UA is unusually shaped.
    return "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
}

private fun buildLoginUrl(loginHintEmail: String?): String {
    // Enter via YouTube's own sign-in bounce → accounts.google.com → back to youtube.com.
    // This keeps first-party youtube.com cookies in the redirect chain.
    val next = URLEncoder.encode("https://www.youtube.com/", Charsets.UTF_8.name())
    val base = "https://www.youtube.com/signin" +
        "?action_handle_signin=true" +
        "&app=desktop" +
        "&hl=en" +
        "&next=$next"
    val email = loginHintEmail?.trim().orEmpty()
    return if (email.isNotBlank() && email.contains("@")) {
        val continueUrl = URLEncoder.encode(base, Charsets.UTF_8.name())
        "https://accounts.google.com/v3/signin/identifier" +
            "?continue=$continueUrl" +
            "&service=youtube" +
            "&flowName=GlifWebSignIn" +
            "&flowEntry=ServiceLogin" +
            "&hl=en" +
            "&Email=${URLEncoder.encode(email, Charsets.UTF_8.name())}"
    } else {
        base
    }
}
