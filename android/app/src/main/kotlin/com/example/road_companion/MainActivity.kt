package com.example.road_companion

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CONTROL_CHANNEL = "es.estela/bridge_controls"
    private val EVENT_CHANNEL = "es.estela/navigation_notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Canal de control para verificación de permisos y navegación hacia ajustes
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationAccessGranted" -> {
                    val granted = NavigationNotificationListenerService.isNotificationAccessGranted(this)
                    result.success(granted)
                }
                "isNotificationListenerConnected" -> {
                    result.success(NavigationNotificationListenerService.isListenerConnected)
                }
                "setSelectedSourcePackage" -> {
                    val pkg = call.argument<String>("packageName")
                    NavigationNotificationListenerService.selectedSourcePackage = pkg
                    NavigationNotificationListenerService.clearCache()
                    NavigationNotificationListenerService.syncActiveNotificationsForCurrentSelection()
                    result.success(true)
                }
                "syncActiveNotifications" -> {
                    NavigationNotificationListenerService.syncActiveNotificationsForCurrentSelection()
                    result.success(true)
                }
                "getSelectedSourcePackage" -> {
                    result.success(NavigationNotificationListenerService.selectedSourcePackage)
                }
                "openNotificationAccessSettings" -> {
                    try {
                        val intent = NavigationNotificationListenerService.createSettingsIntent(this)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_ERROR", e.localizedMessage, null)
                    }
                }
                "clearCache" -> {
                    NavigationNotificationListenerService.clearCache()
                    result.success(true)
                }
                "launchUrl" -> {
                    val urlString = call.argument<String>("url")
                    if (urlString != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(urlString)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ACTIVITY_NOT_FOUND", e.localizedMessage, null)
                        }
                    } else {
                        result.error("INVALID_URL", "URL requerida", null)
                    }
                }
                "startTripperGattServer" -> {
                    val res = TripperGattServerManager.startGattServer(this)
                    result.success(res)
                }
                "stopTripperGattServer" -> {
                    TripperGattServerManager.stopGattServer()
                    result.success(true)
                }
                "isTripperGattServerRunning" -> {
                    result.success(TripperGattServerManager.isServerRunning())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Canal de eventos reactivo para la transmisión de notificaciones en tiempo real
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NavigationNotificationListenerService.notificationListener = { payload ->
                        runOnUiThread {
                            events?.success(payload)
                        }
                    }
                    NavigationNotificationListenerService.syncActiveNotificationsForCurrentSelection()
                }

                override fun onCancel(arguments: Any?) {
                    NavigationNotificationListenerService.notificationListener = null
                }
            }
        )

        // Canal de eventos para el servidor GATT local del Tripper Pod
        val GATT_SERVER_EVENT_CHANNEL = "es.estela/tripper_gatt_server_events"
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, GATT_SERVER_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    TripperGattServerManager.onDataReceivedListener = { hex, address ->
                        runOnUiThread {
                            events?.success(mapOf("type" to "data", "hex" to hex, "address" to address))
                        }
                    }
                    TripperGattServerManager.onConnectionStateListener = { state, address ->
                        runOnUiThread {
                            events?.success(mapOf("type" to "connection", "state" to state, "address" to address))
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    TripperGattServerManager.onDataReceivedListener = null
                    TripperGattServerManager.onConnectionStateListener = null
                }
            }
        )
    }
}
