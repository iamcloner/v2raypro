package com.v2raypro.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.v2raypro.app/vpn"
    private val VPN_REQUEST_CODE = 2001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        pendingResult = result
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                    } else {
                        startVpnService()
                        result.success(true)
                    }
                }
                "stopVpn" -> {
                    val intent = Intent(this, V2RayVpnService::class.java).apply {
                        action = "STOP"
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startVpnService() {
        val intent = Intent(this, V2RayVpnService::class.java)
        startService(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                startVpnService()
                pendingResult?.success(true)
            } else {
                pendingResult?.error("PERMISSION_DENIED", "User denied VPN permission", null)
            }
            pendingResult = null
        }
    }
}
