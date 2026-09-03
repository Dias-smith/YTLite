package com.ytlite.player.data.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

/** Best-effort VPN detection via [NetworkCapabilities.TRANSPORT_VPN]. */
object VpnStatus {
    fun isActive(context: Context): Boolean {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return false
        return cm.allNetworks.any { network ->
            cm.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }
    }
}
