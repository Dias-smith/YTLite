package com.ytlite.player.ui.settings

import android.app.Application
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Policy
import androidx.compose.material.icons.outlined.SentimentSatisfied
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.R
import com.ytlite.player.data.preferences.AppPreferences
import com.ytlite.player.data.preferences.DefaultDownloadFormat
import com.ytlite.player.data.preferences.DownloadPreferences

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onLanguageChanged: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: SettingsViewModel = viewModel(
        factory = SettingsViewModel.factory(
            LocalContext.current.applicationContext as Application,
        ),
    ),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showLanguageSheet by remember { mutableStateOf(false) }
    var showThreadSheet by remember { mutableStateOf(false) }
    var showFormatSheet by remember { mutableStateOf(false) }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.player_back),
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(vertical = 8.dp),
        ) {
            SettingsToggleRow(
                icon = Icons.Outlined.DarkMode,
                label = stringResource(R.string.settings_night_mode),
                checked = uiState.nightModeEnabled,
                onCheckedChange = viewModel::setNightModeEnabled,
            )
            SettingsNavRow(
                icon = Icons.Outlined.Language,
                label = stringResource(R.string.settings_language),
                onClick = { showLanguageSheet = true },
            )
            SettingsNavRow(
                icon = Icons.Outlined.Notifications,
                label = stringResource(R.string.settings_notifications),
                onClick = {
                    val intent = Intent().apply {
                        when {
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                                action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
                                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                            }
                            else -> {
                                action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                                data = Uri.fromParts("package", context.packageName, null)
                            }
                        }
                    }
                    context.startActivity(intent)
                },
            )
            SettingsNavRow(
                icon = Icons.Outlined.SentimentSatisfied,
                label = stringResource(R.string.settings_rate_us),
                onClick = {
                    val packageName = context.packageName
                    try {
                        context.startActivity(
                            Intent(
                                Intent.ACTION_VIEW,
                                Uri.parse("market://details?id=$packageName"),
                            ),
                        )
                    } catch (_: ActivityNotFoundException) {
                        context.startActivity(
                            Intent(
                                Intent.ACTION_VIEW,
                                Uri.parse("https://play.google.com/store/apps/details?id=$packageName"),
                            ),
                        )
                    }
                },
            )
            SettingsNavRow(
                icon = Icons.Outlined.Policy,
                label = stringResource(R.string.settings_privacy_policy),
                onClick = {
                    context.startActivity(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse(context.getString(R.string.settings_privacy_url)),
                        ),
                    )
                },
            )
            SettingsNavRow(
                icon = Icons.Outlined.Description,
                label = stringResource(R.string.settings_terms_of_service),
                onClick = {
                    context.startActivity(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse(context.getString(R.string.settings_terms_url)),
                        ),
                    )
                },
            )
            SettingsNavRow(
                icon = Icons.AutoMirrored.Outlined.Chat,
                label = stringResource(R.string.settings_feedback),
                onClick = {
                    val email = context.getString(R.string.settings_feedback_email)
                    val subject = context.getString(R.string.settings_feedback_subject)
                    val intent = Intent(Intent.ACTION_SENDTO).apply {
                        data = Uri.parse("mailto:")
                        putExtra(Intent.EXTRA_EMAIL, arrayOf(email))
                        putExtra(Intent.EXTRA_SUBJECT, subject)
                    }
                    runCatching { context.startActivity(intent) }
                },
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            Text(
                text = stringResource(R.string.settings_download_section),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            SettingsNavRow(
                icon = Icons.Outlined.Download,
                label = stringResource(
                    R.string.settings_download_threads_value,
                    uiState.downloadThreadCount,
                ),
                onClick = { showThreadSheet = true },
            )
            SettingsToggleRow(
                icon = Icons.Outlined.Download,
                label = stringResource(R.string.settings_download_resume),
                checked = uiState.downloadResumeEnabled,
                onCheckedChange = viewModel::setDownloadResumeEnabled,
            )
            SettingsToggleRow(
                icon = Icons.Outlined.Download,
                label = stringResource(R.string.settings_download_wifi_only),
                checked = uiState.downloadWifiOnly,
                onCheckedChange = viewModel::setDownloadWifiOnly,
            )
            SettingsNavRow(
                icon = Icons.Outlined.Download,
                label = stringResource(R.string.settings_download_default_format) +
                    ": " + defaultFormatLabel(uiState.defaultDownloadFormat),
                onClick = { showFormatSheet = true },
            )
        }
    }

    if (showLanguageSheet) {
        LanguagePickerSheet(
            selected = uiState.appLanguage,
            onDismiss = { showLanguageSheet = false },
            onSelect = { language ->
                viewModel.setAppLanguage(language) {
                    showLanguageSheet = false
                    onLanguageChanged()
                }
            },
        )
    }

    if (showThreadSheet) {
        SimpleChoiceSheet(
            title = stringResource(R.string.settings_download_threads),
            options = listOf(1, 2, 4, 8).map { it to "$it" },
            selected = uiState.downloadThreadCount,
            onDismiss = { showThreadSheet = false },
            onSelect = {
                viewModel.setDownloadThreadCount(it)
                showThreadSheet = false
            },
        )
    }

    if (showFormatSheet) {
        SimpleChoiceSheet(
            title = stringResource(R.string.settings_download_default_format),
            options = DefaultDownloadFormat.entries.map { it to defaultFormatLabel(it) },
            selected = uiState.defaultDownloadFormat,
            onDismiss = { showFormatSheet = false },
            onSelect = {
                viewModel.setDefaultDownloadFormat(it)
                showFormatSheet = false
            },
        )
    }
}

