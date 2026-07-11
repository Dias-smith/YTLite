package com.ytlite.player.ui.library

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import android.app.Application
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.data.model.TrackMetadataSeed

@Composable
fun EditTrackMetadataDialog(
    trackId: String,
    seed: TrackMetadataSeed? = null,
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    val application = androidx.compose.ui.platform.LocalContext.current.applicationContext as Application
    val viewModel: EditTrackMetadataViewModel = viewModel(
        key = "edit-metadata-$trackId-${seed?.title}",
        factory = EditTrackMetadataViewModel.factory(application, trackId, seed),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    androidx.compose.runtime.LaunchedEffect(uiState.savedMetadata) {
        if (uiState.savedMetadata != null) {
            onSaved()
            onDismiss()
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = stringResource(R.string.edit_metadata_title)) },
        text = {
            if (uiState.isLoading) {
                CircularProgressIndicator()
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState()),
                ) {
                    if (uiState.thumbnailUrl.isNotBlank()) {
                        AsyncImage(
                            model = uiState.thumbnailUrl,
                            contentDescription = uiState.title,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(120.dp)
                                .padding(bottom = 12.dp)
                                .clip(RoundedCornerShape(8.dp)),
                        )
                    }
                    OutlinedTextField(
                        value = uiState.title,
                        onValueChange = viewModel::updateTitle,
                        label = { Text(stringResource(R.string.edit_metadata_field_title)) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 8.dp),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = uiState.artistName,
                        onValueChange = viewModel::updateArtistName,
                        label = { Text(stringResource(R.string.edit_metadata_field_artist)) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 8.dp),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = uiState.album,
                        onValueChange = viewModel::updateAlbum,
                        label = { Text(stringResource(R.string.edit_metadata_field_album)) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 8.dp),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = uiState.year,
                        onValueChange = viewModel::updateYear,
                        label = { Text(stringResource(R.string.edit_metadata_field_year)) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 8.dp),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = uiState.thumbnailUrl,
                        onValueChange = viewModel::updateThumbnailUrl,
                        label = { Text(stringResource(R.string.edit_metadata_field_thumbnail)) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = viewModel::save,
                enabled = !uiState.isLoading && !uiState.isSaving,
            ) {
                Text(stringResource(R.string.edit_metadata_save))
            }
        },
        dismissButton = {
            Column {
                if (uiState.hasOverride) {
                    TextButton(
                        onClick = viewModel::resetToDefault,
                        enabled = !uiState.isSaving,
                    ) {
                        Text(stringResource(R.string.edit_metadata_reset))
                    }
                }
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.edit_metadata_cancel))
                }
            }
        },
    )
}
