package com.example.healthbridge

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import android.content.Intent
import android.net.Uri

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "health_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    // Simulate permission request
                    result.success(true)
                }
                "openHealthConnectSettings" -> {
                    try {
                        val intent = Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS")
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            // Fallback for some devices
                            val intent = Intent("android.intent.action.VIEW")
                            intent.data = Uri.parse("market://details?id=com.google.android.apps.healthdata")
                            startActivity(intent)
                            result.success(true)
                        } catch (ex: Exception) {
                            result.error("UNAVAILABLE", "Health Connect settings not available", null)
                        }
                    }
                }
                "getSteps" -> {
                    // Simulate fetching steps from Health Connect
                    result.success(5432)
                }
                "getSleepData" -> {
                    // Simulate fetching sleep hours
                    result.success(7.5)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
