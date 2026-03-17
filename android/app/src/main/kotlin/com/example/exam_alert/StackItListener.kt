package com.example.exam_alert

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.content.Context
import android.util.Log

class StackItListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val prefs = getSharedPreferences("StackItPrefs", Context.MODE_PRIVATE)
        
        // 1. Check Quick Release (Shake bypass)
        if (prefs.getBoolean("temp_release_active", false)) {
            Log.d("StackIt", "Bypassed: Shake Release is Active")
            return
        }

        // 2. Time Window Check
        val calendar = java.util.Calendar.getInstance()
        val nowMins = (calendar.get(java.util.Calendar.HOUR_OF_DAY) * 60) + calendar.get(java.util.Calendar.MINUTE)
        
        // Default to "Always Block" (0 to 1439) if keys are missing
        val startMins = prefs.getInt("start_time_mins", 0)
        val endMins = prefs.getInt("end_time_mins", 1439)

        Log.d("StackIt", "Current Mins: $nowMins, Window: $startMins to $endMins")

        if (nowMins in startMins..endMins) {
            val blockedApps = prefs.getStringSet("blocked_apps", emptySet()) ?: emptySet()
            val packageName = sbn.packageName

            if (blockedApps.contains(packageName)) {
                // 3. Keyword Check (Emergency Bypass)
                val extras = sbn.notification.extras
                val title = extras.getString("android.title")?.lowercase() ?: ""
                val text = extras.getCharSequence("android.text")?.toString()?.lowercase() ?: ""
                val fullContent = "$title $text"

                val emergencyKeywords = prefs.getStringSet("emergency_keywords", setOf("emergency", "urgent", "exam")) ?: emptySet()
                
                // Logic: If ANY keyword is found, LET IT THROUGH
                val isEmergency = emergencyKeywords.any { it.isNotEmpty() && fullContent.contains(it.lowercase()) }

                if (isEmergency) {
                    Log.d("StackIt", "Emergency Detected: $fullContent. Letting it through.")
                    return 
                }

                Log.d("StackIt", "Log.")
                // 4. LOG & CANCEL
                saveToVault(packageName, title, text)
                Log.d("StackIt", "Sent to Vault.")
                cancelNotification(sbn.key)
                Log.d("StackIt", "SUCCESSFULLY SILENCED: $packageName")
            }
        } else {
            Log.d("StackIt", "Outside focus window. Letting notification pass.")
        }
    }

    private fun saveToVault(pkg: String, title: String, content: String) {
        try {
            val db = openOrCreateDatabase("stackit_vault.db", Context.MODE_PRIVATE, null)
            db.execSQL("CREATE TABLE IF NOT EXISTS notifications (id INTEGER PRIMARY KEY AUTOINCREMENT, pkg TEXT, title TEXT, content TEXT, timestamp INTEGER)")
            db.execSQL("INSERT INTO notifications (pkg, title, content, timestamp) VALUES (?, ?, ?, ?)", 
                arrayOf(pkg, title, content, System.currentTimeMillis()))
            db.close()
        } catch (e: Exception) { Log.e("StackIt", "DB Error: ${e.message}") }
    }
}