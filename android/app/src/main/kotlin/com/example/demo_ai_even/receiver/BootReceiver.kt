package com.example.demo_ai_even.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import com.example.demo_ai_even.notification.NotificationForwardingService

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "even_ai_service_state"
        private const val KEY_SERVICE_RUNNING = "service_running"
        private const val KEY_LEFT_DEVICE_NAME = "left_device_name"
        private const val KEY_RIGHT_DEVICE_NAME = "right_device_name"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i(TAG, "Device boot completed, checking if service should be restarted")
            
            // Check if there was a previous connection
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val wasRunning = prefs.getBoolean(KEY_SERVICE_RUNNING, false)
            val leftDevice = prefs.getString(KEY_LEFT_DEVICE_NAME, null)
            val rightDevice = prefs.getString(KEY_RIGHT_DEVICE_NAME, null)
            
            if (wasRunning && leftDevice != null && rightDevice != null) {
                Log.i(TAG, "Previous connection found, restarting service")
                // Restart the service
                NotificationForwardingService.startService(context)
            } else {
                Log.d(TAG, "No previous connection found, not starting service")
            }
        }
    }
}

