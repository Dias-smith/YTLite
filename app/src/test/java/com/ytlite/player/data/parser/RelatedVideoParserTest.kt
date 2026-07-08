package com.ytlite.player.data.parser

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RelatedVideoParserTest {

    @Test
    fun parse_lockupViewModelFromSecondaryResults() {
        val response = JSONObject(
            """
            {
              "contents": {
                "twoColumnWatchNextResults": {
                  "secondaryResults": {
                    "secondaryResults": {
                      "results": [
                        {
                          "lockupViewModel": {
                            "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                            "contentId": "abc12345678",
                            "metadata": {
                              "lockupMetadataViewModel": {
                                "title": { "content": "Related Video One" },
                                "metadata": {
                                  "contentMetadataViewModel": {
                                    "metadataRows": [
                                      {
                                        "metadataParts": [
                                          { "text": { "content": "Test Channel" } },
                                          { "text": { "content": "1.2M views" } }
                                        ]
                                      }
                                    ]
                                  }
                                }
                              }
                            },
                            "contentImage": {
                              "thumbnailViewModel": {
                                "image": {
                                  "sources": [
                                    { "url": "https://i.ytimg.com/vi/abc12345678/hqdefault.jpg" }
                                  ]
                                }
                              }
                            }
                          }
                        },
                        {
                          "lockupViewModel": {
                            "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                            "contentId": "currentVideo11",
                            "metadata": {
                              "lockupMetadataViewModel": {
                                "title": { "content": "Current Video" }
                              }
                            }
                          }
                        }
                      ]
                    }
                  }
                }
              }
            }
            """.trimIndent(),
        )

        val related = RelatedVideoParser.parse(response, excludeVideoId = "currentVideo11")

        assertEquals(1, related.size)
        assertEquals("abc12345678", related[0].videoId)
        assertEquals("Related Video One", related[0].title)
        assertEquals("Test Channel", related[0].channelName)
    }

    @Test
    fun parse_fallsBackToFullTreeWhenNoSecondaryResults() {
        val response = JSONObject(
            """
            {
              "lockupViewModel": {
                "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                "contentId": "xyz98765432",
                "metadata": {
                  "lockupMetadataViewModel": {
                    "title": { "content": "Fallback Related" }
                  }
                }
              }
            }
            """.trimIndent(),
        )

        val related = RelatedVideoParser.parse(response)

        assertEquals(1, related.size)
        assertEquals("xyz98765432", related[0].videoId)
    }

    @Test
    fun countLockupViewModels_countsNestedNodes() {
        val response = JSONObject(
            """
            {
              "a": { "lockupViewModel": { "contentId": "1" } },
              "b": { "lockupViewModel": { "contentId": "2" } }
            }
            """.trimIndent(),
        )

        assertEquals(2, RelatedVideoParser.countLockupViewModels(response))
    }

    @Test
    fun parse_legacyVideoRendererStillSupported() {
        val response = JSONObject(
            """
            {
              "contents": {
                "twoColumnWatchNextResults": {
                  "secondaryResults": {
                    "secondaryResults": {
                      "results": [
                        {
                          "compactVideoRenderer": {
                            "videoId": "legacy1111111",
                            "title": { "simpleText": "Legacy Related" },
                            "shortBylineText": { "simpleText": "Legacy Channel" },
                            "thumbnail": {
                              "thumbnails": [
                                { "url": "https://i.ytimg.com/vi/legacy1111111/hqdefault.jpg" }
                              ]
                            }
                          }
                        }
                      ]
                    }
                  }
                }
              }
            }
            """.trimIndent(),
        )

        val related = RelatedVideoParser.parse(response)

        assertEquals(1, related.size)
        assertEquals("legacy1111111", related[0].videoId)
        assertTrue(related[0].title.contains("Legacy"))
    }
}
