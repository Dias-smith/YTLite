package com.ytlite.player.ui.auth

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.ytlite.player.BuildConfig
import com.ytlite.player.R
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.SupabaseClientProvider
import kotlinx.coroutines.launch

data class GoogleSignInLauncher(
    val canSignIn: Boolean,
    val startSignIn: () -> Unit,
    val notConfiguredMessage: String?,
)

@Composable
fun rememberGoogleSignInLauncher(
    onError: (String) -> Unit,
): GoogleSignInLauncher {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val authRepository = remember(context) { AuthRepository.getInstance(context) }
    val googleSignInHelper = rememberGoogleNativeSignInHelper()
    val supabaseNotConfigured = stringResource(R.string.sign_in_supabase_not_configured)
    val googleNotConfigured = stringResource(R.string.sign_in_google_not_configured)

    if (!SupabaseClientProvider.isConfigured) {
        return remember(supabaseNotConfigured) {
            GoogleSignInLauncher(
                canSignIn = false,
                startSignIn = {},
                notConfiguredMessage = supabaseNotConfigured,
            )
        }
    }
    if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isBlank() || googleSignInHelper == null) {
        return remember(googleNotConfigured) {
            GoogleSignInLauncher(
                canSignIn = false,
                startSignIn = {},
                notConfiguredMessage = googleNotConfigured,
            )
        }
    }

    return remember(authRepository, googleSignInHelper, scope) {
        GoogleSignInLauncher(
            canSignIn = true,
            startSignIn = {
                scope.launch {
                    googleSignInHelper.signIn()
                        .mapCatching { tokens ->
                            authRepository.signInWithGoogleNative(tokens).getOrThrow()
                        }
                        .onFailure { error ->
                            if (error !is GoogleSignInCancelledException) {
                                onError(error.message ?: context.getString(R.string.error_sign_in_failed))
                            }
                        }
                }
            },
            notConfiguredMessage = null,
        )
    }
}
