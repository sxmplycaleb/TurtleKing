package com.turtleking.turtle_king

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Best-effort multicast reception for the Phase 18 LAN discovery
        // beacons. The Dart side treats a missing channel as a no-op, so a
        // failure here can never break gameplay or discovery via manual IP.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "turtle_king/multicast_lock",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    acquireMulticastLock()
                    result.success(null)
                }
                "release" -> {
                    releaseMulticastLock()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun acquireMulticastLock() {
        if (multicastLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("turtle_king").apply {
                setReferenceCounted(false)
            }
        }
        multicastLock?.acquire()
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }
}
