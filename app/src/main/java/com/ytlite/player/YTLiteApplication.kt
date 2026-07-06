package com.ytlite.player

import android.app.Application
import com.ytlite.player.data.js.JsExtractorEngine
import com.ytlite.player.data.repository.ExtractionRepository
import com.ytlite.player.playback.PlaybackManager

class YTLiteApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        ExtractionRepository.init(this)
        PlaybackManager.init(this)
    }

    override fun onLowMemory() {
        super.onLowMemory()
        JsExtractorEngine.getInstance(this).destroy()
    }
}
