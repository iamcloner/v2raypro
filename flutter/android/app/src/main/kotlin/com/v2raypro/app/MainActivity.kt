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
    private var methodChannel: MethodChannel? = null
    private var pendingVpnResult: MethodChannel.Result? = null
    private var pendingConfigName: String = "V2RayPro"
    private var pendingHttpPort: Int = 10888

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
                "startVpnService" -> {
                    val configName = call.argument<String>("configName") ?: "V2RayPro"
                    val httpPort = call.argument<Int>("httpPort") ?: 10888
                    val prepareIntent = VpnService.prepare(this)
                    if (prepareIntent != null) {
                        pendingVpnResult = result
                        pendingConfigName = configName
                        pendingHttpPort = httpPort
                        startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                    } else {
                        launchVpnService(configName, httpPort)
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

    private fun launchVpnService(configName: String, httpPort: Int) {
        val startIntent = Intent(this, V2RayVpnService::class.java).apply {
            action = V2RayVpnService.ACTION_START
            putExtra("configName", configName)
            putExtra("httpPort", httpPort)
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
                launchVpnService(pendingConfigName, pendingHttpPort)
                pendingVpnResult?.success(true)
            } else {
                pendingVpnResult?.success(false)
            }
            pendingVpnResult = null
        }
    }
}
