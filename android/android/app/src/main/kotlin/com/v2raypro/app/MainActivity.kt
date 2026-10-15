package com.v2raypro.app

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.v2raypro.app/native"
    private val VPN_REQUEST_CODE = 2026
    private val NOTIFICATION_PERMISSION_CODE = 2027
    private var methodChannel: MethodChannel? = null
    private var pendingVpnResult: MethodChannel.Result? = null
    private var pendingConfigName: String = "V2RayPro"
    private var pendingHttpPort: Int = 10888
    private var pendingSocksPort: Int = 10999

    private var pendingIsTun: Boolean = true
    private var pendingNotificationTitle: String = "V2RayPro - متصل"
    private var pendingDisconnectText: String = "قطع اتصال"
    private var pendingAppRoutingMode: String = "exclusive"
    private var pendingAppRoutingList: ArrayList<String> = arrayListOf()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        V2RayVpnService.onDisconnectListener = {
            runOnUiThread {
                channel.invokeMethod("onDisconnectedFromNotification", null)
            }
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val perm = android.Manifest.permission.POST_NOTIFICATIONS
                        val granted = androidx.core.content.ContextCompat.checkSelfPermission(this, perm) == android.content.pm.PackageManager.PERMISSION_GRANTED
                        if (!granted) {
                            androidx.core.app.ActivityCompat.requestPermissions(this, arrayOf(perm), NOTIFICATION_PERMISSION_CODE)
                            result.success(false)
                        } else {
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "getNativeLibraryDir" -> {
                    result.success(applicationInfo.nativeLibraryDir)
                }
                "getXrayBinary" -> {
                    val libDir = applicationInfo.nativeLibraryDir
                    val xrayLib = File(libDir, "libxray.so")
                    if (xrayLib.exists()) {
                        result.success(xrayLib.absolutePath)
                    } else {
                        val fallback = File(applicationInfo.dataDir, "lib/libxray.so")
                        if (fallback.exists()) {
                            result.success(fallback.absolutePath)
                        } else {
                            result.success(null)
                        }
                    }
                }
                "isAnotherVpnActive" -> {
                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    var hasOtherVpn = false
                    if (!V2RayVpnService.isRunning) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val activeNetwork = cm.activeNetwork
                            val caps = cm.getNetworkCapabilities(activeNetwork)
                            if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                                hasOtherVpn = true
                            }
                        } else {
                            for (net in cm.allNetworks) {
                                val caps = cm.getNetworkCapabilities(net) ?: continue
                                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                                    hasOtherVpn = true
                                    break
                                }
                            }
                        }
                    }
                    result.success(hasOtherVpn)
                }
                "isVpnRunning" -> {
                    result.success(V2RayVpnService.isRunning)
                }
                "startVpnService" -> {
                    val configName = call.argument<String>("configName") ?: "V2RayPro"
                    val httpPort = call.argument<Int>("httpPort") ?: 10888
                    val socksPort = call.argument<Int>("socksPort") ?: 10999
                    val isTun = call.argument<Boolean>("isTun") ?: true
                    val notificationTitle = call.argument<String>("notificationTitle") ?: "V2RayPro - متصل"
                    val disconnectText = call.argument<String>("disconnectText") ?: "قطع اتصال"
                    val appRoutingMode = call.argument<String>("appRoutingMode") ?: "exclusive"
                    val appRoutingList = call.argument<ArrayList<String>>("appRoutingList") ?: arrayListOf<String>()

                    if (isTun) {
                        val prepareIntent = VpnService.prepare(this)
                        if (prepareIntent != null) {
                            pendingVpnResult = result
                            pendingConfigName = configName
                            pendingHttpPort = httpPort
                            pendingSocksPort = socksPort
                            pendingIsTun = isTun
                            pendingNotificationTitle = notificationTitle
                            pendingDisconnectText = disconnectText
                            pendingAppRoutingMode = appRoutingMode
                            pendingAppRoutingList = appRoutingList
                            startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                        } else {
                            launchVpnService(configName, httpPort, socksPort, isTun, notificationTitle, disconnectText, appRoutingMode, appRoutingList)
                            result.success(true)
                        }
                    } else {
                        // Proxy Mode: No VPN interface needed, start purely as foreground service
                        launchVpnService(configName, httpPort, socksPort, false, notificationTitle, disconnectText, appRoutingMode, appRoutingList)
                        result.success(true)
                    }
                }
                "stopVpnService" -> {
                    val stopIntent = Intent(this, V2RayVpnService::class.java).apply {
                        action = V2RayVpnService.ACTION_STOP
                    }
                    startService(stopIntent)
                    result.success(true)
                }
                "getInstalledApps" -> {
                    Thread {
                        try {
                            val pm = packageManager
                            val intent = Intent(Intent.ACTION_MAIN, null).apply {
                                addCategory(Intent.CATEGORY_LAUNCHER)
                            }
                            val resolveInfos = pm.queryIntentActivities(intent, 0)
                            val apps = ArrayList<Map<String, String>>()
                            val seen = HashSet<String>()
                            for (ri in resolveInfos) {
                                val pkg = ri.activityInfo.packageName
                                if (pkg != packageName && !seen.contains(pkg)) {
                                    seen.add(pkg)
                                    val label = ri.loadLabel(pm)?.toString() ?: pkg
                                    apps.add(mapOf("name" to label, "packageName" to pkg))
                                }
                            }
                            apps.sortBy { (it["name"] ?: "").lowercase() }
                            runOnUiThread { result.success(apps) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ERROR", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun launchVpnService(
        configName: String,
        httpPort: Int,
        socksPort: Int,
        isTun: Boolean,
        notificationTitle: String,
        disconnectText: String,
        appRoutingMode: String = "exclusive",
        appRoutingList: ArrayList<String> = arrayListOf()
    ) {
        val startIntent = Intent(this, V2RayVpnService::class.java).apply {
            action = V2RayVpnService.ACTION_START
            putExtra("configName", configName)
            putExtra("httpPort", httpPort)
            putExtra("socksPort", socksPort)
            putExtra("isTun", isTun)
            putExtra("notificationTitle", notificationTitle)
            putExtra("disconnectText", disconnectText)
            putExtra("appRoutingMode", appRoutingMode)
            putStringArrayListExtra("appRoutingList", appRoutingList)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(startIntent)
        } else {
            startService(startIntent)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == RESULT_OK) {
                launchVpnService(
                    pendingConfigName,
                    pendingHttpPort,
                    pendingSocksPort,
                    pendingIsTun,
                    pendingNotificationTitle,
                    pendingDisconnectText,
                    pendingAppRoutingMode,
                    pendingAppRoutingList
                )
                pendingVpnResult?.success(true)
            } else {
                pendingVpnResult?.success(false)
            }
            pendingVpnResult = null
        }
    }
}
