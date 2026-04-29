package com.example.healthbridge

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
