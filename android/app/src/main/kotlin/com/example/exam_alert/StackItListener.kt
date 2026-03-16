package com.example.exam_alert

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.content.Context
import android.util.Log

class StackItListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d("StackIt", "LISTENER CONNECTED: Monitoring stream active.")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val prefs = getSharedPreferences("StackItPrefs", Context.MODE_PRIVATE)
        
        // 1. Time Check (Signal Gating)
        val calendar = java.util.Calendar.getInstance()
        val nowMins = (calendar.get(java.util.Calendar.HOUR_OF_DAY) * 60) + calendar.get(java.util.Calendar.MINUTE)
        
        // Use exact keys defined in MainActivity
        val startMins = prefs.getInt("start_time_mins", 0)
        val endMins = prefs.getInt("end_time_mins", 1439)

        if (nowMins in startMins..endMins) {
            val blockedApps = prefs.getStringSet("blocked_apps", emptySet())
            val packageName = sbn.packageName

            if (blockedApps?.contains(packageName) == true) {
                // 2. Keyword Check (Emergency Bypass)
                val extras = sbn.notification.extras
                val title = extras.getString("android.title")?.lowercase() ?: "No Title"
                val text = extras.getCharSequence("android.text")?.toString()?.lowercase() ?: "No Content"
                val fullContent = "$title $text"

                val emergencyKeywords = prefs.getStringSet("emergency_keywords", setOf("emergency", "urgent", "exam"))
                
                val isEmergency = emergencyKeywords?.any { fullContent.contains(it.lowercase()) } ?: false

                if (isEmergency) {
                    Log.d("StackIt", "Emergency Keyword Detected in $packageName. Bypassing Silo.")
                    return // Let the notification through
                }

                // 3. Silo Action
                cancelNotification(sbn.key)
                Log.d("StackIt", "SILENCED: $packageName during focus window.")
            }
        }
    }
}