package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "tracks")
data class TrackEntity(
    @PrimaryKey val trackId: String,
    val title: String,
    val durationSeconds: Int = 0,
    val durationText: String? = null,
    val thumbnailLow: String? = null,
    val thumbnailMedium: String? = null,
    val thumbnailHigh: String? = null,
    val viewCount: Long = 0L,
    val viewCountText: String? = null,
    val publishedText: String? = null,
    val primaryArtistId: String? = null,
    val primaryArtistName: String? = null,
) {
    companion object {
        /** Prefer a real title; never let blank / video-id placeholders wipe catalogue names. */
        fun mergeTitle(incoming: String, existing: String?, trackId: String): String {
            val next = incoming.trim()
            val prev = existing?.trim().orEmpty()
            if (next.isNotEmpty() && next != trackId) return next
            if (prev.isNotEmpty()) return prev
            return next.ifEmpty { trackId }
        }

        fun mergeFromRemote(existing: TrackEntity?, remote: TrackEntity): TrackEntity {
            val trackId = remote.trackId
            return TrackEntity(
                trackId = trackId,
                title = mergeTitle(remote.title, existing?.title, trackId),
                durationSeconds = remote.durationSeconds.takeIf { it > 0 }
                    ?: existing?.durationSeconds
                    ?: 0,
                durationText = remote.durationText ?: existing?.durationText,
                thumbnailLow = remote.thumbnailLow ?: existing?.thumbnailLow,
                thumbnailMedium = remote.thumbnailMedium ?: existing?.thumbnailMedium,
                thumbnailHigh = remote.thumbnailHigh ?: existing?.thumbnailHigh,
                viewCount = remote.viewCount.takeIf { it > 0 } ?: existing?.viewCount ?: 0L,
                viewCountText = remote.viewCountText ?: existing?.viewCountText,
                publishedText = remote.publishedText ?: existing?.publishedText,
                primaryArtistId = remote.primaryArtistId?.takeIf { it.isNotBlank() }
                    ?: existing?.primaryArtistId,
                primaryArtistName = remote.primaryArtistName?.takeIf { it.isNotBlank() }
                    ?: existing?.primaryArtistName,
            )
        }
    }
}
