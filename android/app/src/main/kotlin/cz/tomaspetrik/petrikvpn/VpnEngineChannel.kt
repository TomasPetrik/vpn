package cz.tomaspetrik.petrikvpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Mirrors iOS [VpnEngineChannel]: MethodChannel `vpn_engine` + EventChannel `vpn_engine/status`.
 */
class VpnEngineChannel(
    messenger: BinaryMessenger,
    private val activity: Activity,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methodChannel = MethodChannel(messenger, CHANNEL_NAME)
    private val statusChannel = EventChannel(messenger, STATUS_CHANNEL_NAME)
    private val controller = TunnelController.get(activity)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private var eventSink: EventChannel.EventSink? = null
    private var lastEmittedKey: String? = null

    var pendingPrepareResult: MethodChannel.Result? = null

    init {
        methodChannel.setMethodCallHandler(this)
        statusChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPublicKey" -> {
                executor.execute {
                    try {
                        val key = controller.getPublicKey()
                        mainHandler.post {
                            result.success(mapOf("public_key" to key))
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("key_error", e.message, null)
                        }
                    }
                }
            }
            "prepare" -> prepareVpn(result)
            "startTunnel" -> {
                @Suppress("UNCHECKED_CAST")
                val config = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                executor.execute {
                    try {
                        controller.start(config)
                        emitStatus(force = true)
                        mainHandler.post {
                            result.success(
                                mapOf(
                                    "ok" to true,
                                    "status" to controller.vpnStatus(),
                                    "message" to "WireGuard + wstunnel started",
                                ),
                            )
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "status" to "error",
                                    "message" to (e.message ?: "startTunnel failed"),
                                ),
                            )
                        }
                    }
                }
            }
            "stopTunnel" -> {
                executor.execute {
                    try {
                        controller.stop()
                        emitStatus(force = true)
                        mainHandler.post {
                            result.success(
                                mapOf(
                                    "ok" to true,
                                    "message" to "stopTunnel requested",
                                ),
                            )
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "message" to (e.message ?: "stopTunnel failed"),
                                ),
                            )
                        }
                    }
                }
            }
            "getStatus" -> {
                executor.execute {
                    val payload = statusPayload()
                    mainHandler.post { result.success(payload) }
                }
            }
            "extensionLog" -> result.success(mapOf("lines" to emptyList<String>()))
            else -> result.notImplemented()
        }
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        val prepareIntent = VpnService.prepare(activity)
        if (prepareIntent == null) {
            result.success(
                mapOf(
                    "granted" to true,
                    "status" to "ready",
                    "message" to "VPN permission already granted",
                ),
            )
            return
        }
        pendingPrepareResult = result
        activity.startActivityForResult(prepareIntent, PREPARE_REQUEST_CODE)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != PREPARE_REQUEST_CODE) {
            return false
        }
        val pending = pendingPrepareResult ?: return true
        pendingPrepareResult = null
        if (resultCode == Activity.RESULT_OK) {
            pending.success(
                mapOf(
                    "granted" to true,
                    "status" to "ready",
                    "message" to "VPN permission granted",
                ),
            )
        } else {
            pending.success(
                mapOf(
                    "granted" to false,
                    "status" to "denied",
                    "message" to "VPN permission denied",
                ),
            )
        }
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emitStatus(force = true)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        lastEmittedKey = null
    }

    private fun statusPayload(): Map<String, Any?> {
        val status = controller.vpnStatus()
        val extensionStatus = controller.extensionStatus
        val payload = linkedMapOf<String, Any?>(
            "status" to status,
            "extension_status" to extensionStatus,
            "extension_log" to emptyList<String>(),
        )
        payload.putAll(controller.trafficStats())
        return payload
    }

    private fun emitStatus(force: Boolean = false) {
        val sink = eventSink ?: return
        val payload = statusPayload()
        val key = "${payload["status"]}|${payload["extension_status"]}"
        if (!force && key == lastEmittedKey) {
            return
        }
        lastEmittedKey = key
        mainHandler.post { sink.success(payload) }
    }

    companion object {
        const val CHANNEL_NAME = "vpn_engine"
        const val STATUS_CHANNEL_NAME = "vpn_engine/status"
        const val PREPARE_REQUEST_CODE = 9911
    }
}
