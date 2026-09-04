package com.ytlite.player.ui.home

import androidx.annotation.StringRes
import androidx.compose.runtime.Immutable
import com.ytlite.player.R
import com.ytlite.player.data.network.InnerTubeConfig

enum class FeedCategorySource {
    Search,
    MusicNewReleaseAlbums,
}

@Immutable
data class FeedCategory(
    val id: String,
    @param:StringRes val labelRes: Int,
    val searchQuery: String? = null,
    val source: FeedCategorySource = FeedCategorySource.Search,
)

object HomeCategories {
    val items: List<FeedCategory>
        get() {
            val gl = InnerTubeConfig.GL
            return listOf(
                FeedCategory(
                    id = "all",
                    labelRes = R.string.home_category_all,
                    searchQuery = null,
                ),
                FeedCategory(
                    id = "new_release",
                    labelRes = R.string.home_category_new_release,
                    source = FeedCategorySource.MusicNewReleaseAlbums,
                ),
                FeedCategory("podcasts", R.string.home_category_podcasts, localizedQuery("podcasts", gl)),
                FeedCategory("charts", R.string.home_category_charts, localizedQuery("charts", gl)),
                FeedCategory("energize", R.string.home_category_energize, localizedQuery("energize", gl)),
                FeedCategory("feel_good", R.string.home_category_feel_good, localizedQuery("feel_good", gl)),
                FeedCategory("workout", R.string.home_category_workout, localizedQuery("workout", gl)),
                FeedCategory("chill", R.string.home_category_chill, localizedQuery("chill", gl)),
                FeedCategory("party", R.string.home_category_party, localizedQuery("party", gl)),
                FeedCategory("romance", R.string.home_category_romance, localizedQuery("romance", gl)),
                FeedCategory("commute", R.string.home_category_commute, localizedQuery("commute", gl)),
                FeedCategory("focus", R.string.home_category_focus, localizedQuery("focus", gl)),
                FeedCategory("sad", R.string.home_category_sad, localizedQuery("sad", gl)),
                FeedCategory("sleep", R.string.home_category_sleep, localizedQuery("sleep", gl)),
            )
        }

    val defaultId: String = "all"

    fun find(id: String): FeedCategory? = items.firstOrNull { it.id == id }

    /** Region-aware search queries for static Home chips (InnerTube `gl`). */
    fun localizedQuery(chipId: String, region: String = InnerTubeConfig.GL): String {
        val code = region.uppercase()
        val sinosphere = setOf("CN", "TW", "HK", "SG", "MY")
        val japanese = setOf("JP")
        val korean = setOf("KR")

        if (code in sinosphere) {
            return when (chipId) {
                "podcasts" -> "播客"
                "charts" -> "音乐排行榜"
                "energize" -> "动感音乐"
                "feel_good" -> "轻松音乐"
                "workout" -> "健身音乐"
                "chill" -> "轻音乐"
                "party" -> "派对音乐"
                "romance" -> "情歌"
                "commute" -> "通勤音乐"
                "focus" -> "专注音乐"
                "sad" -> "伤感歌曲"
                "sleep" -> "助眠音乐"
                else -> chipId
            }
        }
        if (code in japanese) {
            return when (chipId) {
                "podcasts" -> "ポッドキャスト"
                "charts" -> "音楽チャート"
                "energize" -> "元気が出る曲"
                "feel_good" -> "気分が上がる曲"
                "workout" -> "ワークアウトミュージック"
                "chill" -> "チルミュージック"
                "party" -> "パーティーミュージック"
                "romance" -> "ラブソング"
                "commute" -> "通勤 BGM"
                "focus" -> "集中ミュージック"
                "sad" -> "悲しい曲"
                "sleep" -> "睡眠ミュージック"
                else -> chipId
            }
        }
        if (code in korean) {
            return when (chipId) {
                "podcasts" -> "팟캐스트"
                "charts" -> "음악 차트"
                "energize" -> "신나는 음악"
                "feel_good" -> "기분 좋은 음악"
                "workout" -> "운동 음악"
                "chill" -> "힐링 음악"
                "party" -> "파티 음악"
                "romance" -> "사랑 노래"
                "commute" -> "출퇴근 음악"
                "focus" -> "집중 음악"
                "sad" -> "슬픈 노래"
                "sleep" -> "수면 음악"
                else -> chipId
            }
        }
        return when (chipId) {
            "podcasts" -> "podcasts"
            "charts" -> "top songs chart"
            "energize" -> "energize music"
            "feel_good" -> "feel good music"
            "workout" -> "workout music"
            "chill" -> "chill music"
            "party" -> "party music"
            "romance" -> "romance music"
            "commute" -> "commute music"
            "focus" -> "focus music"
            "sad" -> "sad music"
            "sleep" -> "sleep music"
            else -> chipId
        }
    }
}