@Composable
private fun defaultFormatLabel(format: DefaultDownloadFormat): String = when (format) {
    DefaultDownloadFormat.AskEachTime -> stringResource(R.string.settings_download_format_ask)
    DefaultDownloadFormat.AudioFast -> stringResource(R.string.settings_download_format_audio)
    DefaultDownloadFormat.Video360 -> stringResource(R.string.settings_download_format_360)
    DefaultDownloadFormat.Video720 -> stringResource(R.string.settings_download_format_720)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> SimpleChoiceSheet(
    title: String,
    options: List<Pair<T, String>>,
    selected: T,
    onDismiss: () -> Unit,
    onSelect: (T) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        )
        options.forEach { (value, label) ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onSelect(value) }
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(
                    selected = value == selected,
                    onClick = { onSelect(value) },
                )
                Text(text = label, style = MaterialTheme.typography.bodyLarge)
            }
        }
        Spacer(modifier = Modifier.padding(bottom = 24.dp))
    }
}

@Composable
private fun SettingsToggleRow(
    icon: ImageVector,
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(24.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 16.dp),
        )
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun SettingsNavRow(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(24.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 16.dp),
        )
        Text(
            text = "›",
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LanguagePickerSheet(
    selected: String,
    onDismiss: () -> Unit,
    onSelect: (String) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(modifier = Modifier.padding(bottom = 24.dp)) {
            Text(
                text = stringResource(R.string.settings_language),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            )
            HorizontalDivider()
            LanguageOption(
                label = stringResource(R.string.settings_language_system),
                selected = selected == AppPreferences.LANGUAGE_SYSTEM,
                onClick = { onSelect(AppPreferences.LANGUAGE_SYSTEM) },
            )
            LanguageOption(
                label = stringResource(R.string.settings_language_english),
                selected = selected == AppPreferences.LANGUAGE_EN,
                onClick = { onSelect(AppPreferences.LANGUAGE_EN) },
            )
            LanguageOption(
                label = stringResource(R.string.settings_language_chinese),
                selected = selected == AppPreferences.LANGUAGE_ZH,
                onClick = { onSelect(AppPreferences.LANGUAGE_ZH) },
            )
        }
    }
}

@Composable
private fun LanguageOption(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onClick)
        Text(text = label, style = MaterialTheme.typography.bodyLarge)
    }
}
