package com.ytlite.player.data.remote

import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.remote.dto.PlaylistDto
import java.time.Instant

fun PlaylistEntity.toPlaylistDto(userId: String): PlaylistDto = PlaylistDto(
    playlistId = playlistId,
    userId = userId,
    name = name,
    coverUrlOrPath = coverUrlOrPath,
    description = description,
    systemType = systemType,
    isPinned = isPinned,
    updatedAt = Instant.ofEpochMilli(updatedAt).toString(),
)

fun PlaylistDto.toPlaylistEntity(ownerKey: String, userId: String): PlaylistEntity = PlaylistEntity(
    playlistId = playlistId,
    ownerKey = ownerKey,
    userId = userId,
    name = name,
    coverUrlOrPath = coverUrlOrPath,
    description = description,
    systemType = systemType,
    source = DataSource.LOCAL.dbValue,
    isSynced = true,
    isPinned = isPinned,
    updatedAt = updatedAtMillis(),
)

fun PlaylistDto.updatedAtMillis(): Long =
    updatedAt?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }
        ?: System.currentTimeMillis()
