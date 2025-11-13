package com.example.demo_ai_even.bluetooth

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

object BlePermissionUtil {
    private const val TAG = "BlePermissionUtil"

    /**
     *  Bluetooth scan and connect permission
     */
    private val BLUETOOTH_PERMISSIONS = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.ACCESS_FINE_LOCATION,
        )
    } else {
        arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION
        )
    }

    /**
     *  If permission not granted will call system permission dialog
     */
    fun checkBluetoothPermission(context: Activity): Boolean {
        val missingPermissions = BLUETOOTH_PERMISSIONS.filter { permission ->
            ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED
        }
        if (missingPermissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(context, missingPermissions.toTypedArray(), 1)
            return false
        }
        return true
    }

    /**
     *  Check and request microphone permission for speech recognition
     */
    fun checkMicrophonePermission(context: Activity): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) 
            != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(context, arrayOf(Manifest.permission.RECORD_AUDIO), 2)
            return false
        }
        return true
    }

    /**
     * Check and request notification permission for Android 13+ (API 33+)
     * Required to show foreground service notifications
     */
    fun checkNotificationPermission(context: Activity): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) 
                != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    context, 
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS), 
                    3
                )
                return false
            }
        }
        return true
    }

    /**
     * Check and request phone state permission
     * Required for call state detection
     */
    fun checkPhoneStatePermission(context: Activity): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE) 
            != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                context, 
                arrayOf(Manifest.permission.READ_PHONE_STATE), 
                4
            )
            return false
        }
        return true
    }

    /**
     * Check and request call log permission (optional)
     * Used for caller information lookup
     */
    fun checkCallLogPermission(context: Activity): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ requires READ_CALL_LOG permission
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG) 
                != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    context, 
                    arrayOf(Manifest.permission.READ_CALL_LOG), 
                    5
                )
                return false
            }
        }
        return true
    }

    /**
     * Check and request contacts permission (optional)
     * Used for caller name lookup
     */
    fun checkContactsPermission(context: Activity): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) 
            != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                context, 
                arrayOf(Manifest.permission.READ_CONTACTS), 
                6
            )
            return false
        }
        return true
    }

}