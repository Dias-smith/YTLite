package com.ytlite.player.ui.subscriptions

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.ytlite.player.R
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.ui.common.SignInPromptScreen
import com.ytlite.player.ui.common.SubscriptionsIllustration

@Composable
fun SubscriptionsScreen(
    session: UserSession?,
    onSignInClick: () -> Unit,
    onVideoClick: (VideoItem) -> Unit,
    onChannelListClick: () -> Unit,
    onChannelClick: (SubscriptionChannel) -> Unit = {},
    onSwitchAccountClick: () -> Unit = {},
    onPlaylistsViewAll: () -> Unit = {},
    onPlaylistClick: (YoutubePlaylistNav) -> Unit = {},
    onCreatePlaylistClick: () -> Unit = {},
    onYoutubeWebLoginClick: () -> Unit = {},
    youtubeCookieSessionEpoch: Int = 0,
    modifier: Modifier = Modifier,
) {
    when (session) {
        is UserSession.Authenticated -> YoutubeYouScreen(
            session = session,
            onViewChannelClick = onChannelClick,
            onSwitchAccountClick = onSwitchAccountClick,
            onSubscriptionsViewAll = onChannelListClick,
            onPlaylistsViewAll = onPlaylistsViewAll,
            onPlaylistClick = onPlaylistClick,
            onChannelClick = onChannelClick,
            onVideoClick = onVideoClick,
            onCreatePlaylistClick = onCreatePlaylistClick,
            onYoutubeWebLoginClick = onYoutubeWebLoginClick,
            youtubeCookieSessionEpoch = youtubeCookieSessionEpoch,
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
