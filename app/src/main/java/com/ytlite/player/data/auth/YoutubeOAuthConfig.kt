package com.ytlite.player.data.auth

/**
 * OAuth scope required for YouTube Data API v3 subscription endpoints.
 *
 * Requested client-side via [AuthRepository.signInWithGoogleOAuth].
 *
 * Also add this scope in **Google Cloud Console → OAuth consent screen → Data Access (Scopes)**.
 *
 * @see <a href="https://developers.google.com/youtube/v3/docs/subscriptions">Subscriptions API</a>
 */
object YoutubeOAuthConfig {
    const val SCOPE_YOUTUBE_READONLY = "https://www.googleapis.com/auth/youtube.readonly"
}
