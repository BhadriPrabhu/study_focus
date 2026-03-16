package com.example.exam_alert

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.stackit/blocklist"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateBlockList" -> {
                    val apps = call.argument<List<String>>("apps")
                    val keywords = call.argument<List<String>>("keywords")
                    val startH = call.argument<Int>("startHour") ?: 0
                    val startM = call.argument<Int>("startMinute") ?: 0
                    val endH = call.argument<Int>("endHour") ?: 23
                    val endM = call.argument<Int>("endMinute") ?: 59

                    val prefs = getSharedPreferences("StackItPrefs", Context.MODE_PRIVATE)
                    
                    val success = prefs.edit()
                        .putStringSet("blocked_apps", apps?.toSet())
                        .putStringSet("emergency_keywords", keywords?.toSet())
                        .putInt("start_time_mins", (startH * 60) + startM)
                        .putInt("end_time_mins", (endH * 60) + endM)
                        .commit() // Immediate write
                    
                    result.success(success)
                }
                "openNotificationListenerSettings" -> {
                    val intent = android.content.Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                    intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}