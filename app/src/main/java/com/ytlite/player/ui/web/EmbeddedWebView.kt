package com.ytlite.player.ui.web

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView

private class PageScriptsHolder {
    @Volatile
    var scripts: List<String> = emptyList()
}

/** Named bridge object for [WebView.addJavascriptInterface]. */
class WebViewJsBridge(
    private val onPauseAppMusic: () -> Unit = {},
    private val onAllowAutoplay: (() -> Unit)? = null,
) {
    private val mainHandler = Handler(Looper.getMainLooper())

    @JavascriptInterface
    fun pauseAppMusic() {
        mainHandler.post { onPauseAppMusic() }
    }

    @JavascriptInterface
    fun allowAutoplay() {
        mainHandler.post { onAllowAutoplay?.invoke() }
    }
}

/** Handle for evaluating JS / tweaking media settings after the WebView is created. */
class EmbeddedWebViewHandle {
    @Volatile
    var webView: WebView? = null
        internal set

    private val mainHandler = Handler(Looper.getMainLooper())

    private inline fun runOnMain(crossinline block: (WebView) -> Unit) {
        val target = webView ?: return
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block(target)
        } else {
            mainHandler.post { webView?.let(block) }
        }
    }

    fun evaluateJavascript(script: String) {
        runOnMain { it.evaluateJavascript(script, null) }
    }

    fun setMediaPlaybackRequiresUserGesture(required: Boolean) {
        runOnMain { it.settings.mediaPlaybackRequiresUserGesture = required }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun EmbeddedWebView(
    url: String,
    modifier: Modifier = Modifier,
    pageScripts: List<String> = emptyList(),
    showLoadingIndicator: Boolean = true,
    jsBridgeName: String? = null,
    jsBridge: Any? = null,
    handle: EmbeddedWebViewHandle? = null,
    mediaPlaybackRequiresUserGesture: Boolean = false,
) {
    val context = LocalContext.current
    val scriptsHolder = remember { PageScriptsHolder() }
    SideEffect {
        scriptsHolder.scripts = pageScripts
    }

    var isLoading by remember(url) { mutableStateOf(true) }
    val loadingCallback = remember {
        object {
            var onLoadingChanged: (Boolean) -> Unit = {}
        }
    }
    loadingCallback.onLoadingChanged = { loading -> isLoading = loading }

    val webView = remember {
        WebView(context).apply {
            setBackgroundColor(AndroidColor.BLACK)
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                this.mediaPlaybackRequiresUserGesture = mediaPlaybackRequiresUserGesture
                loadWithOverviewMode = true
                useWideViewPort = true
            }
            if (jsBridgeName != null && jsBridge != null) {
                addJavascriptInterface(jsBridge, jsBridgeName)
            }
            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView?, startedUrl: String?, favicon: android.graphics.Bitmap?) {
                    super.onPageStarted(view, startedUrl, favicon)
                    loadingCallback.onLoadingChanged(true)
                }

                override fun onPageFinished(view: WebView?, finishedUrl: String?) {
                    super.onPageFinished(view, finishedUrl)
                    val target = view ?: return
                    scriptsHolder.scripts.forEach { script ->
                        if (script.isNotBlank()) {
                            target.evaluateJavascript(script, null)
                        }
                    }
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onProgressChanged(view: WebView?, newProgress: Int) {
                    super.onProgressChanged(view, newProgress)
                    if (newProgress >= 90) {
                        loadingCallback.onLoadingChanged(false)
                    }
                }
            }
        }.also { created ->
            handle?.webView = created
        }
    }

    DisposableEffect(url) {
        loadingCallback.onLoadingChanged(true)
        webView.loadUrl(url)
        onDispose { }
    }

    DisposableEffect(Unit) {
        onDispose {
            handle?.webView = null
            webView.stopLoading()
            webView.destroy()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        AndroidView(
            factory = { webView },
            modifier = Modifier.fillMaxSize(),
        )
        if (showLoadingIndicator && isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.background),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}
