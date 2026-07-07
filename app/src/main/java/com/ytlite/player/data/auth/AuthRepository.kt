package com.ytlite.player.data.auth

import android.content.Context
import com.ytlite.player.BuildConfig
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.IDToken
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update

class AuthRepository(
    private val context: Context,
    private val guestSessionStore: GuestSessionStore,
) {
    @Volatile
    private var cachedGoogleAccessToken: String? = null

    private val _session = MutableStateFlow<UserSession?>(null)
    val session: Flow<UserSession?> = _session.asStateFlow()

    private val _authError = MutableStateFlow<String?>(null)
    val authError: Flow<String?> = _authError.asStateFlow()

    val supabaseConfigured: Boolean = SupabaseClientProvider.isConfigured

    var onMergeGuestData: (suspend (guestOwnerKey: String, userId: String, profile: UserProfile) -> Unit)? = null

    var onAuthenticated: (suspend (UserProfile) -> Unit)? = null

    var onSignedOut: (suspend () -> Unit)? = null

    /** Invoked after WebView bootstrap persists YouTube auth cookies (__Secure-3PAPISID). */
    var onYoutubeCookiesReady: (suspend () -> Unit)? = null

    suspend fun notifyYoutubeCookiesReady() {
        com.ytlite.player.data.youtube.YoutubeDiagnostics.d(
            "Auth",
            "notifyYoutubeCookiesReady invoked hasCallback=${onYoutubeCookiesReady != null}",
        )
        onYoutubeCookiesReady?.invoke()
    }

    suspend fun initialize() {
        val guestId = guestSessionStore.ensureGuestId()
        val client = SupabaseClientProvider.get(context)
        val storedUserId = guestSessionStore.supabaseUserIdFlow.first()

        if (client != null) {
            cachedGoogleAccessToken = guestSessionStore.getGoogleAccessToken()
            val currentUser = client.auth.currentUserOrNull()
            if (currentUser != null && storedUserId == currentUser.id) {
                val profile = buildProfileFromAuth(currentUser.id, currentUser.userMetadata)
                _session.value = UserSession.Authenticated(profile)
                onAuthenticated?.invoke(profile)
                logYoutubeDataApiReadiness("initialize-session")
                return
            }
        }
        _session.value = UserSession.Guest(guestId = guestId)
    }

    suspend fun signInWithGoogleNative(tokens: GoogleNativeSignInTokens): Result<UserProfile> {
        val client = SupabaseClientProvider.get(context)
            ?: return Result.failure(IllegalStateException("Supabase 未配置"))
        return runCatching {
            if (tokens.accessToken.isNullOrBlank()) {
                throw IllegalStateException("未获取 YouTube 授权，请重新登录并同意 YouTube 只读权限")
            }
            client.auth.signInWith(IDToken) {
                provider = Google
                idToken = tokens.idToken
                accessToken = tokens.accessToken
                nonce = tokens.nonce
            }
            persistGoogleAccessToken(tokens.accessToken)
            buildProfileFromOAuth(client)
        }.onSuccess {
            logYoutubeDataApiReadiness("post-google-native-sign-in")
        }
    }

    private suspend fun persistGoogleAccessToken(token: String?) {
        cachedGoogleAccessToken = token?.takeIf { it.isNotBlank() }
        guestSessionStore.setGoogleAccessToken(cachedGoogleAccessToken)
    }

    suspend fun onOAuthSessionFromDeeplink() {
        val client = SupabaseClientProvider.get(context) ?: return
        val user = client.auth.currentUserOrNull() ?: return
        if (_session.value is UserSession.Authenticated &&
            (_session.value as UserSession.Authenticated).profile.userId == user.id
        ) {
            logYoutubeDataApiReadiness("oauth-deeplink")
            return
        }
        applyAuthenticatedProfile(buildProfileFromOAuth(client))
    }

    private fun buildProfileFromOAuth(client: io.github.jan.supabase.SupabaseClient): UserProfile {
        val user = client.auth.currentUserOrNull()
            ?: throw IllegalStateException("登录成功但未获取到用户信息")
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
        logYoutubeDataApiReadiness("post-google-sign-in")
        if (guestOwnerKey != null) {
            onMergeGuestData?.invoke(guestOwnerKey, profile.userId, profile)
        }
        onAuthenticated?.invoke(profile)
    }

    suspend fun signOut() {
        val client = SupabaseClientProvider.get(context)
        runCatching { client?.auth?.signOut() }
        cachedGoogleAccessToken = null
        guestSessionStore.setGoogleAccessToken(null)
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

    /**
     * Google OAuth access token for YouTube Data API.
     * Native sign-in stores the AuthorizationClient token locally because Supabase
     * ID-token login does not persist [providerToken] on the session.
     */
    fun getGoogleProviderAccessToken(): String? {
        cachedGoogleAccessToken?.let { return it }
        val client = SupabaseClientProvider.get(context) ?: return null
        return client.auth.currentSessionOrNull()?.providerToken
    }

    fun isYoutubeDataApiKeyConfigured(): Boolean =
        BuildConfig.YOUTUBE_DATA_API_KEY.isNotBlank()

    fun needsYoutubeDataApiReauth(): Boolean =
        isYoutubeDataApiKeyConfigured() && getGoogleProviderAccessToken() == null

    fun logYoutubeDataApiReadiness(label: String) {
        val storedTokenPresent = !cachedGoogleAccessToken.isNullOrBlank()
        val sessionTokenPresent = SupabaseClientProvider.get(context)
            ?.auth
            ?.currentSessionOrNull()
            ?.providerToken
            ?.isNotBlank() == true
        val effectiveTokenPresent = getGoogleProviderAccessToken() != null
        com.ytlite.player.data.youtube.YoutubeDiagnostics.d(
            "Auth",
            "[$label] googleAccessToken stored=$storedTokenPresent " +
                "sessionProviderToken=$sessionTokenPresent " +
                "effective=$effectiveTokenPresent keyConfigured=${isYoutubeDataApiKeyConfigured()}",
        )
        if (isYoutubeDataApiKeyConfigured() && !effectiveTokenPresent) {
            com.ytlite.player.data.youtube.YoutubeDiagnostics.w(
                "Auth",
                "[$label] Data API key set but no Google access token — " +
                    "re-login and grant ${YoutubeOAuthConfig.SCOPE_YOUTUBE_READONLY}",
            )
        }
    }

    suspend fun onGoogleSignInSuccess(
        userId: String,
        displayName: String?,
        avatarUrl: String?,
        email: String?,
    ) {
        val handle = email?.substringBefore("@")?.let { "@$it" }
        applyAuthenticatedProfile(
            UserProfile(
                userId = userId,
                displayName = displayName?.ifBlank { null } ?: "用户",
                handle = handle,
                avatarUrl = avatarUrl,
                email = email?.ifBlank { null },
            ),
        )
    }

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
