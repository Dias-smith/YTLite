package com.ytlite.player.data.remote.youtube

import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

class YoutubeRemoteDataSource(
    private val dataApiClient: YoutubeDataApiClient = YoutubeDataApiClient.getInstance(),
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

    suspend fun refreshPlaylists(oauthAccessToken: String?) = withContext(Dispatchers.IO) {
        val key = ownerKey
        if (key == null) {
            YoutubeDiagnostics.logPlaylistsFetchOutcome(
                step = "Playlists/Remote",
                outcome = "skipped",
                detail = "ownerKey=null",
            )
            return@withContext
        }
        if (oauthAccessToken.isNullOrBlank()) {
            YoutubeDiagnostics.logPlaylistsFetchOutcome(
                step = "Playlists/Remote",
                outcome = "skipped",
                detail = "oauthAccessToken missing ownerKey=$key",
            )
            playlistsState.value = emptyList()
            return@withContext
        }
        if (!dataApiClient.isConfigured) {
            YoutubeDiagnostics.logPlaylistsFetchOutcome(
                step = "Playlists/Remote",
                outcome = "skipped",
                detail = "YOUTUBE_DATA_API_KEY not configured ownerKey=$key",
            )
            playlistsState.value = emptyList()
            return@withContext
        }
        runCatching {
            val playlists = dataApiClient.listOwnedPlaylists(
                oauthAccessToken = oauthAccessToken,
                ownerKey = key,
            )
            if (playlists == null) {
                YoutubeDiagnostics.logPlaylistsFetchOutcome(
                    step = "Playlists/Remote",
                    outcome = "failed",
                    detail = "listOwnedPlaylists returned null ownerKey=$key",
                )
                playlistsState.value = emptyList()
            } else {
                YoutubeDiagnostics.logPlaylistsFetchOutcome(
                    step = "Playlists/Remote",
                    outcome = "success",
                    detail = "count=${playlists.size} ownerKey=$key ids=${playlists.map { it.playlistId }}",
                )
                playlistsState.value = playlists
            }
        }.onFailure { error ->
            YoutubeDiagnostics.e(
                step = "Playlists/Remote",
                message = "refreshPlaylists exception ownerKey=$key: ${error.message}",
                throwable = error,
            )
            playlistsState.value = emptyList()
        }
    }

    suspend fun getPlaylistTracks(
        playlistId: String,
        oauthAccessToken: String?,
    ): List<PlaylistTrackEntity> = withContext(Dispatchers.IO) {
        if (oauthAccessToken.isNullOrBlank() || !dataApiClient.isConfigured) {
            return@withContext emptyList()
        }
        dataApiClient.listPlaylistItems(oauthAccessToken, playlistId) ?: emptyList()
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
