package com.v2raypro.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat

class V2RayVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.v2raypro.app.VPN_START"
        const val ACTION_STOP = "com.v2raypro.app.VPN_STOP"
        const val ACTION_DISCONNECT = "com.v2raypro.app.VPN_DISCONNECT"
        const val CHANNEL_ID = "v2raypro_vpn_channel"
        const val NOTIFICATION_ID = 1001

        var isRunning = false
            private set

        var onDisconnectListener: (() -> Unit)? = null
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var wakeLock: android.os.PowerManager.WakeLock? = null

    private val disconnectReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            stopVpn()
            onDisconnectListener?.invoke()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        val filter = IntentFilter(ACTION_DISCONNECT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(disconnectReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(disconnectReceiver, filter)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP || action == ACTION_DISCONNECT) {
            stopVpn()
            if (action == ACTION_DISCONNECT) {
                onDisconnectListener?.invoke()
            }
            return START_NOT_STICKY
        }

        if (action == ACTION_START) {
            val configName = intent.getStringExtra("configName") ?: "V2RayPro"
            val httpPort = intent.getIntExtra("httpPort", 10888)
            val socksPort = intent.getIntExtra("socksPort", 10999)
            val isTun = intent.getBooleanExtra("isTun", true)
            val notificationTitle = intent.getStringExtra("notificationTitle") ?: "V2RayPro - متصل"
            val disconnectText = intent.getStringExtra("disconnectText") ?: "قطع اتصال"
            val appRoutingMode = intent.getStringExtra("appRoutingMode") ?: "exclusive"
            val appRoutingList = intent.getStringArrayListExtra("appRoutingList") ?: arrayListOf<String>()

            startVpn(configName, httpPort, socksPort, isTun, notificationTitle, disconnectText, appRoutingMode, appRoutingList)
            return START_STICKY
        }

        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "V2RayPro VPN"
            val descriptionText = "Active VPN Connection Notification"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(
        configName: String,
        notificationTitle: String,
        disconnectText: String
    ): Notification {
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val mainPendingIntent = PendingIntent.getActivity(
            this, 0, mainIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val disconnectIntent = Intent(ACTION_DISCONNECT).setPackage(packageName)
        val disconnectPendingIntent = PendingIntent.getBroadcast(
            this, 1, disconnectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(notificationTitle)
            .setContentText(configName)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true) // User cannot swipe away until disconnected
            .setContentIntent(mainPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                disconnectText,
                disconnectPendingIntent
            )
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun startVpn(
        configName: String,
        httpPort: Int,
        socksPort: Int,
        isTun: Boolean,
        notificationTitle: String,
        disconnectText: String,
        appRoutingMode: String = "exclusive",
        appRoutingList: ArrayList<String> = arrayListOf()
    ) {
        val notification = createNotification(configName, notificationTitle, disconnectText)
        startForeground(NOTIFICATION_ID, notification)

        try {
            val pm = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
            wakeLock = pm?.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "V2RayPro:VpnWakeLock")
            wakeLock?.acquire(24 * 60 * 60 * 1000L) // 24h safety limit
        } catch (_: Exception) {}

        if (isTun) {
            try {
                val builder = Builder()
                    .setSession("V2RayPro: $configName")
                    .addAddress("26.26.26.1", 24)
                    .addRoute("0.0.0.0", 0)
                    .addDnsServer("1.1.1.1")
                    .addDnsServer("8.8.8.8")
                    .setMtu(8500)


                if (appRoutingMode == "inclusive" && appRoutingList.isNotEmpty()) {
                    // Inclusive mode: ONLY the selected applications are routed through the VPN tunnel.
                    // All other apps bypass the tunnel and connect directly.
                    // Note: Our own package is NOT added to allowed list, so Xray core connections
                    // bypass the VPN automatically without loopback recursion!
                    for (pkg in appRoutingList) {
                        try {
                            builder.addAllowedApplication(pkg)
                        } catch (_: Exception) {}
                    }
                } else {
                    // Exclusive mode (default): Selected applications bypass the VPN tunnel.
                    // Our own package MUST be excluded so Xray loopback doesn't cause recursion.
                    try {
                        builder.addDisallowedApplication(packageName)
                    } catch (_: Exception) {}

                    for (pkg in appRoutingList) {
                        if (pkg != packageName) {
                            try {
                                builder.addDisallowedApplication(pkg)
                            } catch (_: Exception) {}
                        }
                    }
                }

                val pfd = builder.establish()
                vpnInterface = pfd
                if (pfd != null) {
                    val tunConfig = java.io.File(cacheDir, "tunnel.yaml")
                    val configContent = """
tunnel:
  mtu: 8500
  ipv4: 26.26.26.1

socks5:
  port: $socksPort
  address: 127.0.0.1
  udp: 'udp'

misc:
  log-level: warn
""".trimIndent()
                    tunConfig.writeText(configContent)

                    hev.htproxy.TProxyService.TProxyStartService(tunConfig.absolutePath, pfd.fd)
                }
                isRunning = true
            } catch (e: Exception) {
                e.printStackTrace()
                stopVpn()
            }
        } else {
            // Proxy Mode: No VPN tunnel is established; VPN key icon does NOT appear!
            vpnInterface = null
            isRunning = true
        }
    }

    private fun stopVpn() {
        isRunning = false
        try {
            hev.htproxy.TProxyService.TProxyStopService()
        } catch (_: Exception) {}
        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (_: Exception) {}

        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        wakeLock = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep foreground service active when app is swiped from recents!
        // Do NOT call stopVpn() here!
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(disconnectReceiver)
        } catch (_: Exception) {}
        stopVpn()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopVpn()
        onDisconnectListener?.invoke()
        super.onRevoke()
    }
}
