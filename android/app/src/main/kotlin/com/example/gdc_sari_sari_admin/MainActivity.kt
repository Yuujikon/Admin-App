package com.example.gdc_sari_sari_admin

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main activity for the GDC Sari-Sari Store Admin Android application.
 *
 * Configures the Flutter engine and establishes platform channel communication
 * for native kiosk mode / Android lock task controls.
 */
class MainActivity : FlutterActivity() {
    /**
     * Platform method channel identifier for native kiosk mode interop.
     */
    private val CHANNEL = "com.gdc.sari_sari/kiosk"

    /**
     * Configures the [FlutterEngine] instance and registers method call handlers.
     *
     * Handles the following platform messages from Flutter ([com.gdc.sari_sari/kiosk]):
     * - `startLockTask`: Enters Android Screen Pinning / Lock Task mode to pin the app interface.
     * - `stopLockTask`: Exits Android Screen Pinning / Lock Task mode.
     *
     * @param flutterEngine The [FlutterEngine] instance initialized for this activity.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLockTask" -> {
                    try {
                        startLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_TASK_ERROR", e.message, null)
                    }
                }
                "stopLockTask" -> {
                    try {
                        stopLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_TASK_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
