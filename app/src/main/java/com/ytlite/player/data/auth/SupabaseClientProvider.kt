package com.ytlite.player.data.auth

import android.content.Context
import com.ytlite.player.BuildConfig
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.compose.auth.ComposeAuth
import io.github.jan.supabase.compose.auth.googleNativeLogin

object SupabaseClientProvider {

    val isConfigured: Boolean
        get() = BuildConfig.SUPABASE_URL.isNotBlank() && BuildConfig.SUPABASE_ANON_KEY.isNotBlank()

    @Volatile
    private var client: io.github.jan.supabase.SupabaseClient? = null

    fun get(context: Context): io.github.jan.supabase.SupabaseClient? {
        if (!isConfigured) return null
        return client ?: synchronized(this) {
            client ?: createSupabaseClient(
                supabaseUrl = BuildConfig.SUPABASE_URL,
                supabaseKey = BuildConfig.SUPABASE_ANON_KEY,
            ) {
                install(Auth) {
                    host = "login-callback"
                    scheme = "com.ytlite.player"
                }
                install(Postgrest)
                if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotBlank()) {
                    install(ComposeAuth) {
                        googleNativeLogin(serverClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID)
                    }
                }
            }.also { client = it }
        }
    }
}
