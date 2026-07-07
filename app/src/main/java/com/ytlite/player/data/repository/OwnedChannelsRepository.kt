package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.OwnedYoutubeChannel
import com.ytlite.player.data.remote.youtube.YoutubeDataApiClient

class OwnedChannelsRepository(
    private val authRepository: AuthRepository,
    private val dataApiClient: YoutubeDataApiClient = YoutubeDataApiClient.getInstance(),
) {
    suspend fun fetchOwnedChannels(): Result<List<OwnedYoutubeChannel>> {
        val token = authRepository.getGoogleProviderAccessToken()
            ?: return Result.failure(IllegalStateException("未获取 YouTube 授权"))
        if (!dataApiClient.isConfigured) {
            return Result.failure(IllegalStateException("YouTube Data API 未配置"))
        }
        val channels = dataApiClient.listOwnedChannels(token)
            ?: return Result.failure(IllegalStateException("无法加载频道列表"))
        return Result.success(channels)
    }

    companion object {
        @Volatile
        private var instance: OwnedChannelsRepository? = null

        fun getInstance(context: Context): OwnedChannelsRepository =
            instance ?: synchronized(this) {
                instance ?: OwnedChannelsRepository(
                    authRepository = AuthRepository.getInstance(context.applicationContext),
                ).also { instance = it }
            }
    }
}
