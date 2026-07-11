package com.ytlite.player.ui.playlistaction

import android.app.Application
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.R
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.library.EditPlaylistDialog

val LocalPlaylistMoreClick = compositionLocalOf<(PlaylistActionContext) -> Unit> { {} }

@Composable
fun PlaylistActionHost(
    onShufflePlay: (List<QueueItem>) -> Unit,
    content: @Composable () -> Unit,
) {
    val application = LocalContext.current.applicationContext as Application
    var sheetContext by remember { mutableStateOf<PlaylistActionContext?>(null) }
    var dialogContext by remember { mutableStateOf<PlaylistActionContext?>(null) }
    var showEditDialog by remember { mutableStateOf(false) }
    var showDeleteDialog by remember { mutableStateOf(false) }

    CompositionLocalProvider(
        LocalPlaylistMoreClick provides { context -> sheetContext = context },
    ) {
        content()
    }

    sheetContext?.let { context ->
        PlaylistActionBottomSheet(
            context = context,
            onDismiss = { sheetContext = null },
            onShufflePlay = onShufflePlay,
            onEdit = {
                dialogContext = context
                sheetContext = null
                showEditDialog = true
            },
            onDelete = {
                dialogContext = context
                sheetContext = null
                showDeleteDialog = true
            },
        )
    }

    if (showEditDialog) {
        dialogContext?.let { context ->
            val viewModel: PlaylistActionViewModel = viewModel(
                key = "playlist-action-edit-${context.playlistId}",
                factory = PlaylistActionViewModel.factory(application, context),
            )
            EditPlaylistDialog(
                initialName = context.title,
                onDismiss = {
                    showEditDialog = false
                    dialogContext = null
                },
                onConfirm = { name ->
                    viewModel.renamePlaylist(name) {
                        showEditDialog = false
                        dialogContext = null
                    }
                },
            )
        }
    }

    if (showDeleteDialog) {
        dialogContext?.let { context ->
            val viewModel: PlaylistActionViewModel = viewModel(
                key = "playlist-action-delete-${context.playlistId}",
                factory = PlaylistActionViewModel.factory(application, context),
            )
            AlertDialog(
                onDismissRequest = {
                    showDeleteDialog = false
                    dialogContext = null
                },
                title = { Text(text = stringResource(R.string.playlist_delete_title)) },
                text = { Text(text = stringResource(R.string.playlist_delete_message, context.title)) },
                confirmButton = {
                    TextButton(
                        onClick = {
                            viewModel.deletePlaylist {
                                showDeleteDialog = false
                                dialogContext = null
                            }
                        },
                    ) {
                        Text(text = stringResource(R.string.playlist_action_delete))
                    }
                },
                dismissButton = {
                    TextButton(
                        onClick = {
                            showDeleteDialog = false
                            dialogContext = null
                        },
                    ) {
                        Text(text = stringResource(R.string.library_cancel))
                    }
                },
            )
        }
    }
}
