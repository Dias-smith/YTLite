package com.ytlite.player.data.network

enum class InnerTubeClientType(
    val clientName: String,
    val clientVersion: String,
    val clientNameHeader: String,
) {
    WEB(
        clientName = "WEB",
        clientVersion = "2.20260701.01.00",
        clientNameHeader = "1",
    ),
    /** YouTube Music web client (music.youtube.com). */
    WEB_REMIX(
        clientName = "WEB_REMIX",
        clientVersion = "1.20250317.01.00",
        clientNameHeader = "67",
    ),
}
