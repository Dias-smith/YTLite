package com.ytlite.player.data.auth

import android.content.Context
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import com.ytlite.player.BuildConfig
import com.ytlite.player.R
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.IDToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

class AuthRepository(
    private val context: Context,
    private val guestSessionStore: GuestSessionStore,
) {
    @Volatile
    private var cachedGoogleAccessToken: String? = null

    private val _session = MutableStateFlow<UserSession?>(null)
    val session: Flow<UserSession?> = _session.asStateFlow()
    private val initializeMutex = Mutex()
    private val tokenMutex = Mutex()

    var onMergeGuestData: (suspend (guestOwnerKey: String, userId: String, profile: UserProfile) -> Unit)? = null

    var onAuthenticated: (suspend (UserProfile) -> Unit)? = null

    var onSwitchToGuestMode: (suspend (userOwnerKey: String, guestOwnerKey: String) -> Unit)? = null

    var onSignedOut: (suspend () -> Unit)? = null

    suspend fun initialize() = initializeMutex.withLock {
        val guestId = guestSessionStore.ensureGuestId()
        runCatching {
            val cookieStore = com.ytlite.player.data.network.YoutubeCookieSessionStore.getInstance(context)
            cookieStore.restoreIntoCookieManagerAndJar()
            com.ytlite.player.data.network.YoutubeCookieJar.syncFromWebView()
        }
        val client = SupabaseClientProvider.get(context)
        val storedUserId = guestSessionStore.supabaseUserIdFlow.first()
        cachedGoogleAccessToken = guestSessionStore.getGoogleAccessToken()

        if (client != null) {
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

        // Do not demote an in-memory Authenticated session to Guest when Supabase
        // momentarily has no currentUser (disk hydrate race). That left the UI
        // "signed in" on one frame then empty YouTube data after re-init.
        val inMemory = _session.value as? UserSession.Authenticated
        if (inMemory != null &&
            !storedUserId.isNullOrBlank() &&
            storedUserId == inMemory.profile.userId
        ) {
            YoutubeDiagnostics.w(
                "Auth",
                "initialize: keeping in-memory Authenticated (supabase user not ready)",
            )
            return@withLock
        }

        _session.value = UserSession.Guest(guestId = guestId)
    }

    /** Hydrate OAuth cache from disk without touching session state. */
    suspend fun hydrateGoogleAccessTokenFromStore() {
        if (!cachedGoogleAccessToken.isNullOrBlank()) return
        cachedGoogleAccessToken = guestSessionStore.getGoogleAccessToken()
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

    suspend fun invalidateGoogleAccessToken() {
        persistGoogleAccessToken(null)
    }

    /**
     * Returns a usable YouTube Data API OAuth access token, refreshing silently when possible.
     * Google access tokens expire (~1h); an expired cached token leaves the app "signed in"
     * via Supabase while all Data API calls fail empty.
     *
     * @param forceRefresh when true, ignore the cache and request a new token silently.
     */
    suspend fun ensureFreshGoogleAccessToken(forceRefresh: Boolean = false): String? =
        tokenMutex.withLock {
            if (forceRefresh) {
                cachedGoogleAccessToken = null
            } else {
                hydrateGoogleAccessTokenFromStore()
                getGoogleProviderAccessToken()?.let { return@withLock it }
            }
            val silently = silentAuthorizeGoogleAccessToken()
            if (!silently.isNullOrBlank()) {
                persistGoogleAccessToken(silently)
                YoutubeDiagnostics.d("Auth", "silent Google accessToken refreshed len=${silently.length}")
                return@withLock silently
            }
            if (!forceRefresh) {
                // Fall back to whatever was on disk / supabase (may still be expired).
                hydrateGoogleAccessTokenFromStore()
            }
            getGoogleProviderAccessToken()
        }

    private suspend fun silentAuthorizeGoogleAccessToken(): String? = withContext(Dispatchers.IO) {
        if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isBlank()) return@withContext null
        runCatching {
            val authorizationRequest = AuthorizationRequest.builder()
                .setRequestedScopes(
                    listOf(
                        Scope(YoutubeOAuthConfig.SCOPE_YOUTUBE_READONLY),
                        Scope("openid"),
                        Scope("profile"),
                        Scope("email"),
                    ),
                )
                .requestOfflineAccess(BuildConfig.GOOGLE_WEB_CLIENT_ID)
                .build()
            val authorizationResult = Identity.getAuthorizationClient(context)
                .authorize(authorizationRequest)
                .await()
            if (authorizationResult.hasResolution()) {
                YoutubeDiagnostics.w("Auth", "silent authorize needs UI resolution")
                return@runCatching null
            }
            authorizationResult.accessToken?.takeIf { it.isNotBlank() }
        }.onFailure { error ->
            YoutubeDiagnostics.w("Auth", "silent authorize failed: ${error.message}")
        }.getOrNull()
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
        runCatching {
            com.ytlite.player.data.network.YoutubeCookieSessionStore.getInstance(context).clear()
            com.ytlite.player.data.network.YoutubeCookieJar.clearAll()
        }

        val guestId = guestSessionStore.ensureGuestId()
        val guestOwnerKey = "guest:$guestId"
        onSwitchToGuestMode?.invoke(userOwnerKey, guestOwnerKey)
        onSignedOut?.invoke()

        guestSessionStore.setSupabaseUserId(null)
        _session.value = UserSession.Guest(guestId = guestId)
    }

    fun currentSession(): UserSession? = _session.value

    fun getGoogleProviderAccessToken(): String? {
        cachedGoogleAccessToken?.takeIf { it.isNotBlank() }?.let { return it }
        val client = SupabaseClientProvider.get(context) ?: return null
        return client.auth.currentSessionOrNull()?.providerToken?.takeIf { it.isNotBlank() }
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
