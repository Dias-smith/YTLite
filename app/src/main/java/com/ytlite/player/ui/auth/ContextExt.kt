package com.ytlite.player.ui.auth

import android.content.Context
import android.content.ContextWrapper
import androidx.activity.ComponentActivity

fun Context.findComponentActivity(): ComponentActivity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is ComponentActivity) return current
        current = current.baseContext
    }
    return null
}
