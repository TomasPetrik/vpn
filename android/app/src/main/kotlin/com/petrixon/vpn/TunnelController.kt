package com.petrixon.vpn

import android.content.Context
import android.net.Uri
import android.util.Log
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import com.wireguard.config.Interface
import com.wireguard.config.Peer
import com.wireguard.crypto.Key
import org.json.JSONArray
import org.json.JSONObject

/**
 * Owns wstunnel + WireGuard GoBackend lifecycle for the app process.
 */
class TunnelController(context: Context) {
    private val appContext = context.applicationContext
    private val keyStore = WireGuardKeyStore(appContext)
    private val backend = GoBackend(appContext)
    private val tunnel = object : Tunnel {
        override fun getName(): String = TUNNEL_NAME
        override fun onStateChange(newState: Tunnel.State) {
            extensionStatus = when (newState) {
                Tunnel.State.UP -> "wireguard_started"
                Tunnel.State.DOWN -> "disconnected"
                Tunnel.State.TOGGLE -> extensionStatus
            }
            Log.i(TAG, "tunnel state → $newState")
        }
    }

    @Volatile
    var extensionStatus: String = "disconnected"
        private set

    @Volatile
    private var peerPublicKey: Key? = null

    @Volatile
    private var running = false

    fun getPublicKey(): String = keyStore.getOrCreatePublicKey()

    @Synchronized
    fun start(config: Map<String, Any?>) {
        if (running) {
            stop()
        }
        // Show the FGS notification immediately — before wstunnel/WG work — so the
        // user sees status as soon as connect starts (not ~seconds after "connected").
        PetrikVpnService.start(appContext)
        try {
            extensionStatus = "starting_transport"
            val wstJson = buildWstunnelJson(config)
            Log.i(TAG, "wstunnel start $wstJson")
            WstunnelFfi.start(wstJson)
            extensionStatus = "wstunnel_started"

            extensionStatus = "starting_wireguard"
            val wgConfig = buildWireGuardConfig(config)
            backend.setState(tunnel, Tunnel.State.UP, wgConfig)
            running = true
            extensionStatus = "wireguard_started"
            PetrikVpnService.updateConnected(appContext)
            Log.i(TAG, "tunnel up")
        } catch (e: Exception) {
            PetrikVpnService.stop(appContext)
            extensionStatus = "disconnected"
            running = false
            throw e
        }
    }

    @Synchronized
    fun stop() {
        extensionStatus = "disconnecting"
        try {
            backend.setState(tunnel, Tunnel.State.DOWN, null)
        } catch (e: Exception) {
            Log.w(TAG, "WireGuard stop: ${e.message}")
        }
        try {
            if (WstunnelFfi.isRunning()) {
                WstunnelFfi.stop()
            }
        } catch (e: Exception) {
            Log.w(TAG, "wstunnel stop: ${e.message}")
        }
        running = false
        peerPublicKey = null
        extensionStatus = "disconnected"
        PetrikVpnService.stop(appContext)
        Log.i(TAG, "tunnel down")
    }

    fun vpnStatus(): String {
        return try {
            when (backend.getState(tunnel)) {
                Tunnel.State.UP -> "connected"
                Tunnel.State.DOWN -> "disconnected"
                Tunnel.State.TOGGLE -> "connecting"
            }
        } catch (_: Exception) {
            if (running) "connected" else "disconnected"
        }
    }

