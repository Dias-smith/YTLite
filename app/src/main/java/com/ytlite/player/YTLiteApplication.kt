package com.ytlite.player

import android.app.Application
import android.content.pm.ApplicationInfo
import android.os.Looper
import android.os.MessageQueue
import coil.ImageLoader
import coil.ImageLoaderFactory
import com.google.firebase.FirebaseApp
import com.google.firebase.crashlytics.FirebaseCrashlytics
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.firebase.RemoteConfigRepository
import com.ytlite.player.data.js.JsExtractorEngine
import com.ytlite.player.data.repository.ExtractionRepository
import com.ytlite.player.data.repository.LibraryRepository
import com.ytlite.player.data.repository.SubscriptionsRepository
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.playback.PlaybackMediaCache
import com.ytlite.player.ui.image.YTLiteImageLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class YTLiteApplication : Application(), ImageLoaderFactory {
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)
        val isDebuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        FirebaseCrashlytics.getInstance().isCrashlyticsCollectionEnabled = !isDebuggable
        RemoteConfigRepository.init(this, isDebuggable = isDebuggable)
        appScope.launch(Dispatchers.IO) {
            RemoteConfigRepository.fetchAndActivate()
        }
        ExtractionRepository.init(this)
        // Lightweight only — do not open media cache / FGS / WebView on the cold-start path.
        PlaybackManager.init(this)
        AuthRepository.getInstance(this)
        LibraryRepository.getInstance(this)
        SubscriptionsRepository.getInstance(this)
        appScope.launch {
            AuthRepository.getInstance(this@YTLiteApplication).initialize()
        }
        scheduleDeferredWarmup()
    }

    /**
     * Defers PlaybackMediaCache open + JsExtractor WebView until after first frames.
     * PlaybackService / MediaController still start lazily on first [PlaybackManager.play].
     */
    private fun scheduleDeferredWarmup() {
        val idleHandler = MessageQueue.IdleHandler {
            appScope.launch { runDeferredWarmup() }
            false
        }
        Looper.myQueue().addIdleHandler(idleHandler)
        // Fallback if the main queue never idles shortly after launch.
        appScope.launch {
            delay(DEFERRED_WARMUP_FALLBACK_MS)
            runDeferredWarmup()
        }
    }

    private suspend fun runDeferredWarmup() {
        if (!warmupStarted.compareAndSet(false, true)) return
        withContext(Dispatchers.IO) {
            runCatching { PlaybackMediaCache.get(this@YTLiteApplication) }
        }
        JsExtractorEngine.preloadAsync(this)
    }

    override fun newImageLoader(): ImageLoader = YTLiteImageLoader.get(this)

    override fun onLowMemory() {
        super.onLowMemory()
        JsExtractorEngine.getInstance(this).destroy()
        YTLiteImageLoader.get(this).memoryCache?.clear()
    }

    companion object {
        private const val DEFERRED_WARMUP_FALLBACK_MS = 2_000L
        private val warmupStarted = java.util.concurrent.atomic.AtomicBoolean(false)
    }
}
