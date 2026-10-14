package com.v2raypro.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.v2raypro.app/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
                else -> result.notImplemented()
            }
        }
    }
}
