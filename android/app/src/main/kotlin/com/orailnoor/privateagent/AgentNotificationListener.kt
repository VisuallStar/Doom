package com.orailnoor.privateagent

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class AgentNotificationListener : NotificationListenerService() {

    companion object {
        var instance: AgentNotificationListener? = null
            private set

        data class NotifEntry(
            val packageName: String,
            val title: String,
            val text: String,
            val timestamp: Long
        )

        val recentNotifications = mutableListOf<NotifEntry>()
        private const val MAX_NOTIFICATIONS = 30

        fun getFormattedNotifications(): String {
            synchronized(recentNotifications) {
                if (recentNotifications.isEmpty()) return ""
                val sb = StringBuilder()
                for (entry in recentNotifications) {
                    val ago = (System.currentTimeMillis() - entry.timestamp) / 1000
                    val timeStr = when {
                        ago < 60 -> "${ago}s ago"
                        ago < 3600 -> "${ago / 60}m ago"
                        else -> "${ago / 3600}h ago"
                    }
                    val appName = entry.packageName.substringAfterLast('.')
                    val titlePart = if (entry.title.isNotEmpty()) "${entry.title}: " else ""
                    sb.appendLine("[$appName] $timeStr: $titlePart${entry.text}")
                }
                return sb.toString().trim()
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        Log.d("PrivateAgent", "NotificationListener connected")

        // Capture currently active notifications
        try {
            val active = activeNotifications
            if (active != null) {
                synchronized(recentNotifications) {
                    for (sbn in active) {
                        addNotification(sbn)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("PrivateAgent", "Error reading active notifications", e)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        synchronized(recentNotifications) {
            addNotification(sbn)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Don't remove from our list — we want history
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        instance = null
        Log.d("PrivateAgent", "NotificationListener disconnected")
    }

    private fun addNotification(sbn: StatusBarNotification) {
        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString() ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val pkg = sbn.packageName ?: "unknown"

        // Skip empty notifications and our own
        if (text.isEmpty() && title.isEmpty()) return
        if (pkg == "com.orailnoor.privateagent") return

        val entry = NotifEntry(pkg, title, text, sbn.postTime)

        // Avoid duplicates (same title+text from same package)
        recentNotifications.removeAll { it.packageName == pkg && it.title == title && it.text == text }
        recentNotifications.add(0, entry)
        if (recentNotifications.size > MAX_NOTIFICATIONS) {
            recentNotifications.removeAt(recentNotifications.size - 1)
        }
    }
}
