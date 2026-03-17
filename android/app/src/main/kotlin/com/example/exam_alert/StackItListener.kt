package com.example.exam_alert

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.content.Context
import android.util.Log
import android.os.Handler
import android.os.Looper
import android.app.Notification

class StackItListener : NotificationListenerService() {

    // Cache to prevent processing the same notification ID multiple times in quick succession
    private val processedKeys = HashSet<String>()
    private val handler = Handler(Looper.getMainLooper())

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // 1. Basic Safety Checks
        if (sbn.isOngoing) return // Ignore persistent notifications (Music, Downloads)
        
        val extras = sbn.notification.extras
        // Ignore "Summary" notifications (the grouping header created by Android)
        val isSummary = (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0
        if (isSummary) return

        val prefs = getSharedPreferences("StackItPrefs", Context.MODE_PRIVATE)
        
        // 2. Check Quick Release (Shake bypass)
        if (prefs.getBoolean("temp_release_active", false)) {
            Log.d("StackIt", "Bypassed: Shake Release is Active")
            return
        }

        // 3. Time Window Check
        val calendar = java.util.Calendar.getInstance()
        val nowMins = (calendar.get(java.util.Calendar.HOUR_OF_DAY) * 60) + calendar.get(java.util.Calendar.MINUTE)

        val startMins = prefs.getInt("start_time_mins", 0)
        val endMins = prefs.getInt("end_time_mins", 1439)

        val isInsideWindow = if (startMins <= endMins) {
            nowMins in startMins..endMins
        } else {
            nowMins >= startMins || nowMins <= endMins
        }

        if (isInsideWindow) {
            val blockedApps = prefs.getStringSet("blocked_apps", emptySet()) ?: emptySet()
            val packageName = sbn.packageName

            if (blockedApps.contains(packageName)) {
                
                // --- DUPLICATE PREVENTION ---
                if (processedKeys.contains(sbn.key)) {
                    Log.d("StackIt", "Duplicate ignored: ${sbn.key}")
                    return
                }

                // 4. Keyword Check (Emergency Bypass)
                val title = extras.getString("android.title")?.lowercase() ?: ""
                val text = extras.getCharSequence("android.text")?.toString()?.lowercase() ?: ""
                val fullContent = "$title $text"

                val emergencyKeywords = prefs.getStringSet("emergency_keywords", setOf("emergency", "urgent", "exam")) ?: emptySet()
                val isEmergency = emergencyKeywords.any { it.isNotEmpty() && fullContent.contains(it.lowercase()) }

                if (isEmergency) {
                    Log.d("StackIt", "Emergency Detected. Letting it through.")
                    return 
                }

                // 5. SILENCE, LOG & CACHE
                saveToVault(packageName, title, text)
                
                // Add to processed list and remove after 5 seconds
                processedKeys.add(sbn.key)
                handler.postDelayed({ processedKeys.remove(sbn.key) }, 5000)

                cancelNotification(sbn.key)
                Log.d("StackIt", "SUCCESSFULLY SILENCED: $packageName")
            }
        } else {
            Log.d("StackIt", "Outside focus window. Current: $nowMins, Window: $startMins-$endMins")
        }
    }

    private fun saveToVault(pkg: String, title: String, content: String) {
        var db: android.database.sqlite.SQLiteDatabase? = null
        try {
            val prefs = getSharedPreferences("StackItPrefs", Context.MODE_PRIVATE)
            val activeSubject = prefs.getString("active_subject_name", "General") ?: "General"

            db = openOrCreateDatabase("stackit_vault.db", Context.MODE_PRIVATE, null)
            
            // Ensure table and subject column exist
            db.execSQL("CREATE TABLE IF NOT EXISTS notifications (id INTEGER PRIMARY KEY AUTOINCREMENT, pkg TEXT, title TEXT, content TEXT, timestamp INTEGER, subject TEXT)")
            
            // Migration check for 'subject' column
            val cursor = db.rawQuery("PRAGMA table_info(notifications)", null)
            var hasSubject = false
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == "subject") {
                    hasSubject = true
                    break
                }
            }
            cursor.close()
            if (!hasSubject) {
                db.execSQL("ALTER TABLE notifications ADD COLUMN subject TEXT DEFAULT 'General'")
            }

            // Insert unique entry
            db.execSQL("INSERT INTO notifications (pkg, title, content, timestamp, subject) VALUES (?, ?, ?, ?, ?)", 
                arrayOf(pkg, title, content, System.currentTimeMillis(), activeSubject))
                
        } catch (e: Exception) { 
            Log.e("StackIt", "DB Error: ${e.message}") 
        } finally {
            db?.close()
        }
    }
}