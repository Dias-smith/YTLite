package com.ytlite.player.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import android.app.Application
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.data.auth.OwnedYoutubeChannel
import com.ytlite.player.data.auth.UserProfile
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.ui.image.rememberYTLiteImageLoader
import java.text.NumberFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountSwitcherSheet(
    session: UserSession,
    visible: Boolean,
    onDismiss: () -> Unit,
    onAddAccountClick: () -> Unit,
    onSignOutClick: () -> Unit,
) {
    if (!visible) return

    val application = LocalContext.current.applicationContext as Application
    val viewModel: AccountSwitcherViewModel = viewModel(factory = AccountSwitcherViewModel.factory(application))
    val channelsState by viewModel.uiState.collectAsStateWithLifecycle()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    LaunchedEffect(visible, session) {
        if (visible) {
            val activeChannelId = (session as? UserSession.Authenticated)?.profile?.channelId
            viewModel.onSheetOpened(activeChannelId)
        }
    }

    LaunchedEffect(visible) {
        if (!visible) {
            viewModel.onSheetClosed()
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
        ) {
            when (session) {
                is UserSession.Authenticated -> {
                    AuthenticatedAccountContent(
                        profile = session.profile,
                        channelsState = channelsState,
                        onChannelClick = viewModel::selectChannel,
                    )
                }
                is UserSession.Guest -> {
                    Text(
                        text = stringResource(R.string.account_switcher_title),
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
                    )
                    Text(
                        text = stringResource(R.string.account_switcher_guest_hint),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
                    )
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            AccountActionRow(
                icon = { Icon(Icons.Filled.PersonAdd, contentDescription = null) },
                label = stringResource(R.string.account_switcher_add_account),
                onClick = {
                    onDismiss()
                    onAddAccountClick()
                },
            )
            if (session is UserSession.Authenticated) {
                AccountActionRow(
                    icon = {
                        Icon(
                            Icons.AutoMirrored.Filled.Logout,
                            contentDescription = null,
                        )
                    },
                    label = stringResource(R.string.account_switcher_sign_out),
                    onClick = {
                        onDismiss()
                        onSignOutClick()
                    },
                )
            }
        }
    }
}

@Composable
private fun AuthenticatedAccountContent(
    profile: UserProfile,
    channelsState: AccountChannelsUiState,
    onChannelClick: (OwnedYoutubeChannel) -> Unit,
) {
    Text(
        text = profile.displayName,
        style = MaterialTheme.typography.titleLarge,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
    )
    profile.email?.takeIf { it.isNotBlank() }?.let { email ->
        Text(
            text = email,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
        )
    }

    if (!channelsState.isLoading && channelsState.channels.isNotEmpty()) {
        channelsState.channels.forEach { channel ->
            val selected = channel.channelId == channelsState.activeChannelId
            AccountChannelRow(
                displayName = channel.title,
                handle = channel.handle,
                avatarUrl = channel.avatarUrl,
                subtitle = formatSubscriberSubtitle(channel),
                selected = selected,
                onClick = { onChannelClick(channel) },
            )
        }
    }
}

@Composable
private fun formatSubscriberSubtitle(channel: OwnedYoutubeChannel): String? {
    if (channel.hiddenSubscriberCount) return null
    val count = channel.subscriberCount ?: return null
    if (count == 0L) {
        return stringResource(R.string.account_switcher_no_subscribers)
    }
    val formatted = NumberFormat.getNumberInstance(Locale.getDefault()).format(count)
    return stringResource(R.string.account_switcher_subscriber_count, formatted)
}

@Composable
private fun AccountChannelRow(
    displayName: String,
    handle: String?,
    avatarUrl: String?,
    subtitle: String?,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val imageLoader = rememberYTLiteImageLoader()
    val avatarLetter = displayName.firstOrNull()?.uppercaseChar()?.toString() ?: "?"

    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (!avatarUrl.isNullOrBlank()) {
            AsyncImage(
                model = avatarUrl,
                contentDescription = displayName,
                imageLoader = imageLoader,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape),
            )
        } else {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Color(0xFFFF8A00)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = avatarLetter,
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White,
                )
            }
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = displayName,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            handle?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            subtitle?.takeIf { it.isNotBlank() }?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        if (selected) {
            Icon(
                imageVector = Icons.Filled.Check,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

@Composable
private fun AccountActionRow(
    icon: @Composable () -> Unit,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        icon()
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}
