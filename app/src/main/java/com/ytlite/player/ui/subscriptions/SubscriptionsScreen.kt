package com.ytlite.player.ui.subscriptions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.ui.common.SignInPromptScreen
import com.ytlite.player.ui.common.SubscriptionsIllustration

@Composable
fun SubscriptionsScreen(
    session: UserSession?,
    onSignInClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    when (session) {
        is UserSession.Authenticated -> SubscriptionsAuthenticatedContent(
            modifier = modifier,
        )
        else -> SignInPromptScreen(
            title = stringResource(R.string.subscriptions_sign_in_title),
            description = stringResource(R.string.subscriptions_sign_in_description),
            illustration = { SubscriptionsIllustration() },
            onSignInClick = onSignInClick,
            modifier = modifier,
        )
    }
}

@Composable
private fun SubscriptionsAuthenticatedContent(
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        SubscriptionsIllustration()
        Spacer(modifier = Modifier.height(32.dp))
        Text(
            text = stringResource(R.string.subscriptions_empty_title),
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = stringResource(R.string.subscriptions_empty_description),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}
