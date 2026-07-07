package com.ytlite.player.data.auth

import android.content.Context
import com.ytlite.player.BuildConfig
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest

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
                install(Auth)
                install(Postgrest)
            }.also { client = it }
        }
    }
}
