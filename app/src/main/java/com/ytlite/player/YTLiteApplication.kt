package com.ytlite.player

import android.app.Application
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.js.JsExtractorEngine
import com.ytlite.player.data.repository.ExtractionRepository
import com.ytlite.player.data.repository.LibraryRepository
import com.ytlite.player.data.repository.SubscriptionsRepository
import com.ytlite.player.playback.PlaybackManager

class YTLiteApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        ExtractionRepository.init(this)
        PlaybackManager.init(this)
        AuthRepository.getInstance(this)
        LibraryRepository.getInstance(this)
        SubscriptionsRepository.getInstance(this)
    }

    override fun onLowMemory() {
        super.onLowMemory()
        JsExtractorEngine.getInstance(this).destroy()
    }
}
