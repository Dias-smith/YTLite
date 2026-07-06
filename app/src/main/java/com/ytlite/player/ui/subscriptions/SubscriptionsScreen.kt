package com.ytlite.player.ui.subscriptions

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.ytlite.player.R
import com.ytlite.player.ui.common.SignInPromptScreen
import com.ytlite.player.ui.common.SubscriptionsIllustration

@Composable
fun SubscriptionsScreen(
    onSignInClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    SignInPromptScreen(
        title = stringResource(R.string.subscriptions_sign_in_title),
        description = stringResource(R.string.subscriptions_sign_in_description),
        illustration = { SubscriptionsIllustration() },
        onSignInClick = onSignInClick,
        modifier = modifier,
    )
}
