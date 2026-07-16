package com.ytlite.player.data.search

/**
 * Normalizes Data API music titles into short search-chip keywords
 * (strip brackets / official-video noise).
 */
object HotKeywordTitle {
    private val bracketPatterns = listOf(
        Regex("""\([^)]*\)"""),
        Regex("""\[[^\]]*\]"""),
        Regex("""【[^】]*】"""),
        Regex("""（[^）]*）"""),
    )
    private val noiseSegment = Regex(
        """^(?i)(official(\s+(music|lyric|audio))?(\s+video)?|lyrics?(\s+video)?|audio|mv|hd|4k|8k|remaster(ed)?|visualizer|theme\s+song)$""",
    )
    private val trailingSep = Regex("""[\s|\-–—:·]+$""")
    private val midSep = Regex("""\s*[|\-–—]\s*""")
    private val spaces = Regex("""\s+""")

    fun clean(raw: String): String? {
        var text = raw.trim()
        if (text.isEmpty()) return null

        repeat(4) {
            var next = text
            for (pattern in bracketPatterns) {
                next = next.replace(pattern, " ")
            }
            next = collapseSpaces(next)
            if (next == text) return@repeat
            text = next
        }

        while (true) {
            val last = midSep.findAll(text).lastOrNull() ?: break
            val tail = text.substring(last.range.last + 1).trim()
            if (noiseSegment.matches(tail)) {
                text = text.substring(0, last.range.first).trim()
            } else {
                break
            }
        }

        text = text.replace(trailingSep, "").let(::collapseSpaces)
        return text.takeIf { it.length >= 2 }
    }

    private fun collapseSpaces(value: String): String =
        value.replace(spaces, " ").trim()
}
