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
    ANDROID_VR(
        clientName = "ANDROID_VR",
        clientVersion = "1.60.19",
        clientNameHeader = "28",
    ),
}