    fun trafficStats(): Map<String, Any?> {
        if (vpnStatus() != "connected") {
            return emptyMap()
        }
        return try {
            val stats = backend.getStatistics(tunnel)
            val peerStats = peerPublicKey?.let { stats.peer(it) }
            val rx = peerStats?.rxBytes() ?: stats.totalRx()
            val tx = peerStats?.txBytes() ?: stats.totalTx()
            val handshakeSec = peerStats
                ?.latestHandshakeEpochMillis()
                ?.takeIf { it > 0L }
                ?.div(1000L)
            buildMap {
                put("rx_bytes", rx)
                put("tx_bytes", tx)
                if (handshakeSec != null && handshakeSec > 0) {
                    put("last_handshake_sec", handshakeSec)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "stats: ${e.message}")
            emptyMap()
        }
    }

    private fun buildWstunnelJson(config: Map<String, Any?>): String {
        val serverIps = stringList(config["server_ips"])
        val serverIp = serverIps.firstOrNull()?.trim().orEmpty()
        require(serverIp.isNotEmpty()) { "server_ips required" }
        val pathPrefix = (config["path_prefix"] as? String)?.trim()?.trim('/')
            .orEmpty()
        require(pathPrefix.isNotEmpty()) { "path_prefix required" }
        val remote = (config["remote"] as? String)?.takeIf { it.isNotBlank() }
            ?: "127.0.0.1:51821"
        val url = (config["transport_url"] as? String)
            ?: (config["url"] as? String)
            ?: "wss://vpn.radarcut.com"
        val tlsSni = try {
            Uri.parse(url).host?.takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        } ?: "vpn.radarcut.com"

        return JSONObject()
            .put("server_ip", serverIp)
            .put("tls_sni", tlsSni)
            .put("path_prefix", pathPrefix)
            .put("remote", remote)
            .put("local_udp", LOCAL_ENDPOINT)
            .put("url", url)
            .put("tls_verify_certificate", true)
            .toString()
    }

    private fun buildWireGuardConfig(config: Map<String, Any?>): Config {
        val privateKey = keyStore.loadPrivateKey()
        val ifaceBuilder = Interface.Builder().parsePrivateKey(privateKey.toBase64())
        for (addr in stringList(config["addresses"])) {
            ifaceBuilder.parseAddresses(addr)
        }
        val dns = stringList(config["dns"])
        if (dns.isNotEmpty()) {
            ifaceBuilder.parseDnsServers(dns.joinToString(", "))
        }
        val mtu = when (val raw = config["mtu"]) {
            is Number -> raw.toInt()
            is String -> raw.toIntOrNull()
            else -> null
        }
        if (mtu != null && mtu > 0) {
            ifaceBuilder.setMtu(mtu)
        }

        val serverPublicKey = (config["server_public_key"] as? String).orEmpty()
        require(serverPublicKey.isNotEmpty()) { "server_public_key required" }
        peerPublicKey = Key.fromBase64(serverPublicKey)

        val allowed = stringList(config["allowed_ips"]).ifEmpty { listOf("0.0.0.0/0", "::/0") }
        val excluded = stringList(config["excluded_ips"])
        val carved = Ipv4RouteCarver.applyExclusions(allowed, excluded)
        // Keep IPv6 catch-all if present; carving is IPv4-only.
        val finalAllowed = carved.ifEmpty { allowed }

        val peerBuilder = Peer.Builder()
            .parsePublicKey(serverPublicKey)
            .setEndpoint(com.wireguard.config.InetEndpoint.parse(LOCAL_ENDPOINT))
        for (cidr in finalAllowed) {
            peerBuilder.parseAllowedIPs(cidr)
        }
        val keepalive = when (val raw = config["persistent_keepalive"]) {
            is Number -> raw.toInt()
            is String -> raw.toIntOrNull()
            else -> 25
        } ?: 25
        if (keepalive > 0) {
            peerBuilder.setPersistentKeepalive(keepalive)
        }

        return Config.Builder()
            .setInterface(ifaceBuilder.build())
            .addPeer(peerBuilder.build())
            .build()
    }

    private fun stringList(raw: Any?): List<String> {
        return when (raw) {
            is List<*> -> raw.mapNotNull { it?.toString()?.takeIf { s -> s.isNotBlank() } }
            is JSONArray -> (0 until raw.length()).mapNotNull {
                raw.optString(it)?.takeIf { s -> s.isNotBlank() }
            }
            is String -> raw.split(',').map { it.trim() }.filter { it.isNotEmpty() }
            else -> emptyList()
        }
    }

    companion object {
        private const val TAG = "PetrikTunnel"
        private const val TUNNEL_NAME = "petrikvpn"
        private const val LOCAL_ENDPOINT = "127.0.0.1:51820"

        @Volatile
        private var instance: TunnelController? = null

        fun get(context: Context): TunnelController {
            return instance ?: synchronized(this) {
                instance ?: TunnelController(context).also { instance = it }
            }
        }
    }
}
