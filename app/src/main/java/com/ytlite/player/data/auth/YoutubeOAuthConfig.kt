package com.ytlite.player.data.auth

/**
 * OAuth scope required for YouTube Data API v3 subscription endpoints.
 *
 * @see <a href="https://developers.google.com/youtube/v3/docs/subscriptions">Subscriptions API</a>
 */
object YoutubeOAuthConfig {
    const val SCOPE_YOUTUBE_READONLY = "https://www.googleapis.com/auth/youtube.readonly"
}
