package com.ytlite.player.data.js

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

@SuppressLint("SetJavaScriptEnabled")
class JsExtractorEngine private constructor(
    appContext: Context,
) {
    private val context = appContext.applicationContext
    private var webView: WebView? = null
    private var bridge: VsPlayerBridge? = null
    private val readyDeferred = CompletableDeferred<Unit>()
    private val isInitializing = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())

    suspend fun ensureReady() {
        withContext(Dispatchers.Main) {
            if (webView == null && isInitializing.compareAndSet(false, true)) {
                initWebView()
            }
        }
        readyDeferred.await()
    }

    suspend fun invoke(event: Int, source: Int, data: JSONObject): JSONObject {
        ensureReady()
        return withTimeout(INVOKE_TIMEOUT_MS) {
            suspendCancellableCoroutine { continuation ->
                val uid = UUID.randomUUID().toString()
                val bridgeRef = bridge ?: run {
                    continuation.cancel(IllegalStateException("JS bridge not ready"))
                    return@suspendCancellableCoroutine
                }
                val message = JSONObject().apply {
                    put("uid", uid)
                    put("event", event)
                    put("source", source)
                    put("data", data)
                }
                bridgeRef.registerPending(uid, continuation)
                continuation.invokeOnCancellation { bridgeRef.cancelPending(uid) }
                val quotedPayload = JSONObject.quote(message.toString())
                val script =
                    "(function(){try{return window.extractor.postMessageToJSBridge($quotedPayload);}catch(e){AndroidBridge.onExtractorError(String(e));}})()"
                mainHandler.post {
                    webView?.evaluateJavascript(script, null)
                }
            }
        }
    }

    fun markReady() {
        if (!readyDeferred.isCompleted) {
            readyDeferred.complete(Unit)
        }
    }

    fun markFailed(message: String) {
        if (!readyDeferred.isCompleted) {
            readyDeferred.completeExceptionally(IllegalStateException(message))
        }
    }

    fun destroy() {
        bridge?.release()
        bridge = null
        webView?.destroy()
        webView = null
        isInitializing.set(false)
        synchronized(Companion) {
            if (instance === this) {
                instance = null
            }
        }
    }

    fun preloadAsync() {
        preloadScope.launch {
            runCatching { ensureReady() }
        }
    }

    private fun initWebView() {
        val view = WebView(context)
        val playerBridge = VsPlayerBridge(
            webView = view,
            onReady = { markReady() },
            onError = { message -> markFailed(message) },
        )
        bridge = playerBridge
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
        }
        view.addJavascriptInterface(playerBridge, "AndroidBridge")
        view.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                // Ready is signaled from bridge.html after extractor.js loads.
            }
        }
        view.loadUrl(BRIDGE_URL)
        webView = view
    }

    companion object {
        private const val BRIDGE_URL = "file:///android_asset/extractor/bridge.html"
        private const val INVOKE_TIMEOUT_MS = 45_000L

        private val preloadScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

        @Volatile
        private var instance: JsExtractorEngine? = null

        fun getInstance(context: Context): JsExtractorEngine =
            instance ?: synchronized(this) {
                instance ?: JsExtractorEngine(context.applicationContext).also { instance = it }
            }

        fun preloadAsync(context: Context) {
            preloadScope.launch {
                runCatching { getInstance(context).ensureReady() }
            }
        }
    }
}
