package com.ytlite.player.data.parser

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RelatedVideoParserMusicTest {

    @Test
    fun parse_musicRadioPlaylistPanel_excludesCurrentAndMapsItems() {
        val response = JSONObject(
            """
            {
              "contents": {
                "singleColumnMusicWatchNextResultsRenderer": {
                  "tabbedRenderer": {
                    "watchNextTabbedResultsRenderer": {
                      "tabs": [{
                        "tabRenderer": {
                          "content": {
                            "musicQueueRenderer": {
                              "content": {
                                "playlistPanelRenderer": {
                                  "contents": [
                                    {
                                      "playlistPanelVideoRenderer": {
                                        "title": { "runs": [{ "text": "Current Song" }] },
                                        "longBylineText": { "runs": [{ "text": "Artist A" }] },
                                        "lengthText": { "runs": [{ "text": "3:00" }] },
                                        "thumbnail": { "thumbnails": [{ "url": "https://i.ytimg.com/vi/cur/hqdefault.jpg" }] },
                                        "navigationEndpoint": { "watchEndpoint": { "videoId": "cur" } },
                                        "selected": true
                                      }
                                    },
                                    {
                                      "playlistPanelVideoRenderer": {
                                        "title": { "runs": [{ "text": "Related Song" }] },
                                        "longBylineText": {
                                          "runs": [
                                            { "text": "Artist B", "navigationEndpoint": { "browseEndpoint": { "browseId": "UCabc" } } },
                                            { "text": " · " },
                                            { "text": "1.2M views" }
                                          ]
                                        },
                                        "lengthText": { "runs": [{ "text": "2:10" }] },
                                        "thumbnail": { "thumbnails": [{ "url": "https://i.ytimg.com/vi/rel/hqdefault.jpg" }] },
                                        "navigationEndpoint": { "watchEndpoint": { "videoId": "rel" } }
                                      }
                                    }
                                  ]
                                }
                              }
                            }
                          }
                        }
                      }]
                    }
                  }
                }
              }
            }
            """.trimIndent(),
        )

        val parsed = RelatedVideoParser.parse(response, excludeVideoId = "cur")
        assertEquals(1, parsed.size)
        assertEquals("rel", parsed[0].videoId)
        assertEquals("Related Song", parsed[0].title)
        assertEquals("Artist B", parsed[0].channelName)
        assertEquals("UCabc", parsed[0].channelId)
        assertEquals("2:10", parsed[0].durationText)
        assertTrue(parsed[0].viewCountText!!.contains("views"))
    }
}
