package com.ytlite.player.ui.auth

import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.ytlite.player.BuildConfig
import com.ytlite.player.data.auth.GoogleNativeSignInTokens
import com.ytlite.player.data.auth.YoutubeOAuthConfig
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.security.MessageDigest
import java.util.UUID

class GoogleSignInCancelledException : Exception("用户取消了登录")

typealias AuthorizationLauncher = (IntentSenderRequest, CompletableDeferred<String?>) -> Unit

class GoogleNativeSignInHelper(
    private val activity: ComponentActivity,
    private val launchAuthorization: AuthorizationLauncher,
) {
    private val credentialManager = CredentialManager.create(activity)

    suspend fun signIn(): Result<GoogleNativeSignInTokens> = withContext(Dispatchers.Main) {
        runCatching {
            val rawNonce = UUID.randomUUID().toString()
            val hashedNonce = sha256Hex(rawNonce)
            val googleIdOption = GetGoogleIdOption.Builder()
                .setFilterByAuthorizedAccounts(false)
                .setServerClientId(BuildConfig.GOOGLE_WEB_CLIENT_ID)
                .setNonce(hashedNonce)
                .build()
            val credentialRequest = GetCredentialRequest.Builder()
                .addCredentialOption(googleIdOption)
                .build()

            val credentialResponse = try {
                credentialManager.getCredential(
                    context = activity,
                    request = credentialRequest,
                )
            } catch (_: GetCredentialCancellationException) {
                throw GoogleSignInCancelledException()
            }

            val customCredential = credentialResponse.credential as? CustomCredential
                ?: throw IllegalStateException("不支持的登录凭证类型")
            if (customCredential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                throw IllegalStateException("不支持的登录凭证类型")
            }
            val idToken = GoogleIdTokenCredential.createFrom(customCredential.data).idToken
            val accessToken = requestYoutubeAccessToken()
            YoutubeDiagnostics.d(
                "Auth",
                "native sign-in accessToken present=${!accessToken.isNullOrBlank()}",
            )
            GoogleNativeSignInTokens(
                idToken = idToken,
                accessToken = accessToken,
                nonce = rawNonce,
            )
        }
    }

    private suspend fun requestYoutubeAccessToken(): String? {
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

        val authorizationResult = Identity.getAuthorizationClient(activity)
            .authorize(authorizationRequest)
            .await()

        if (authorizationResult.hasResolution()) {
            YoutubeDiagnostics.d("Auth", "youtube authorization requires user consent UI")
            val pendingIntent = authorizationResult.pendingIntent ?: return null
            val deferred = CompletableDeferred<String?>()
            launchAuthorization(
                IntentSenderRequest.Builder(pendingIntent.intentSender).build(),
                deferred,
            )
            return deferred.await()
        }
        YoutubeDiagnostics.d(
            "Auth",
            "youtube authorization granted without extra UI accessToken present=" +
                !authorizationResult.accessToken.isNullOrBlank(),
        )
        return authorizationResult.accessToken
    }

    private fun sha256Hex(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
        return digest.joinToString("") { byte -> "%02x".format(byte) }
    }
}

@Composable
fun rememberGoogleNativeSignInHelper(): GoogleNativeSignInHelper? {
    val activity = LocalContext.current.findComponentActivity() ?: return null
    var pendingAuthorization by remember { mutableStateOf<CompletableDeferred<String?>?>(null) }

    val authorizationLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartIntentSenderForResult(),
    ) { result ->
        val deferred = pendingAuthorization
        pendingAuthorization = null
        if (deferred == null) return@rememberLauncherForActivityResult

        if (result.resultCode == ComponentActivity.RESULT_OK && result.data != null) {
            val token = runCatching {
                Identity.getAuthorizationClient(activity)
                    .getAuthorizationResultFromIntent(result.data!!)
                    .accessToken
            }.getOrNull()
            YoutubeDiagnostics.d(
                "Auth",
                "youtube authorization callback accessToken present=${!token.isNullOrBlank()}",
            )
            deferred.complete(token)
        } else {
            YoutubeDiagnostics.w(
                "Auth",
                "youtube authorization callback cancelled resultCode=${result.resultCode}",
            )
            deferred.complete(null)
        }
    }

    return remember(activity, authorizationLauncher) {
        GoogleNativeSignInHelper(
            activity = activity,
            launchAuthorization = { request, deferred ->
                pendingAuthorization = deferred
                authorizationLauncher.launch(request)
            },
        )
    }
}
