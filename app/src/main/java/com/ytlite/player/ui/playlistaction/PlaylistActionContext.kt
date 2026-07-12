package com.ytlite.player.ui.playlistaction

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryItem

@Immutable
data class PlaylistActionContext(
    val playlistId: String,
    val title: String,
    val coverUrl: String?,
    val source: DataSource,
    val systemType: String?,
    val ownerKey: String,
    val isPinned: Boolean = false,
) {
    val isHistoryVirtual: Boolean get() = systemType == PlaylistSystemType.HISTORY
    val isSystemPlaylist: Boolean get() = systemType != null
    val canEdit: Boolean get() = source == DataSource.LOCAL && systemType == null
    val canDelete: Boolean get() = canEdit
    val canPin: Boolean get() = systemType != PlaylistSystemType.HISTORY

    companion object {
        fun fromLibraryItem(item: LibraryItem.Playlist, ownerKey: String) = PlaylistActionContext(
            playlistId = item.playlistId,
            title = item.title,
            coverUrl = item.coverUrl,
            source = item.source,
            systemType = item.systemType,
            ownerKey = ownerKey,
            isPinned = item.isPinned,
        )

        fun fromPlaylistEntity(
            playlist: PlaylistEntity,
            coverUrl: String?,
            ownerKey: String,
        ) = PlaylistActionContext(
            playlistId = playlist.playlistId,
            title = playlist.name,
            coverUrl = coverUrl ?: playlist.coverUrlOrPath,
            source = playlist.dataSource,
            systemType = playlist.systemType,
            ownerKey = ownerKey,
            isPinned = playlist.isPinned,
        )
    }
}
