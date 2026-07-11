package com.ytlite.player.ui.trackaction

import com.ytlite.player.data.model.TrackMetadataSeed

fun TrackActionContext.toMetadataSeed() = TrackMetadataSeed(
    trackId = videoId,
    title = title,
    artistName = channelName,
    thumbnailUrl = thumbnailUrl,
    album = album,
    year = year,
    channelId = channelId,
)
