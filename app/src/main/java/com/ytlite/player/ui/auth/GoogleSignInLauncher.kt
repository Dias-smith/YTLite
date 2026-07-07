package com.ytlite.player.ui.auth

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.ytlite.player.BuildConfig
import com.ytlite.player.R
import com.ytlite.player.data.auth.SupabaseClientProvider
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.compose.auth.composeAuth
import io.github.jan.supabase.compose.auth.composable.NativeSignInResult
import io.github.jan.supabase.compose.auth.composable.rememberSignInWithGoogle

data class GoogleSignInLauncher(
    val canSignIn: Boolean,
    val startSignIn: () -> Unit,
    val notConfiguredMessage: String?,
)

@Composable
fun rememberGoogleSignInLauncher(
    onSignInSuccess: (userId: String, displayName: String?, avatarUrl: String?, email: String?) -> Unit,
    onError: (String) -> Unit,
): GoogleSignInLauncher {
    val context = LocalContext.current
    val supabaseNotConfigured = stringResource(R.string.sign_in_supabase_not_configured)
    val googleNotConfigured = stringResource(R.string.sign_in_google_not_configured)
    val client = remember(context) { SupabaseClientProvider.get(context) }

    if (!SupabaseClientProvider.isConfigured) {
        return remember(supabaseNotConfigured) {
            GoogleSignInLauncher(
                canSignIn = false,
                startSignIn = {},
                notConfiguredMessage = supabaseNotConfigured,
            )
        }
    }
    if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isBlank() || client == null) {
        return remember(googleNotConfigured) {
            GoogleSignInLauncher(
                canSignIn = false,
                startSignIn = {},
                notConfiguredMessage = googleNotConfigured,
            )
        }
    }

    val googleAction = client.composeAuth.rememberSignInWithGoogle(
        onResult = { result ->
            when (result) {
                is NativeSignInResult.Success -> {
                    val user = client.auth.currentUserOrNull()
                    if (user != null) {
                        val metadata = user.userMetadata
                        onSignInSuccess(
                            user.id,
                            metadata?.get("full_name")?.toString()?.trim('"')
                                ?: metadata?.get("name")?.toString()?.trim('"'),
                            metadata?.get("avatar_url")?.toString()?.trim('"'),
                            metadata?.get("email")?.toString()?.trim('"')
                                ?: user.email,
                        )
                    }
                }
                is NativeSignInResult.ClosedByUser -> Unit
                is NativeSignInResult.Error -> onError(result.message ?: "登录失败")
                is NativeSignInResult.NetworkError -> onError(result.message ?: "网络错误")
            }
        },
    )

    return remember(googleAction) {
        GoogleSignInLauncher(
            canSignIn = true,
            startSignIn = { googleAction.startFlow() },
            notConfiguredMessage = null,
        )
    }
}
