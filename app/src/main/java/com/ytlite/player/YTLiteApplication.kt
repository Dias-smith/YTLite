package com.ytlite.player

import android.app.Application
import com.ytlite.player.data.js.JsExtractorEngine
import com.ytlite.player.data.repository.ExtractionRepository

class YTLiteApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        ExtractionRepository.init(this)
    }

    override fun onLowMemory() {
        super.onLowMemory()
        JsExtractorEngine.getInstance(this).destroy()
    }
}
