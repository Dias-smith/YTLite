package com.ytlite.player.ui.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ytlite.player.BuildConfig
import com.ytlite.player.R
import com.ytlite.player.data.auth.SupabaseClientProvider
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.compose.auth.composeAuth
import io.github.jan.supabase.compose.auth.composable.NativeSignInResult
import io.github.jan.supabase.compose.auth.composable.rememberSignInWithGoogle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SignInBottomSheet(
    visible: Boolean,
    supabaseConfigured: Boolean,
    onDismiss: () -> Unit,
    onSignInSuccess: (userId: String, displayName: String?, avatarUrl: String?, email: String?) -> Unit,
    onError: (String) -> Unit,
) {
    if (!visible) return

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    val client = SupabaseClientProvider.get(context)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = stringResource(R.string.sign_in_sheet_title),
                style = MaterialTheme.typography.titleLarge,
            )
            Text(
                text = stringResource(R.string.sign_in_sheet_description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (!supabaseConfigured) {
                Text(
                    text = stringResource(R.string.sign_in_supabase_not_configured),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            } else if (client != null && BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotBlank()) {
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
                Button(
                    onClick = { googleAction.startFlow() },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(text = stringResource(R.string.sign_in_with_google))
                }
            } else {
                Text(
                    text = stringResource(R.string.sign_in_google_not_configured),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}
