package com.example.pms_owner_panel

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.staypass.owner/bdv_bridge"
    }

    private val bgExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> {
                        result.success(readBridgeStatus())
                    }
                    "configure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val apiBaseUrl = call.argument<String>("apiBaseUrl") ?: ""
                        val hotelId = call.argument<String>("hotelId") ?: ""
                        val bridgeToken = call.argument<String>("bridgeToken") ?: ""
                        val allowTestSources = call.argument<Boolean>("allowTestSources") ?: false

                        val prefs = applicationContext.getSharedPreferences(
                            BdvNotificationListenerService.PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        prefs.edit()
                            .putBoolean("enabled", enabled)
                            .putString("apiBaseUrl", apiBaseUrl)
                            .putString("hotelId", hotelId)
                            .putString("bridgeToken", bridgeToken)
                            .putBoolean("allowTestSources", allowTestSources)
                            .apply()

                        if (enabled && isNotificationAccessGranted() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            runCatching {
                                NotificationListenerService.requestRebind(
                                    ComponentName(
                                        applicationContext,
                                        BdvNotificationListenerService::class.java
                                    )
                                )
                            }
                        }

                        if (enabled) {
                            bgExecutor.execute {
                                BdvNotificationListenerService.flushPendingQueue(applicationContext)
                            }
                        }

                        result.success(readBridgeStatus())
                    }
                    "flushQueue" -> {
                        bgExecutor.execute {
                            BdvNotificationListenerService.flushPendingQueue(applicationContext)
                            runOnUiThread {
                                result.success(readBridgeStatus())
                            }
                        }
                    }
                    "openNotificationSettings" -> {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isNotificationAccessGranted(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false

        val myComponent = ComponentName(
            applicationContext,
            BdvNotificationListenerService::class.java
        )
        return enabledListeners.split(":").any { raw ->
            val cn = ComponentName.unflattenFromString(raw)
            cn != null && cn == myComponent
        }
    }

    private fun readBridgeStatus(): Map<String, Any?> {
        val prefs = applicationContext.getSharedPreferences(
            BdvNotificationListenerService.PREFS_NAME,
            Context.MODE_PRIVATE
        )
        return mapOf(
            "supported" to true,
            "permissionGranted" to isNotificationAccessGranted(),
            "enabled" to prefs.getBoolean("enabled", false),
            "apiBaseUrl" to (prefs.getString("apiBaseUrl", "") ?: ""),
            "hotelId" to (prefs.getString("hotelId", "") ?: ""),
            "allowTestSources" to prefs.getBoolean("allowTestSources", false),
            "forwardedCount" to prefs.getInt("forwardedCount", 0),
            "pendingQueueCount" to BdvNotificationListenerService.getPendingQueueCount(applicationContext),
            "lastEventSummary" to (prefs.getString("lastEventSummary", "") ?: ""),
            "lastForwardedAt" to (prefs.getString("lastForwardedAt", "") ?: ""),
            "lastError" to (prefs.getString("lastError", "") ?: "")
        )
    }
}
