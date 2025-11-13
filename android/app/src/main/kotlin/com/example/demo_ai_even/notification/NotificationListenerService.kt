package com.example.demo_ai_even.notification

import android.annotation.TargetApi
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.example.demo_ai_even.bluetooth.BleChannelHelper
import org.json.JSONObject

@TargetApi(Build.VERSION_CODES.JELLY_BEAN_MR2)
class AppNotificationListenerService : NotificationListenerService() {
    
    companion object {
        private const val TAG = "NotificationListener"
        var instance: AppNotificationListenerService? = null
    }
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "NotificationListenerService created")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        instance = null
        Log.d(TAG, "NotificationListenerService destroyed")
    }
    
    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "NotificationListenerService connected")
        // Notify Flutter that the service is ready
        BleChannelHelper.bleNotificationListenerStatus(true)
    }
    
    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "NotificationListenerService disconnected")
        BleChannelHelper.bleNotificationListenerStatus(false)
    }
    
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        
        if (sbn == null || !isNotificationForUser(sbn)) {
            return
        }
        
        try {
            val notification = sbn.notification
            val extras = notification.extras ?: android.os.Bundle()
            
            if (notification.extras == null) {
                Log.w(TAG, "Notification extras were null for package ${sbn.packageName} - creating empty bundle")
            }
            
            // Get notification details
            val packageName = sbn.packageName
            var title = extras.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString() ?: ""
            var text = extras.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString() ?: ""
            var subText = extras.getCharSequence(android.app.Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
            val timestamp = sbn.postTime / 1000 // Convert to seconds
            
            // Get notification category (important for detecting calls)
            val category = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                notification.category
            } else {
                null
            }
            
            // Get app name
            val appName = try {
                val pm = packageManager
                val appInfo = pm.getApplicationInfo(packageName, 0)
                pm.getApplicationLabel(appInfo).toString()
            } catch (e: Exception) {
                packageName
            }
            
            // Check if this is a call notification
            val isCallNotification = category == android.app.Notification.CATEGORY_CALL || 
                                   packageName.contains("phone", ignoreCase = true) ||
                                   packageName.contains("dialer", ignoreCase = true) ||
                                   packageName.contains("telecom", ignoreCase = true) ||
                                   packageName.contains("incallui", ignoreCase = true)
            
            // For call notifications, try to extract caller info from additional extras
            if (isCallNotification) {
                Log.d(TAG, "CALL NOTIFICATION DETECTED: package=$packageName, category=$category")
                Log.d(TAG, "Call notification extras: title='$title', text='$text', subText='$subText'")
                
                // Try to get caller info from big text (some dialers use this)
                val bigText = extras.getCharSequence(android.app.Notification.EXTRA_BIG_TEXT)?.toString()
                if (!bigText.isNullOrEmpty() && text.isEmpty()) {
                    text = bigText
                    Log.d(TAG, "Call notification: Using BIG_TEXT as message: '$text'")
                }
                
                // Try to get info from text lines (some dialers use this format)
                val textLines = extras.getCharSequenceArray(android.app.Notification.EXTRA_TEXT_LINES)
                if (textLines != null && textLines.isNotEmpty()) {
                    if (text.isEmpty() && textLines[0] != null) {
                        text = textLines[0].toString()
                        Log.d(TAG, "Call notification: Using TEXT_LINES[0] as message: '$text'")
                    }
                    if (subText.isEmpty() && textLines.size > 1 && textLines[1] != null) {
                        subText = textLines[1].toString()
                        Log.d(TAG, "Call notification: Using TEXT_LINES[1] as subtitle: '$subText'")
                    }
                }
                
                // Log all available extras for debugging (limit to avoid spam)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    val allKeys = extras.keySet()
                    Log.d(TAG, "Call notification available keys: ${allKeys.joinToString(", ")}")
                }
            }
            
            // Only send notifications with content
            // Exception: Allow call notifications even if title/text is empty (they might have caller info in other fields)
            if (!isCallNotification && title.isEmpty() && text.isEmpty() && subText.isEmpty()) {
                Log.d(TAG, "Skipping notification: no content - package=$packageName")
                return
            }
            
            // For call notifications, ensure we have at least some content
            if (isCallNotification && title.isEmpty() && text.isEmpty() && subText.isEmpty()) {
                // Fallback: use app name or package name
                if (title.isEmpty()) {
                    title = "Incoming Call"
                }
                Log.d(TAG, "Call notification: Using fallback title='$title'")
            }
            
            // Create notification JSON
            val notificationData = JSONObject().apply {
                put("msg_id", sbn.id and 0x7FFFFFFF) // Ensure positive ID
                put("app_identifier", packageName)
                put("title", title)
                put("subtitle", subText)
                put("message", text)
                put("time_s", timestamp.toInt())
                put("display_name", appName)
                if (category != null) {
                    put("category", category) // Add category for better call detection
                }
                if (isCallNotification && text.isEmpty() && subText.isEmpty()) {
                    // Some dialers hide caller info from notification extras; add a hint for Flutter side
                    put("call_notification", true)
                }
            }
            
            if (isCallNotification) {
                Log.d(TAG, "SENDING CALL NOTIFICATION: $packageName - title='$title', subtitle='$subText', message='$text', category=$category")
            } else {
                Log.d(TAG, "Notification received: $packageName - title='$title', message='$text', category=$category")
            }
            
            // Send to Flutter
            BleChannelHelper.bleNotificationReceived(notificationData.toString())
            
        } catch (e: Exception) {
            Log.e(TAG, "Error processing notification", e)
        }
    }
    
    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        // Optional: Handle notification removal if needed
    }
    
    private fun isNotificationForUser(sbn: StatusBarNotification): Boolean {
        // Only process notifications for the current user
        // UserHandle comparison should work directly
        return sbn.user == android.os.Process.myUserHandle()
    }
    
    /**
     * Check if notification access is enabled
     */
    fun isNotificationAccessEnabled(): Boolean {
        val componentName = ComponentName(this, AppNotificationListenerService::class.java)
        val componentNameFlat = componentName.flattenToString()
        
        // Check if service is in the list of enabled listeners
        val flat = android.provider.Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        )
        
        if (flat != null && !flat.isEmpty()) {
            val names = flat.split(":")
            return names.any { it.contains(componentNameFlat) }
        }
        
        // Fallback: try to access notifications (will throw SecurityException if not enabled)
        return try {
            getActiveNotifications() // This will work if service has access
            true
        } catch (e: SecurityException) {
            false
        }
    }
    
    /**
     * Open system settings to enable notification access
     */
    fun openNotificationAccessSettings() {
        val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }
}

