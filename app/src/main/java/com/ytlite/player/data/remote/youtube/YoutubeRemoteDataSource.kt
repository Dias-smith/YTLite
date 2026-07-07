package com.ytlite.player.data.remote.youtube

import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import com.ytlite.player.data.model.PlaylistIds
import com.ytlite.player.data.network.InnerTubeApi
import com.ytlite.player.data.network.YoutubeCookieJar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

class YoutubeRemoteDataSource(
    private val innerTubeApi: InnerTubeApi = InnerTubeApi.getInstance(),
) {
    private val playlistsState = MutableStateFlow<List<PlaylistEntity>>(emptyList())
    private var ownerKey: String? = null

    fun getYoutubePlaylistsFlow(): Flow<List<PlaylistEntity>> = playlistsState.asStateFlow()

    fun setOwnerKey(key: String?) {
        ownerKey = key
        if (key == null) {
            playlistsState.value = emptyList()
        }
    }

    suspend fun refreshPlaylists() = withContext(Dispatchers.IO) {
        val key = ownerKey ?: return@withContext
        if (!YoutubeCookieJar.hasAuthCookies()) {
            playlistsState.value = emptyList()
            return@withContext
        }
        runCatching {
            val response = innerTubeApi.browseLibraryPlaylists()
            playlistsState.value = YoutubePlaylistParser.parsePlaylists(response, key)
        }.onFailure {
            playlistsState.value = emptyList()
        }
    }

    suspend fun getPlaylistTracks(playlistId: String): List<PlaylistTrackEntity> =
        withContext(Dispatchers.IO) {
            if (!YoutubeCookieJar.hasAuthCookies()) return@withContext emptyList()
            val youtubeId = PlaylistIds.stripYoutubePrefix(playlistId)
            runCatching {
                val response = innerTubeApi.browsePlaylistItems(youtubeId)
                YoutubePlaylistParser.parsePlaylistItems(response, playlistId)
            }.getOrDefault(emptyList())
        }

    companion object {
        @Volatile
        private var instance: YoutubeRemoteDataSource? = null

        fun getInstance(): YoutubeRemoteDataSource =
            instance ?: synchronized(this) {
                instance ?: YoutubeRemoteDataSource().also { instance = it }
            }
    }
}
