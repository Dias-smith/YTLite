package com.ytlite.player.data.auth

import android.content.Context
import com.ytlite.player.BuildConfig
import com.ytlite.player.R
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.IDToken
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class AuthRepository(
    private val context: Context,
    private val guestSessionStore: GuestSessionStore,
) {
    @Volatile
    private var cachedGoogleAccessToken: String? = null

    private val _session = MutableStateFlow<UserSession?>(null)
    val session: Flow<UserSession?> = _session.asStateFlow()
    private val initializeMutex = Mutex()

    var onMergeGuestData: (suspend (guestOwnerKey: String, userId: String, profile: UserProfile) -> Unit)? = null

    var onAuthenticated: (suspend (UserProfile) -> Unit)? = null

    var onSwitchToGuestMode: (suspend (userOwnerKey: String, guestOwnerKey: String) -> Unit)? = null

    var onSignedOut: (suspend () -> Unit)? = null

    suspend fun initialize() = initializeMutex.withLock {
        val guestId = guestSessionStore.ensureGuestId()
        val client = SupabaseClientProvider.get(context)
        val storedUserId = guestSessionStore.supabaseUserIdFlow.first()

        if (client != null) {
            cachedGoogleAccessToken = guestSessionStore.getGoogleAccessToken()
            val currentUser = client.auth.currentUserOrNull()
            if (currentUser != null && storedUserId == currentUser.id) {
                val profile = buildProfileFromAuth(currentUser.id, currentUser.userMetadata)
                val activeChannelId = guestSessionStore.getActiveChannelId(currentUser.id)
                val authenticated = UserSession.Authenticated(
                    profile.copy(channelId = activeChannelId),
                )
                _session.value = authenticated
                onAuthenticated?.invoke(authenticated.profile)
                return@withLock
            }
        }
        _session.value = UserSession.Guest(guestId = guestId)
    }

    suspend fun signInWithGoogleNative(tokens: GoogleNativeSignInTokens): Result<UserProfile> {
        val client = SupabaseClientProvider.get(context)
            ?: return Result.failure(IllegalStateException(context.getString(R.string.error_supabase_not_configured)))
        return runCatching {
            if (tokens.accessToken.isNullOrBlank()) {
                throw IllegalStateException(context.getString(R.string.error_youtube_auth_missing))
            }
            client.auth.signInWith(IDToken) {
                provider = Google
                idToken = tokens.idToken
                accessToken = tokens.accessToken
                nonce = tokens.nonce
            }
            persistGoogleAccessToken(tokens.accessToken)
            val profile = buildProfileFromOAuth(client)
            applyAuthenticatedProfile(profile)
            profile
        }
    }

    private suspend fun persistGoogleAccessToken(token: String?) {
        cachedGoogleAccessToken = token?.takeIf { it.isNotBlank() }
        guestSessionStore.setGoogleAccessToken(cachedGoogleAccessToken)
    }

    private fun buildProfileFromOAuth(client: io.github.jan.supabase.SupabaseClient): UserProfile {
        val user = client.auth.currentUserOrNull()
            ?: throw IllegalStateException(context.getString(R.string.error_user_info_missing))
        return buildProfileFromAuth(user.id, user.userMetadata).copy(
            email = user.userMetadata?.get("email")?.toString()?.trim('"')
                ?: user.email,
        )
    }

    private suspend fun applyAuthenticatedProfile(profile: UserProfile) {
        val guestSession = _session.value as? UserSession.Guest
        val guestOwnerKey = guestSession?.ownerKey
        guestSessionStore.setSupabaseUserId(profile.userId)
        _session.value = UserSession.Authenticated(profile)
        if (guestOwnerKey != null) {
            onMergeGuestData?.invoke(guestOwnerKey, profile.userId, profile)
        }
        onAuthenticated?.invoke(profile)
    }

    suspend fun switchToGuestMode() {
        val authenticated = _session.value as? UserSession.Authenticated ?: return
        val userId = authenticated.profile.userId
        val userOwnerKey = authenticated.ownerKey

        val client = SupabaseClientProvider.get(context)
        runCatching { client?.auth?.signOut() }
        cachedGoogleAccessToken = null
        guestSessionStore.setGoogleAccessToken(null)
        guestSessionStore.setActiveChannelId(userId, null)

        val guestId = guestSessionStore.ensureGuestId()
        val guestOwnerKey = "guest:$guestId"
        onSwitchToGuestMode?.invoke(userOwnerKey, guestOwnerKey)
        onSignedOut?.invoke()

        guestSessionStore.setSupabaseUserId(null)
        _session.value = UserSession.Guest(guestId = guestId)
    }

    fun currentSession(): UserSession? = _session.value

    fun getGoogleProviderAccessToken(): String? {
        cachedGoogleAccessToken?.let { return it }
        val client = SupabaseClientProvider.get(context) ?: return null
        return client.auth.currentSessionOrNull()?.providerToken
    }

    /** Debug-only: where the OAuth token would be read from (no token value logged). */
    fun diagnoseGoogleAccessTokenSource(): String {
        if (!cachedGoogleAccessToken.isNullOrBlank()) {
            return "guest_store_cached(len=${cachedGoogleAccessToken!!.length})"
        }
        val provider = SupabaseClientProvider.get(context)?.auth?.currentSessionOrNull()?.providerToken
        if (!provider.isNullOrBlank()) {
            return "supabase_provider(len=${provider.length})"
        }
        return "missing"
    }

    fun isYoutubeDataApiKeyConfigured(): Boolean =
        BuildConfig.YOUTUBE_DATA_API_KEY.isNotBlank()

    fun needsYoutubeDataApiReauth(): Boolean =
        isYoutubeDataApiKeyConfigured() && getGoogleProviderAccessToken() == null

    fun updateAuthenticatedProfile(profile: UserProfile) {
        _session.value = UserSession.Authenticated(profile)
    }

    suspend fun selectYoutubeChannel(channel: OwnedYoutubeChannel) {
        val session = currentSession() as? UserSession.Authenticated ?: return
        guestSessionStore.setActiveChannelId(session.profile.userId, channel.channelId)
        updateAuthenticatedProfile(
            session.profile.copy(
                channelId = channel.channelId,
                displayName = channel.title,
                handle = channel.handle,
                avatarUrl = channel.avatarUrl,
            ),
        )
    }

    fun getActiveChannelId(): String? {
        val session = currentSession() as? UserSession.Authenticated ?: return null
        return session.profile.channelId
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
            displayName = name?.ifBlank { null } ?: context.getString(R.string.default_user_display_name),
            handle = email?.substringBefore("@")?.let { "@$it" },
            avatarUrl = avatar,
            email = email?.ifBlank { null },
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
