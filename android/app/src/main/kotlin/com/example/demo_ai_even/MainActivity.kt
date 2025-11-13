package com.example.demo_ai_even

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import com.example.demo_ai_even.bluetooth.BleChannelHelper
import com.example.demo_ai_even.bluetooth.BleManager
import com.example.demo_ai_even.bluetooth.BlePermissionUtil
import com.example.demo_ai_even.call.CallStateListener
import com.example.demo_ai_even.cpp.Cpp
import com.example.demo_ai_even.speech.SpeechRecognitionManager
import com.example.demo_ai_even.speech.GoogleCloudSpeechService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Cpp.init()
        BleManager.instance.initBluetooth(this)
        
        // Initialize speech recognition (includes Google Cloud Speech if credentials available)
        // Google Cloud credentials are loaded from assets/google-cloud-credentials.json if present
        // See GOOGLE_CLOUD_SPEECH_SETUP.md for setup instructions
        SpeechRecognitionManager.instance.initialize(this)
        
        // Request Bluetooth permissions on app startup
        requestBluetoothPermissions()
        
        // Request battery optimization exception (to prevent Android from killing the service)
        requestBatteryOptimizationException()
        
        // Initialize and start call state listener
        initializeCallListener()
    }
    
    private fun requestBluetoothPermissions() {
        BlePermissionUtil.checkBluetoothPermission(this)
        BlePermissionUtil.checkMicrophonePermission(this)
        BlePermissionUtil.checkNotificationPermission(this)
        // Request phone permissions for call detection
        BlePermissionUtil.checkPhoneStatePermission(this)
        BlePermissionUtil.checkCallLogPermission(this)
        BlePermissionUtil.checkContactsPermission(this)
    }
    
    private fun initializeCallListener() {
        try {
            val callListener = CallStateListener.getInstance(this)
            callListener.startListening()
            Log.d(this::class.simpleName, "Call state listener initialized")
        } catch (e: Exception) {
            Log.e(this::class.simpleName, "Error initializing call listener: ${e.message}", e)
        }
    }
    
    /**
     * Check if battery optimization is disabled
     */
    fun isBatteryOptimizationDisabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                powerManager.isIgnoringBatteryOptimizations(packageName)
            } catch (e: Exception) {
                Log.e(this::class.simpleName, "Error checking battery optimization: ${e.message}", e)
                false
            }
        } else {
            true // Pre-Marshmallow doesn't have battery optimization
        }
    }
    
    /**
     * Request to ignore battery optimizations to prevent Android from killing the service
     * This is critical for maintaining BLE connection in background
     */
    private fun requestBatteryOptimizationException() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                val packageName = packageName
                
                if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                    Log.d(this::class.simpleName, "Battery optimization not ignored, requesting exception")
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    Toast.makeText(
                        this,
                        "Please allow battery optimization exception to maintain connection",
                        Toast.LENGTH_LONG
                    ).show()
                } else {
                    Log.d(this::class.simpleName, "Battery optimization already ignored")
                }
            } catch (e: Exception) {
                Log.e(this::class.simpleName, "Error requesting battery optimization exception: ${e.message}", e)
            }
        }
    }
    
    /**
     * Public method to request battery optimization exception (can be called from other places)
     */
    fun requestBatteryOptimization() {
        requestBatteryOptimizationException()
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == 1) { // Matching the request code in BlePermissionUtil
            val allGranted = grantResults.all { it == android.content.pm.PackageManager.PERMISSION_GRANTED }
            if (allGranted) {
                Log.d(this::class.simpleName, "Bluetooth permissions granted")
                Toast.makeText(this, "Bluetooth permissions granted", Toast.LENGTH_SHORT).show()
            } else {
                Log.w(this::class.simpleName, "Bluetooth permissions denied")
                Toast.makeText(
                    this, 
                    "Bluetooth permissions are required to connect to glasses", 
                    Toast.LENGTH_LONG
                ).show()
            }
        } else if (requestCode == 2) { // Microphone permission
            val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (granted) {
                Log.d(this::class.simpleName, "Microphone permission granted")
                Toast.makeText(this, "Microphone permission granted", Toast.LENGTH_SHORT).show()
            } else {
                Log.w(this::class.simpleName, "Microphone permission denied")
                Toast.makeText(
                    this, 
                    "Microphone permission is required for speech recognition", 
                    Toast.LENGTH_LONG
                ).show()
            }
        } else if (requestCode == 3) { // Notification permission
            val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (granted) {
                Log.d(this::class.simpleName, "Notification permission granted")
                Toast.makeText(this, "Notification permission granted", Toast.LENGTH_SHORT).show()
            } else {
                Log.w(this::class.simpleName, "Notification permission denied")
                Toast.makeText(
                    this, 
                    "Notification permission is required to maintain connection in background", 
                    Toast.LENGTH_LONG
                ).show()
            }
        } else if (requestCode == 4) { // Phone state permission
            val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (granted) {
                Log.d(this::class.simpleName, "Phone state permission granted")
                Toast.makeText(this, "Phone state permission granted", Toast.LENGTH_SHORT).show()
                // Restart call listener with new permission
                initializeCallListener()
            } else {
                Log.w(this::class.simpleName, "Phone state permission denied")
                Toast.makeText(
                    this, 
                    "Phone state permission is required to show incoming calls on glasses", 
                    Toast.LENGTH_LONG
                ).show()
            }
        } else if (requestCode == 5) { // Call log permission
            val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (granted) {
                Log.d(this::class.simpleName, "Call log permission granted")
            } else {
                Log.w(this::class.simpleName, "Call log permission denied (caller name may not be available)")
            }
        } else if (requestCode == 6) { // Contacts permission
            val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (granted) {
                Log.d(this::class.simpleName, "Contacts permission granted")
            } else {
                Log.w(this::class.simpleName, "Contacts permission denied (caller name may not be available)")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BleChannelHelper.initChannel(this, flutterEngine)
    }
    
    override fun onPause() {
        super.onPause()
        Log.d(this::class.simpleName, "MainActivity onPause - app going to background")
        // Service will continue running in background
    }
    
    override fun onStop() {
        super.onStop()
        Log.d(this::class.simpleName, "MainActivity onStop - app backgrounded")
        // Service will continue running in background
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(this::class.simpleName, "MainActivity onDestroy")
        // Note: Service will continue running even if activity is destroyed
        // Call listener will continue running as it uses application context
    }

}
