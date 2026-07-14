package com.ytlite.player

import android.app.Application
import android.content.pm.ApplicationInfo
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
import kotlinx.coroutines.launch

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
        PlaybackManager.init(this)
        PlaybackMediaCache.get(this)
        PlaybackManager.ensureConnected()
        JsExtractorEngine.preloadAsync(this)
        AuthRepository.getInstance(this)
        LibraryRepository.getInstance(this)
        SubscriptionsRepository.getInstance(this)
        appScope.launch {
            AuthRepository.getInstance(this@YTLiteApplication).initialize()
        }
    }

    override fun newImageLoader(): ImageLoader = YTLiteImageLoader.get(this)

    override fun onLowMemory() {
        super.onLowMemory()
        JsExtractorEngine.getInstance(this).destroy()
        YTLiteImageLoader.get(this).memoryCache?.clear()
    }
}
