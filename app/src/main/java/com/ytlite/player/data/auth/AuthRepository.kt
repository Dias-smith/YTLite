package com.ytlite.player.data.auth

import android.content.Context
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update

class AuthRepository(
    private val context: Context,
    private val guestSessionStore: GuestSessionStore,
) {
    private val _session = MutableStateFlow<UserSession?>(null)
    val session: Flow<UserSession?> = _session.asStateFlow()

    private val _authError = MutableStateFlow<String?>(null)
    val authError: Flow<String?> = _authError.asStateFlow()

    val supabaseConfigured: Boolean = SupabaseClientProvider.isConfigured

    var onMergeGuestData: (suspend (guestOwnerKey: String, userId: String, profile: UserProfile) -> Unit)? = null

    var onAuthenticated: (suspend (UserProfile) -> Unit)? = null

    var onSignedOut: (suspend () -> Unit)? = null

    suspend fun initialize() {
        val guestId = guestSessionStore.ensureGuestId()
        val client = SupabaseClientProvider.get(context)
        val storedUserId = guestSessionStore.supabaseUserIdFlow.first()

        if (client != null) {
            val currentUser = client.auth.currentUserOrNull()
            if (currentUser != null && storedUserId == currentUser.id) {
                val profile = buildProfileFromAuth(currentUser.id, currentUser.userMetadata)
                _session.value = UserSession.Authenticated(profile)
                onAuthenticated?.invoke(profile)
                return
            }
        }
        _session.value = UserSession.Guest(guestId = guestId)
    }

    suspend fun onGoogleSignInSuccess(
        userId: String,
        displayName: String?,
        avatarUrl: String?,
        email: String?,
    ) {
        val guestSession = _session.value as? UserSession.Guest
        val guestOwnerKey = guestSession?.ownerKey

        val handle = email?.substringBefore("@")?.let { "@$it" }
        val profile = UserProfile(
            userId = userId,
            displayName = displayName?.ifBlank { null } ?: "用户",
            handle = handle,
            avatarUrl = avatarUrl,
        )
        guestSessionStore.setSupabaseUserId(userId)
        _session.value = UserSession.Authenticated(profile)

        if (guestOwnerKey != null) {
            onMergeGuestData?.invoke(guestOwnerKey, userId, profile)
        }
        onAuthenticated?.invoke(profile)
    }

    suspend fun signInWithGoogleOAuth(): Result<Unit> {
        val client = SupabaseClientProvider.get(context)
            ?: return Result.failure(IllegalStateException("Supabase 未配置"))
        return runCatching {
            client.auth.signInWith(Google)
        }
    }

    suspend fun signOut() {
        val client = SupabaseClientProvider.get(context)
        runCatching { client?.auth?.signOut() }
        onSignedOut?.invoke()
        guestSessionStore.setSupabaseUserId(null)
        val newGuestId = guestSessionStore.rotateGuestId()
        _session.value = UserSession.Guest(guestId = newGuestId)
    }

    fun clearError() {
        _authError.update { null }
    }

    fun setError(message: String) {
        _authError.update { message }
    }

    fun currentSession(): UserSession? = _session.value

    fun updateAuthenticatedProfile(profile: UserProfile) {
        _session.value = UserSession.Authenticated(profile)
    }

    private fun buildProfileFromAuth(
        userId: String,
        metadata: Map<String, kotlinx.serialization.json.JsonElement>?,
    ): UserProfile {
        val name = metadata?.get("full_name")?.toString()?.trim('"')
            ?: metadata?.get("name")?.toString()?.trim('"')
        val avatar = metadata?.get("avatar_url")?.toString()?.trim('"')
        val email = metadata?.get("email")?.toString()?.trim('"')
        return UserProfile(
            userId = userId,
            displayName = name?.ifBlank { null } ?: "用户",
            handle = email?.substringBefore("@")?.let { "@$it" },
            avatarUrl = avatar,
        )
    }

    companion object {
        @Volatile
        private var instance: AuthRepository? = null

        fun getInstance(context: Context): AuthRepository =
            instance ?: synchronized(this) {
                instance ?: AuthRepository(
                    context = context.applicationContext,
                    guestSessionStore = GuestSessionStore(context.applicationContext),
                ).also { instance = it }
            }
    }
}
