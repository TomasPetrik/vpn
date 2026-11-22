package com.petrixon.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat

/**
 * Foreground notification host while the WireGuard tunnel is up.
 * The actual TUN is owned by [com.wireguard.android.backend.GoBackend.VpnService].
 */
class PetrikVpnService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                ensureChannel()
                val text = intent.getStringExtra(EXTRA_TEXT) ?: "VPN connected"
                val notification = buildNotification(text)
                NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification)
                return START_STICKY
            }
            else -> {
                ensureChannel()
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Connecting…"
                val notification = buildNotification(text)
                if (Build.VERSION.SDK_INT >= 34) {
                    ServiceCompat.startForeground(
                        this,
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            }
        }
        return START_STICKY
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        // New channel id: Android never raises importance of an existing channel.
        // IMPORTANCE_LOW was delayed/hidden on some OEMs (e.g. Samsung One UI).
        val channel = NotificationChannel(
            CHANNEL_ID,
            "PetrikVPN",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "VPN connection status"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(contentText: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PetrikVPN")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    companion object {
        // v2: DEFAULT importance (v1 was LOW and often delayed on OEM skins).
        private const val CHANNEL_ID = "petrikvpn_tunnel_v2"
        private const val NOTIFICATION_ID = 42
        const val ACTION_STOP = "com.petrixon.vpn.STOP_FG"
        private const val ACTION_UPDATE = "com.petrixon.vpn.UPDATE_FG"
        private const val EXTRA_TEXT = "text"

        fun start(context: Context, text: String = "Connecting…") {
            val intent = Intent(context, PetrikVpnService::class.java)
                .putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun updateConnected(context: Context) {
            val intent = Intent(context, PetrikVpnService::class.java)
                .setAction(ACTION_UPDATE)
                .putExtra(EXTRA_TEXT, "VPN connected")
            try {
                context.startService(intent)
            } catch (_: Exception) {
                start(context, "VPN connected")
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, PetrikVpnService::class.java).setAction(ACTION_STOP)
            try {
                context.startService(intent)
            } catch (_: Exception) {
                context.stopService(Intent(context, PetrikVpnService::class.java))
            }
        }
    }
}
