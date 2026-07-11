package com.ytlite.player.data.parser

data class LyricLine(
    val text: String,
    val startMs: Long,
)

object VttLyricsParser {

    fun parse(vtt: String): List<LyricLine> {
        val lines = mutableListOf<LyricLine>()
        val blocks = vtt.split(Regex("\n\n+"))
        for (block in blocks) {
            val trimmed = block.trim()
            if (trimmed.isBlank() || trimmed.startsWith("WEBVTT") || trimmed.startsWith("NOTE")) continue
            val blockLines = trimmed.lines()
            if (blockLines.isEmpty()) continue
            val timeLineIndex = blockLines.indexOfFirst { it.contains("-->") }
            if (timeLineIndex < 0) continue
            val startMs = parseTimestamp(blockLines[timeLineIndex].substringBefore("-->").trim()) ?: continue
            val text = blockLines.drop(timeLineIndex + 1)
                .joinToString("\n")
                .replace(Regex("<[^>]+>"), "")
                .trim()
            if (text.isNotBlank()) {
                lines.add(LyricLine(text = text, startMs = startMs))
            }
        }
        return lines
    }

    private fun parseTimestamp(value: String): Long? {
        val parts = value.split(":")
        return when (parts.size) {
            3 -> {
                val hours = parts[0].toLongOrNull() ?: return null
                val minutes = parts[1].toLongOrNull() ?: return null
                val secondsParts = parts[2].split(".")
                val seconds = secondsParts[0].toLongOrNull() ?: return null
                val millis = secondsParts.getOrNull(1)?.padEnd(3, '0')?.take(3)?.toLongOrNull() ?: 0L
                ((hours * 3600 + minutes * 60 + seconds) * 1000) + millis
            }
            2 -> {
                val minutes = parts[0].toLongOrNull() ?: return null
                val secondsParts = parts[1].split(".")
                val seconds = secondsParts[0].toLongOrNull() ?: return null
                val millis = secondsParts.getOrNull(1)?.padEnd(3, '0')?.take(3)?.toLongOrNull() ?: 0L
                ((minutes * 60 + seconds) * 1000) + millis
            }
            else -> null
        }
    }
}
