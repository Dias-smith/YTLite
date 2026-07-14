package com.ytlite.player.data.network

object InnerTubeConfig {
    const val API_KEY = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    const val MUSIC_API_KEY = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    const val BASE_URL = "https://www.youtube.com"
    const val MUSIC_BASE_URL = "https://music.youtube.com"

    val FEED_CLIENT = InnerTubeClientType.WEB
    val MUSIC_CLIENT = InnerTubeClientType.WEB_REMIX

    const val HL = "en"
    const val GL = "US"

    const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    const val BROWSE_ID_HOME = "FEwhat_to_watch"
    const val BROWSE_ID_LIBRARY = "FEmy_youtube"
    const val BROWSE_ID_TRENDING = "FEtrending"
    const val BROWSE_ID_EXPLORE = "FEtopics_base"
    const val BROWSE_ID_CHARTS = "FEmusic_charts"
    /** YouTube Music new-release albums ([music.youtube.com/new_releases/albums](https://music.youtube.com/new_releases/albums)). */
    const val BROWSE_ID_MUSIC_NEW_RELEASES_ALBUMS = "FEmusic_new_releases_albums"

    const val SEARCH_PARAMS_VIDEOS = "EgIQAQ%3D%3D"
    const val SEARCH_PARAMS_CHANNELS = "EgIQAg%3D%3D"
    /** InnerTube filter type=3 (playlist). Note: EgIQAUAB is videos+extra, not playlists. */
    const val SEARCH_PARAMS_PLAYLISTS = "EgIQAw%3D%3D"

    val BROWSE_URL: String
        get() = "$BASE_URL/youtubei/v1/browse?key=$API_KEY"

    val SEARCH_URL: String
        get() = "$BASE_URL/youtubei/v1/search?key=$API_KEY"

    val NEXT_URL: String
        get() = "$BASE_URL/youtubei/v1/next?key=$API_KEY"

    val MUSIC_NEXT_URL: String
        get() = "$MUSIC_BASE_URL/youtubei/v1/next?key=$MUSIC_API_KEY"

    val MUSIC_BROWSE_URL: String
        get() = "$MUSIC_BASE_URL/youtubei/v1/browse?key=$MUSIC_API_KEY"

    /** YouTube searchbox autocomplete (query strings, not video results). */
    const val SUGGEST_QUERIES_BASE_URL =
        "https://suggestqueries.google.com/complete/search?client=firefox&ds=yt"
}
