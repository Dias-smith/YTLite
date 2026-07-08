package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.R
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.OwnedYoutubeChannel
import com.ytlite.player.data.remote.youtube.YoutubeDataApiClient

class OwnedChannelsRepository(
    private val appContext: Context,
    private val authRepository: AuthRepository,
    private val dataApiClient: YoutubeDataApiClient = YoutubeDataApiClient.getInstance(),
) {
    suspend fun fetchOwnedChannels(): Result<List<OwnedYoutubeChannel>> {
        val token = authRepository.getGoogleProviderAccessToken()
            ?: return Result.failure(
                IllegalStateException(appContext.getString(R.string.error_youtube_auth_missing)),
            )
        if (!dataApiClient.isConfigured) {
            return Result.failure(
                IllegalStateException(appContext.getString(R.string.error_youtube_api_not_configured)),
            )
        }
        val channels = dataApiClient.listOwnedChannels(token)
            ?: return Result.failure(
                IllegalStateException(appContext.getString(R.string.error_load_channels_failed)),
            )
        return Result.success(channels)
    }

    companion object {
        @Volatile
        private var instance: OwnedChannelsRepository? = null

        fun getInstance(context: Context): OwnedChannelsRepository =
            instance ?: synchronized(this) {
                instance ?: OwnedChannelsRepository(
                    appContext = context.applicationContext,
                    authRepository = AuthRepository.getInstance(context.applicationContext),
                ).also { instance = it }
            }
    }
}
