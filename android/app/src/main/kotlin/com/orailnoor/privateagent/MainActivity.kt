package com.orailnoor.privateagent

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.graphics.PixelFormat
import android.graphics.Color
import android.view.Gravity
import android.view.WindowManager
import android.view.View
import android.widget.Button
import android.net.Uri
import android.hardware.camera2.CameraManager
import android.content.Context

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.privateagent/accessibility"
    private val EVENT_CHANNEL = "com.privateagent/accessibility_events"
    private var eventSink: EventChannel.EventSink? = null
    private var overlayView: View? = null

    private val GALLERY_PICK_REQ = 1001
    private val GALLERY_PICK_APP_REQ = 1002
    private var pendingShareAppName: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Torch and system control channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.privateagent/torch").setMethodCallHandler { call, result ->
            when (call.method) {
                "toggleTorch" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    try {
                        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                        val cameraId = cameraManager.cameraIdList[0]
                        cameraManager.setTorchMode(cameraId, enabled)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getScreenTime" -> {
                    try {
                        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
                        val cal = java.util.Calendar.getInstance()
                        cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
                        cal.set(java.util.Calendar.MINUTE, 0)
                        cal.set(java.util.Calendar.SECOND, 0)
                        val startTime = cal.timeInMillis
                        val endTime = System.currentTimeMillis()
                        val stats = usageStatsManager.queryUsageStats(
                            android.app.usage.UsageStatsManager.INTERVAL_DAILY,
                            startTime, endTime
                        )
                        if (stats.isNullOrEmpty()) {
                            result.success("No usage data available. Please grant Usage Access permission in Settings > Apps > Special access > Usage data access.")
                        } else {
                            val sb = StringBuilder("Today's Screen Time:\n")
                            var totalMs = 0L
                            val sorted = stats
                                .filter { it.totalTimeInForeground > 60000 } // > 1 min
                                .sortedByDescending { it.totalTimeInForeground }
                                .take(10)
                            for (stat in sorted) {
                                val mins = stat.totalTimeInForeground / 60000
                                val hrs = mins / 60
                                val remMins = mins % 60
                                val appName = try {
                                    packageManager.getApplicationLabel(
                                        packageManager.getApplicationInfo(stat.packageName, 0)
                                    ).toString()
                                } catch (_: Exception) { stat.packageName.substringAfterLast('.') }
                                totalMs += stat.totalTimeInForeground
                                if (hrs > 0) {
                                    sb.appendLine("  $appName: ${hrs}h ${remMins}m")
                                } else {
                                    sb.appendLine("  $appName: ${remMins}m")
                                }
                            }
                            val totalMins = totalMs / 60000
                            val totalHrs = totalMins / 60
                            val totalRemMins = totalMins % 60
                            sb.appendLine("\nTotal: ${totalHrs}h ${totalRemMins}m")
                            result.success(sb.toString().trim())
                        }
                    } catch (e: Exception) {
                        result.success("Could not get screen time: ${e.message}")
                    }
                }
                "setScreenTimeout" -> {
                    val seconds = call.argument<Int>("seconds") ?: 30
                    try {
                        val timeoutMs = seconds * 1000
                        if (android.provider.Settings.System.canWrite(this)) {
                            android.provider.Settings.System.putInt(
                                contentResolver,
                                android.provider.Settings.System.SCREEN_OFF_TIMEOUT,
                                timeoutMs
                            )
                            result.success(true)
                        } else {
                            // Request WRITE_SETTINGS permission
                            val intent = android.content.Intent(android.provider.Settings.ACTION_MANAGE_WRITE_SETTINGS)
                            intent.data = android.net.Uri.parse("package:$packageName")
                            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    AgentAccessibilityService.eventListener = { eventMap ->
                        runOnUiThread {
                            eventSink?.success(eventMap)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    AgentAccessibilityService.eventListener = null
                }
            }
        )

        // SMS direct send channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.privateagent/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSms" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    if (phoneNumber.isEmpty() || message.isEmpty()) {
                        result.success(false)
                    } else {
                        try {
                            val smsManager = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                                getSystemService(android.telephony.SmsManager::class.java)
                            } else {
                                @Suppress("DEPRECATION")
                                android.telephony.SmsManager.getDefault()
                            }
                            // Handle long messages by splitting
                            val parts = smsManager.divideMessage(message)
                            if (parts.size == 1) {
                                smsManager.sendTextMessage(phoneNumber, null, message, null, null)
                            } else {
                                smsManager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("PrivateAgent", "SMS send error: ${e.message}")
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Gallery channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.privateagent/gallery").setMethodCallHandler { call, result ->
            when (call.method) {
                "shareImage" -> {
                    pendingResult = result
                    pendingShareAppName = null
                    val intent = Intent(Intent.ACTION_PICK, android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                    intent.type = "image/*"
                    startActivityForResult(intent, GALLERY_PICK_REQ)
                }
                "shareImageToApp" -> {
                    pendingResult = result
                    pendingShareAppName = call.argument<String>("appName")
                    val intent = Intent(Intent.ACTION_PICK, android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                    intent.type = "image/*"
                    startActivityForResult(intent, GALLERY_PICK_APP_REQ)
                }
                "openGallery" -> {
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.type = "image/*"
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    try {
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        registerAccessibilityChannel(flutterEngine, this)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if ((requestCode == GALLERY_PICK_REQ || requestCode == GALLERY_PICK_APP_REQ) && resultCode == android.app.Activity.RESULT_OK) {
            val uri = data?.data
            if (uri != null) {
                val shareIntent = Intent(Intent.ACTION_SEND)
                shareIntent.type = "image/*"
                shareIntent.putExtra(Intent.EXTRA_STREAM, uri)
                shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                
                if (requestCode == GALLERY_PICK_APP_REQ && pendingShareAppName != null) {
                    val packageName = getPackageNameForApp(pendingShareAppName!!)
                    if (packageName != null) {
                        shareIntent.setPackage(packageName)
                    }
                }
                
                try {
                    startActivity(Intent.createChooser(shareIntent, "Share Image"))
                    pendingResult?.success(true)
                } catch (e: Exception) {
                    pendingResult?.success(false)
                }
            } else {
                pendingResult?.success(false)
            }
            pendingResult = null
            pendingShareAppName = null
        }
    }
    
    private fun getPackageNameForApp(appName: String): String? {
        val lower = appName.toLowerCase()
        return when {
            lower.contains("whatsapp") -> "com.whatsapp"
            lower.contains("instagram") -> "com.instagram.android"
            lower.contains("twitter") || lower.contains("x") -> "com.twitter.android"
            lower.contains("facebook") -> "com.facebook.katana"
            lower.contains("telegram") -> "org.telegram.messenger"
            lower.contains("messenger") -> "com.facebook.orca"
            else -> null
        }
    }

    companion object {
        fun registerAccessibilityChannel(flutterEngine: FlutterEngine, context: android.content.Context) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.privateagent/accessibility")
                .setMethodCallHandler { call, result ->
                    android.util.Log.d("PrivateAgentKotlin", "Received method call: ${call.method}")
                    when (call.method) {
                        "ping" -> result.success(true)

                        "logToNative" -> {
                            val msg = call.argument<String>("message") ?: ""
                            android.util.Log.d("PrivateAgentDart", msg)
                            result.success(true)
                        }

                        "isServiceRunning" -> {
                            result.success(AgentAccessibilityService.isRunning())
                        }

                        "checkOverlayPermission" -> {
                            result.success(Settings.canDrawOverlays(context))
                        }

                        "requestOverlayPermission" -> {
                            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            result.success(true)
                        }

                        "showMacroOverlay" -> {
                            // Macro overlay requires an Activity context, so we just ignore or return error if called from background
                            result.error("NOT_SUPPORTED", "Macro overlay not supported from background", null)
                        }

                        "hideMacroOverlay" -> {
                            result.success(true)
                        }

                        "openAccessibilitySettings" -> {
                            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            result.success(true)
                        }

                        "dumpScreen" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                val nodes = service.dumpScreen()
                                result.success(nodes)
                            }
                        }

                        "takeScreenshot" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                    service.takeScreenshot { base64 ->
                                        if (base64 != null) {
                                            result.success(base64)
                                        } else {
                                            result.error("SCREENSHOT_FAILED", "Failed to capture screenshot", null)
                                        }
                                    }
                                } else {
                                    result.error("UNSUPPORTED_VERSION", "Screenshot requires Android 11 (API 30) or higher", null)
                                }
                            }
                        }

                        "clickByText" -> {
                            val text = call.argument<String>("text") ?: ""
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.clickByText(text))
                            }
                        }

                        "clickAt" -> {
                            val x = call.argument<Double>("x")?.toFloat() ?: 0f
                            val y = call.argument<Double>("y")?.toFloat() ?: 0f
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.clickAtCoordinates(x, y))
                            }
                        }

                        "typeText" -> {
                            val text = call.argument<String>("text") ?: ""
                            val hint = call.argument<String>("fieldHint")
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.typeText(text, hint))
                            }
                        }

                        "pressEnter" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.pressEnter())
                            }
                        }

                        "scroll" -> {
                            val direction = call.argument<String>("direction") ?: "down"
                            val target = call.argument<String>("target")
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.scroll(direction, target))
                            }
                        }

                        "showToast" -> {
                            val message = call.argument<String>("message") ?: ""
                            android.widget.Toast.makeText(context, message, android.widget.Toast.LENGTH_SHORT).show()
                            result.success(true)
                        }

                        "swipe" -> {
                            val startX = call.argument<Double>("startX")?.toFloat() ?: 0f
                            val startY = call.argument<Double>("startY")?.toFloat() ?: 0f
                            val endX = call.argument<Double>("endX")?.toFloat() ?: 0f
                            val endY = call.argument<Double>("endY")?.toFloat() ?: 0f
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.swipe(startX, startY, endX, endY))
                            }
                        }

                        "pressBack" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.pressBack())
                            }
                        }

                        "pressHome" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.pressHome())
                            }
                        }

                        "openNotifications" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.openNotifications())
                            }
                        }

                        "getCurrentPackage" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.getCurrentPackage())
                            }
                        }

                        "readNotifications" -> {
                            // Try NotificationListenerService first (modern, reliable)
                            val listenerResult = AgentNotificationListener.getFormattedNotifications()
                            if (listenerResult.isNotEmpty()) {
                                result.success(listenerResult)
                            } else {
                                // Fall back to accessibility service captured notifications
                                val sb = StringBuilder()
                                synchronized(AgentAccessibilityService.recentNotifications) {
                                    if (AgentAccessibilityService.recentNotifications.isEmpty()) {
                                        result.success("No notifications found. Please enable 'Notification Access' for PrivateAgent in Settings > Apps > Special access > Notification access.")
                                        return@setMethodCallHandler
                                    }
                                    for (entry in AgentAccessibilityService.recentNotifications) {
                                        val ago = (System.currentTimeMillis() - entry.timestamp) / 1000
                                        val timeStr = when {
                                            ago < 60 -> "${ago}s ago"
                                            ago < 3600 -> "${ago / 60}m ago"
                                            else -> "${ago / 3600}h ago"
                                        }
                                        sb.appendLine("[${entry.packageName.substringAfterLast('.')}] $timeStr: ${entry.text}")
                                    }
                                }
                                result.success(sb.toString().trim())
                            }
                        }

                        else -> result.notImplemented()
                    }
                }
        }
    }
}

class BackgroundEngineReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: android.content.Context, intent: android.content.Intent) {
        val engine = io.flutter.embedding.engine.FlutterEngineCache
            .getInstance()
            .get("myCachedEngine")
        if (engine == null) {
            android.util.Log.e("PrivateAgent", "Background engine myCachedEngine was not found")
            return
        }

        android.util.Log.d(
            "PrivateAgent",
            "Registering accessibility channel on myCachedEngine " +
                "(engine=${System.identityHashCode(engine)}, " +
                "dartExecuting=${engine.dartExecutor.isExecutingDart})"
        )
        MainActivity.registerAccessibilityChannel(engine, context.applicationContext)
    }
}
