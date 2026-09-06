package com.visuallstar.doom

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
import android.media.AudioManager
import android.provider.AlarmClock

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.doom/accessibility"
    private val EVENT_CHANNEL = "com.doom/accessibility_events"
    private var eventSink: EventChannel.EventSink? = null
    private var overlayView: View? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Torch and system control channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.doom/torch").setMethodCallHandler { call, result ->
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.doom/sms").setMethodCallHandler { call, result ->
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

        // Device actions channel for direct native control
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.doom/device_actions").setMethodCallHandler { call, result ->
            when (call.method) {
                "shareImage" -> {
                    val path = call.argument<String>("path") ?: ""
                    val packageName = call.argument<String>("package") ?: ""
                    try {
                        val file = java.io.File(path)
                        val uri = androidx.core.content.FileProvider.getUriForFile(
                            this, "${this.packageName}.fileprovider", file)
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "image/*"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            if (packageName.isNotEmpty()) setPackage(packageName)
                        }
                        startActivity(Intent.createChooser(intent, "Share via").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success("Sharing image")
                    } catch (e: Exception) {
                        result.error("SHARE_ERROR", "Share error: ${e.message}", null)
                    }
                }
                "makeDirectCall" -> {
                    val number = call.argument<String>("number") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number"))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success("Calling $number")
                    } catch (e: Exception) {
                        result.error("CALL_ERROR", "Call error: ${e.message}", null)
                    }
                }
                "openWhatsApp" -> {
                    val number = call.argument<String>("number") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    try {
                        val url = if (number.isNotEmpty()) {
                            "https://api.whatsapp.com/send?phone=$number&text=${Uri.encode(message)}"
                        } else {
                            "https://api.whatsapp.com/send?text=${Uri.encode(message)}"
                        }
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        intent.setPackage("com.whatsapp")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success("Opening WhatsApp")
                    } catch (e: Exception) {
                        result.error("WA_ERROR", "WhatsApp error: ${e.message}", null)
                    }
                }
                "openInstagram" -> {
                    val username = call.argument<String>("username") ?: ""
                    try {
                        val uri = if (username.isNotEmpty()) "https://www.instagram.com/$username/" else "https://www.instagram.com/"
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                        intent.setPackage("com.instagram.android")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success("Opening Instagram")
                    } catch (e: Exception) {
                        val fallback = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.instagram.com/$username/"))
                        fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(fallback)
                        result.success("Opening Instagram in browser")
                    }
                }
                "openSnapchat" -> {
                    val username = call.argument<String>("username") ?: ""
                    try {
                        val intent = if (username.isNotEmpty()) {
                            Intent(Intent.ACTION_VIEW, Uri.parse("https://www.snapchat.com/add/$username"))
                        } else {
                            packageManager.getLaunchIntentForPackage("com.snapchat.android")
                                ?: Intent(Intent.ACTION_VIEW, Uri.parse("https://www.snapchat.com/"))
                        }
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success("Opening Snapchat")
                    } catch (e: Exception) {
                        result.error("SNAP_ERROR", "Snapchat error: ${e.message}", null)
                    }
                }
                "mediaControl" -> {
                    val action = call.argument<String>("action") ?: "play_pause"
                    try {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val keyCode = when (action) {
                            "play", "pause", "play_pause" -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                            "next" -> android.view.KeyEvent.KEYCODE_MEDIA_NEXT
                            "previous" -> android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS
                            "stop" -> android.view.KeyEvent.KEYCODE_MEDIA_STOP
                            else -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                        }
                        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, keyCode))
                        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, keyCode))
                        result.success("Media $action executed")
                    } catch (e: Exception) {
                        result.error("MEDIA_ERROR", "Media control error: ${e.message}", null)
                    }
                }
                "setAlarmDirect" -> {
                    val hour = call.argument<Int>("hour") ?: 0
                    val minute = call.argument<Int>("minute") ?: 0
                    val label = call.argument<String>("label") ?: ""
                    try {
                        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                            putExtra(AlarmClock.EXTRA_HOUR, hour)
                            putExtra(AlarmClock.EXTRA_MINUTES, minute)
                            if (label.isNotEmpty()) putExtra(AlarmClock.EXTRA_MESSAGE, label)
                            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success("Alarm set for ${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}")
                    } catch (e: Exception) {
                        result.error("ALARM_ERROR", "Alarm error: ${e.message}", null)
                    }
                }
                "setTimerDirect" -> {
                    val seconds = call.argument<Int>("seconds") ?: 60
                    val label = call.argument<String>("label") ?: ""
                    try {
                        val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                            putExtra(AlarmClock.EXTRA_LENGTH, seconds)
                            if (label.isNotEmpty()) putExtra(AlarmClock.EXTRA_MESSAGE, label)
                            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success("Timer set for ${seconds / 60}m ${seconds % 60}s")
                    } catch (e: Exception) {
                        result.error("TIMER_ERROR", "Timer error: ${e.message}", null)
                    }
                }
                "setBrightnessNative" -> {
                    val value = call.argument<Int>("value") ?: 128
                    try {
                        if (Settings.System.canWrite(this)) {
                            Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, value.coerceIn(0, 255))
                            result.success("Brightness set to ${value * 100 / 255}%")
                        } else {
                            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                            intent.data = Uri.parse("package:$packageName")
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.error("PERMISSION_NEEDED", "Please allow write settings permission", null)
                        }
                    } catch (e: Exception) {
                        result.error("BRIGHTNESS_ERROR", "Brightness error: ${e.message}", null)
                    }
                }
                "setVolumeNative" -> {
                    val level = call.argument<Int>("level") ?: 50
                    try {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val vol = (level * maxVol / 100).coerceIn(0, maxVol)
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, vol, AudioManager.FLAG_SHOW_UI)
                        result.success("Volume set to $level%")
                    } catch (e: Exception) {
                        result.error("VOLUME_ERROR", "Volume error: ${e.message}", null)
                    }
                }
                "youtubeSearch" -> {
                    val query = call.argument<String>("query") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/results?search_query=" + Uri.encode(query)))
                        intent.setPackage("com.google.android.youtube")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success("Searching YouTube for $query")
                    } catch (e: Exception) {
                        val fallback = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/results?search_query=" + Uri.encode(query)))
                        fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(fallback)
                        result.success("Searching YouTube for $query (browser)")
                    }
                }
                else -> result.notImplemented()
            }
        }

        registerAccessibilityChannel(flutterEngine, this)
    }

    companion object {
        fun registerAccessibilityChannel(flutterEngine: FlutterEngine, context: android.content.Context) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.doom/accessibility")
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

                        "takeScreenshot" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.success("Accessibility service is not running.")
                            } else {
                                try {
                                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                        service.takeScreenshot(
                                            android.view.Display.DEFAULT_DISPLAY,
                                            context.mainExecutor,
                                            object : android.accessibilityservice.AccessibilityService.TakeScreenshotCallback {
                                                override fun onSuccess(screenshot: android.accessibilityservice.AccessibilityService.ScreenshotResult) {
                                                    result.success("Screenshot captured successfully.")
                                                }
                                                override fun onFailure(errorCode: Int) {
                                                    result.success("Screenshot failed with error code: $errorCode")
                                                }
                                            }
                                        )
                                    } else {
                                        // Fallback for older Android versions - perform global action
                                        service.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_TAKE_SCREENSHOT)
                                        result.success("Screenshot triggered.")
                                    }
                                } catch (e: Exception) {
                                    result.success("Error taking screenshot: ${e.message}")
                                }
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
