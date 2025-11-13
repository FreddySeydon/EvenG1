package com.example.demo_ai_even.notification

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.demo_ai_even.MainActivity
import com.example.demo_ai_even.bluetooth.BleManager
import kotlinx.coroutines.*

class NotificationForwardingService : Service() {
    
    private var heartbeatJob: Job? = null
    private var connectionMonitorJob: Job? = null
    private var reconnectionJob: Job? = null
    private val heartbeatScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var wakeLock: PowerManager.WakeLock? = null
    
    // State persistence
    private lateinit var sharedPrefs: SharedPreferences
    private var isServiceRestarted = false
    
    // Connection state
    private var lastHeartbeatTime: Long = 0
    private var heartbeatSuccessCount = 0
    private var heartbeatFailureCount = 0
    private var connectionState: ConnectionState = ConnectionState.DISCONNECTED
    private var reconnectionAttempts = 0
    private val maxReconnectionAttempts = 5
    
    enum class ConnectionState {
        CONNECTED, RECONNECTING, DISCONNECTED
    }
    
    companion object {
        private const val TAG = "NotificationService"
        private const val NOTIFICATION_CHANNEL_ID = "notification_forwarding_channel"
        private const val NOTIFICATION_ID = 1
        private const val SERVICE_ID = 1234
        
        // SharedPreferences keys
        private const val PREFS_NAME = "even_ai_service_state"
        private const val KEY_LEFT_DEVICE_NAME = "left_device_name"
        private const val KEY_RIGHT_DEVICE_NAME = "right_device_name"
        private const val KEY_CHANNEL_NUMBER = "channel_number"
        private const val KEY_CONNECTION_TIMESTAMP = "connection_timestamp"
        private const val KEY_SERVICE_RUNNING = "service_running"
        
        // Action intents
        private const val ACTION_RECONNECT = "com.example.demo_ai_even.RECONNECT"
        private const val ACTION_STOP_SERVICE = "com.example.demo_ai_even.STOP_SERVICE"
        
        fun startService(context: Context) {
            val intent = Intent(context, NotificationForwardingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.d(TAG, "NotificationForwardingService start requested")
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, NotificationForwardingService::class.java)
            context.stopService(intent)
            Log.d(TAG, "NotificationForwardingService stop requested")
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "NotificationForwardingService onCreate")
        
        // Initialize SharedPreferences for state persistence
        sharedPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        // Check if service was restarted
        isServiceRestarted = sharedPrefs.getBoolean(KEY_SERVICE_RUNNING, false)
        
        // Create notification channel for Android O and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Even AI Connection",
                NotificationManager.IMPORTANCE_DEFAULT // Changed from LOW to DEFAULT
            ).apply {
                description = "Maintains connection to your glasses"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
        
        // Check battery optimization status
        checkBatteryOptimizationStatus()
        
        // Check if we should restore connection state
        if (isServiceRestarted) {
            Log.i(TAG, "[${System.currentTimeMillis()}] Service restarted - Attempting to restore connection")
            restoreConnectionState()
        }
        
        Log.i(TAG, "[${System.currentTimeMillis()}] Service created - Starting background operations")
        
        // Mark service as running
        saveServiceState(running = true)
        
        // Start native heartbeat
        startNativeHeartbeat()
        
        // Start connection monitoring
        startConnectionMonitoring()
    }
    
    /**
     * Check battery optimization status and log warning if enabled
     */
    private fun checkBatteryOptimizationStatus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                val isIgnored = powerManager.isIgnoringBatteryOptimizations(packageName)
                if (!isIgnored) {
                    Log.w(TAG, "Battery optimization is NOT disabled - service may be killed by system")
                } else {
                    Log.d(TAG, "Battery optimization is disabled - service should stay alive")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error checking battery optimization: ${e.message}", e)
            }
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val timestamp = System.currentTimeMillis()
        Log.i(TAG, "[$timestamp] NotificationForwardingService onStartCommand - Service ID: $startId, Flags: $flags")
        
        // Handle notification action intents
        when (intent?.action) {
            ACTION_RECONNECT -> {
                Log.i(TAG, "Reconnect action triggered from notification")
                startReconnection()
            }
            ACTION_STOP_SERVICE -> {
                Log.i(TAG, "Stop service action triggered from notification")
                clearConnectionState()
                stopSelf()
                return START_NOT_STICKY
            }
        }
        
        // Check if this is a restart (flags contain START_FLAG_REDELIVERY or START_FLAG_RETRY)
        val wasRestarted = (flags and START_FLAG_REDELIVERY != 0) || (flags and START_FLAG_RETRY != 0)
        if (wasRestarted && !isServiceRestarted) {
            Log.i(TAG, "Service was restarted by system - restoring state")
            isServiceRestarted = true
            restoreConnectionState()
        }
        
        // Update notification
        updateNotification()
        
        // Check notification permission before starting foreground service (Android 13+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val hasPermission = android.content.pm.PackageManager.PERMISSION_GRANTED == 
                checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
            if (!hasPermission) {
                Log.w(TAG, "Notification permission not granted - foreground service may not show notification")
                // Still try to start, but log warning
            }
        }
        
        // Start foreground service with proper type for Android 12+
        try {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Try to use setForegroundServiceBehavior on Android 14+ if available
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        startForeground(
                            NOTIFICATION_ID, 
                            notification, 
                            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                        )
                    } else {
                        startForeground(NOTIFICATION_ID, notification)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Could not set foreground service type, using fallback: ${e.message}")
                    startForeground(NOTIFICATION_ID, notification)
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                startForeground(NOTIFICATION_ID, notification)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "Foreground service started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service: ${e.message}", e)
            // If we can't start foreground service, the heartbeat will still work in background
            // but may be less reliable
        }
        
        return START_STICKY // Restart if killed by system
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null // Not a bound service
    }
    
    override fun onDestroy() {
        super.onDestroy()
        val timestamp = System.currentTimeMillis()
        Log.w(TAG, "[$timestamp] NotificationForwardingService onDestroy - Service is being destroyed!")
        
        // Stop all operations
        stopNativeHeartbeat()
        stopConnectionMonitoring()
        stopReconnection()
        heartbeatScope.cancel() // Cancel all coroutines
        releaseWakeLock()
        
        // Note: We don't clear service_running flag here because we want to restore on restart
        // Only clear if user explicitly stops the service
        Log.w(TAG, "[$timestamp] Service cleanup complete")
    }
    
    /**
     * Acquire wake lock - keep it continuously while service is running and connected
     * This ensures the device doesn't sleep between heartbeats
     */
    private fun acquireWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                return // Already held
            }
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "NotificationForwardingService::WakeLock"
            ).apply {
                // Acquire without timeout to keep device awake while service is running
                acquire()
                Log.i(TAG, "[${System.currentTimeMillis()}] Wake lock acquired - keeping device awake for service")
            }
        } catch (e: Exception) {
            Log.e(TAG, "[${System.currentTimeMillis()}] Error acquiring wake lock: ${e.message}", e)
        }
    }
    
    /**
     * Release wake lock
     */
    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.d(TAG, "[${System.currentTimeMillis()}] Wake lock released")
                }
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing wake lock", e)
        }
    }
    
    // State Persistence Methods
    
    /**
     * Save connection state to SharedPreferences
     */
    fun saveConnectionState(leftDeviceName: String, rightDeviceName: String, channelNumber: String) {
        sharedPrefs.edit().apply {
            putString(KEY_LEFT_DEVICE_NAME, leftDeviceName)
            putString(KEY_RIGHT_DEVICE_NAME, rightDeviceName)
            putString(KEY_CHANNEL_NUMBER, channelNumber)
            putLong(KEY_CONNECTION_TIMESTAMP, System.currentTimeMillis())
            apply()
        }
        Log.d(TAG, "Connection state saved: $leftDeviceName / $rightDeviceName")
    }
    
    /**
     * Save service running state
     */
    private fun saveServiceState(running: Boolean) {
        sharedPrefs.edit().putBoolean(KEY_SERVICE_RUNNING, running).apply()
    }
    
    /**
     * Clear connection state (called when user explicitly disconnects)
     */
    fun clearConnectionState() {
        sharedPrefs.edit().apply {
            remove(KEY_LEFT_DEVICE_NAME)
            remove(KEY_RIGHT_DEVICE_NAME)
            remove(KEY_CHANNEL_NUMBER)
            remove(KEY_CONNECTION_TIMESTAMP)
            putBoolean(KEY_SERVICE_RUNNING, false)
            apply()
        }
        Log.d(TAG, "Connection state cleared")
    }
    
    /**
     * Get saved connection state
     */
    private fun getSavedConnectionState(): Triple<String?, String?, String?> {
        val leftDevice = sharedPrefs.getString(KEY_LEFT_DEVICE_NAME, null)
        val rightDevice = sharedPrefs.getString(KEY_RIGHT_DEVICE_NAME, null)
        val channelNumber = sharedPrefs.getString(KEY_CHANNEL_NUMBER, null)
        return Triple(leftDevice, rightDevice, channelNumber)
    }
    
    /**
     * Restore connection state and attempt reconnection
     */
    private fun restoreConnectionState() {
        val (leftDevice, rightDevice, channelNumber) = getSavedConnectionState()
        if (leftDevice != null && rightDevice != null && channelNumber != null) {
            Log.i(TAG, "Restoring connection state: $leftDevice / $rightDevice (channel: $channelNumber)")
            // Check if already connected
            if (!BleManager.instance.isBleConnected()) {
                // Start reconnection process
                startReconnection()
            } else {
                Log.i(TAG, "BLE already connected, no need to restore")
                connectionState = ConnectionState.CONNECTED
                updateNotification()
            }
        } else {
            Log.d(TAG, "No saved connection state to restore")
        }
    }
    
    /**
     * Start native-side heartbeat that runs independently of Dart isolate
     * This ensures heartbeat continues even when app is in background
     * Uses selective wake lock (only during active operations)
     */
    private fun startNativeHeartbeat() {
        stopNativeHeartbeat() // Stop any existing heartbeat
        
        val timestamp = System.currentTimeMillis()
        Log.d(TAG, "[$timestamp] Starting native heartbeat - Service should keep connection alive")
        
        heartbeatJob = heartbeatScope.launch {
            var heartbeatSeq = 0
            var consecutiveFailures = 0
            var lastSuccessTime = System.currentTimeMillis()
            
            while (isActive) {
                try {
                    val currentTime = System.currentTimeMillis()
                    val timeSinceLastSuccess = currentTime - lastSuccessTime
                    
                    // Log periodic status every 5 heartbeats (~2.5 minutes)
                    if (heartbeatSeq % 5 == 0) {
                        Log.i(TAG, "[$currentTime] Heartbeat Status - Seq: $heartbeatSeq, Failures: $consecutiveFailures, Time since last success: ${timeSinceLastSuccess/1000}s, Success rate: ${calculateSuccessRate()}%")
                    }
                    
                    // Check if BLE is connected before sending heartbeat
                    val isConnected = BleManager.instance.isBleConnected()
                    
                    // Ensure wake lock is held while connected
                    if (isConnected && (wakeLock == null || !wakeLock!!.isHeld)) {
                        acquireWakeLock()
                    }
                    
                    if (isConnected) {
                        // Send heartbeat packet: [0x25, length_low, length_high, seq, 0x04, seq]
                        val length = 6
                        val data = byteArrayOf(
                            0x25.toByte(),
                            (length and 0xff).toByte(),
                            ((length shr 8) and 0xff).toByte(),
                            (heartbeatSeq % 0xff).toByte(),
                            0x04.toByte(),
                            (heartbeatSeq % 0xff).toByte()
                        )
                        heartbeatSeq++
                        
                        // Send to both left and right devices
                        val sendStartTime = System.currentTimeMillis()
                        val success = BleManager.instance.sendHeartbeatData(data)
                        val sendDuration = System.currentTimeMillis() - sendStartTime
                        
                        if (success) {
                            consecutiveFailures = 0
                            lastSuccessTime = System.currentTimeMillis()
                            lastHeartbeatTime = lastSuccessTime
                            heartbeatSuccessCount++
                            // Only update notification if state changed from disconnected/reconnecting to connected
                            val previousState = connectionState
                            connectionState = ConnectionState.CONNECTED
                            if (previousState != ConnectionState.CONNECTED) {
                                updateNotification()
                            }
                            Log.d(TAG, "[$currentTime] ✓ Heartbeat sent successfully - Seq: $heartbeatSeq, Duration: ${sendDuration}ms")
                        } else {
                            consecutiveFailures++
                            heartbeatFailureCount++
                            Log.w(TAG, "[$currentTime] ✗ Heartbeat send failed - Seq: $heartbeatSeq, Failures: $consecutiveFailures, Duration: ${sendDuration}ms")
                            
                            // If send fails, it might indicate connection issue
                            // Check connection status
                            val stillConnected = BleManager.instance.isBleConnected()
                            val previousState = connectionState
                            if (!stillConnected) {
                                Log.w(TAG, "[$currentTime] BLE connection lost during heartbeat, will trigger reconnection")
                                connectionState = ConnectionState.DISCONNECTED
                                // Only update notification if state changed
                                if (previousState != ConnectionState.DISCONNECTED) {
                                    updateNotification()
                                }
                                // Trigger reconnection but don't break - keep heartbeat loop running
                                if (reconnectionJob == null || !reconnectionJob!!.isActive) {
                                    startReconnection()
                                }
                            } else {
                                Log.w(TAG, "[$currentTime] BLE still connected but heartbeat failed - may be temporary issue")
                            }
                            
                            // If we've had too many failures, trigger reconnection (but keep loop running)
                            if (consecutiveFailures >= 5) {
                                Log.e(TAG, "[$currentTime] WARNING: $consecutiveFailures consecutive heartbeat failures! Triggering reconnection")
                                val prevState = connectionState
                                connectionState = ConnectionState.RECONNECTING
                                // Only update notification if state changed
                                if (prevState != ConnectionState.RECONNECTING) {
                                    updateNotification()
                                }
                                if (reconnectionJob == null || !reconnectionJob!!.isActive) {
                                    startReconnection()
                                }
                            }
                            
                            // Check for stale connection (no success for > 90 seconds) - more lenient
                            if (timeSinceLastSuccess > 90000) {
                                Log.w(TAG, "[$currentTime] Stale connection detected (no success for ${timeSinceLastSuccess/1000}s), triggering reconnection")
                                val prevState = connectionState
                                connectionState = ConnectionState.RECONNECTING
                                // Only update notification if state changed
                                if (prevState != ConnectionState.RECONNECTING) {
                                    updateNotification()
                                }
                                if (reconnectionJob == null || !reconnectionJob!!.isActive) {
                                    startReconnection()
                                }
                            }
                        }
                    } else {
                            Log.w(TAG, "[$currentTime] Heartbeat skipped: BLE not connected (seq would be: $heartbeatSeq)")
                            consecutiveFailures++
                            val previousState = connectionState
                            connectionState = ConnectionState.DISCONNECTED
                            // Only update notification if state changed
                            if (previousState != ConnectionState.DISCONNECTED) {
                                updateNotification()
                            }
                            
                            // Release wake lock when disconnected to save battery
                            if (wakeLock?.isHeld == true) {
                                // Don't release completely, just note that we're disconnected
                                // Keep it in case reconnection happens quickly
                            }
                            
                            // If not connected, start reconnection (but keep heartbeat loop running)
                            if (consecutiveFailures >= 3 && (reconnectionJob == null || !reconnectionJob!!.isActive)) {
                                Log.w(TAG, "[$currentTime] BLE not connected, starting reconnection")
                                startReconnection()
                            }
                        }
                } catch (e: Exception) {
                    consecutiveFailures++
                    heartbeatFailureCount++
                    // Don't release wake lock on exception - keep it for retry
                    Log.e(TAG, "[${System.currentTimeMillis()}] Exception sending native heartbeat: ${e.message}", e)
                }
                
                // Wait 25 seconds before next heartbeat (reduced from 29s to keep connection more active and prevent 30-minute disconnects)
                delay(25000) // 25 seconds - more frequent to prevent disconnection
            }
            
            Log.w(TAG, "[${System.currentTimeMillis()}] Native heartbeat loop exited - isActive: ${isActive}")
            
            // If loop exited but service is still active, restart it after a delay
            if (isActive) {
                Log.i(TAG, "Heartbeat loop exited but service is still active, restarting in 5 seconds...")
                delay(5000)
                if (isActive) {
                    startNativeHeartbeat()
                }
            }
        }
    }
    
    /**
     * Calculate heartbeat success rate
     */
    private fun calculateSuccessRate(): Int {
        val total = heartbeatSuccessCount + heartbeatFailureCount
        return if (total > 0) {
            (heartbeatSuccessCount * 100 / total)
        } else {
            100
        }
    }
    
    /**
     * Stop native heartbeat
     */
    private fun stopNativeHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = null
        Log.d(TAG, "Native heartbeat stopped")
    }
    
    /**
     * Monitor connection status periodically and log any changes
     * Enhanced with proactive reconnection triggers
     */
    private fun startConnectionMonitoring() {
        stopConnectionMonitoring()
        
        Log.d(TAG, "Starting connection monitoring")
        
        connectionMonitorJob = heartbeatScope.launch {
            var lastConnectionState = false
            var disconnectedStartTime: Long? = null
            
            while (isActive) {
                try {
                    val isConnected = BleManager.instance.isBleConnected()
                    if (isConnected != lastConnectionState) {
                        Log.i(TAG, "Connection state changed: $lastConnectionState -> $isConnected")
                        lastConnectionState = isConnected
                        
                        if (isConnected) {
                            disconnectedStartTime = null
                            connectionState = ConnectionState.CONNECTED
                            reconnectionAttempts = 0
                            
                            // Ensure wake lock is acquired when connection is established
                            if (wakeLock == null || !wakeLock!!.isHeld) {
                                acquireWakeLock()
                            }
                            
                            updateNotification()
                            Log.i(TAG, "BLE connection established")
                        } else {
                            disconnectedStartTime = System.currentTimeMillis()
                            connectionState = ConnectionState.DISCONNECTED
                            updateNotification()
                            Log.w(TAG, "BLE connection lost detected by monitor")
                            
                            // Start reconnection if not already trying
                            if (reconnectionJob == null || !reconnectionJob!!.isActive) {
                                startReconnection()
                            }
                        }
                    } else if (!isConnected && disconnectedStartTime != null) {
                        // Check if disconnected for too long without reconnection
                        val disconnectedDuration = System.currentTimeMillis() - disconnectedStartTime!!
                        if (disconnectedDuration > 30000 && (reconnectionJob == null || !reconnectionJob!!.isActive)) {
                            Log.w(TAG, "Connection lost for ${disconnectedDuration/1000}s, triggering reconnection")
                            startReconnection()
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error monitoring connection", e)
                }
                
                // Check every 5 seconds
                delay(5000)
            }
        }
    }
    
    /**
     * Stop connection monitoring
     */
    private fun stopConnectionMonitoring() {
        connectionMonitorJob?.cancel()
        connectionMonitorJob = null
        Log.d(TAG, "Connection monitoring stopped")
    }
    
    /**
     * Start automatic reconnection with exponential backoff
     */
    private fun startReconnection() {
        stopReconnection() // Stop any existing reconnection attempt
        
        val (leftDevice, rightDevice, channelNumber) = getSavedConnectionState()
        if (leftDevice == null || rightDevice == null || channelNumber == null) {
            Log.w(TAG, "Cannot reconnect: no saved connection state")
            connectionState = ConnectionState.DISCONNECTED
            updateNotification()
            return
        }
        
        if (reconnectionAttempts >= maxReconnectionAttempts) {
            Log.e(TAG, "Max reconnection attempts ($maxReconnectionAttempts) reached, giving up")
            connectionState = ConnectionState.DISCONNECTED
            updateNotification()
            return
        }
        
        Log.i(TAG, "Starting reconnection attempt ${reconnectionAttempts + 1}/$maxReconnectionAttempts for channel $channelNumber")
        connectionState = ConnectionState.RECONNECTING
        updateNotification()
        
        reconnectionJob = heartbeatScope.launch {
            // Calculate exponential backoff delay: 5s, 10s, 20s, 40s, 60s (max)
            val baseDelay = 5000L
            val maxDelay = 60000L
            val delayMs = minOf(baseDelay * (1L shl reconnectionAttempts), maxDelay)
            
            Log.d(TAG, "Waiting ${delayMs/1000}s before reconnection attempt")
            delay(delayMs)
            
            if (!isActive) {
                return@launch
            }
            
            try {
                // Ensure wake lock is held for reconnection attempt
                if (wakeLock == null || !wakeLock!!.isHeld) {
                    acquireWakeLock()
                }
                
                // Attempt to reconnect via BleManager
                // Note: This requires access to the Activity context or we need to add a method to BleManager
                // that can reconnect using saved device names
                val reconnectSuccess = attemptReconnection(channelNumber)
                
                if (reconnectSuccess) {
                    Log.i(TAG, "Reconnection successful!")
                    reconnectionAttempts = 0
                    connectionState = ConnectionState.CONNECTED
                    
                    // Wake lock should already be held, but ensure it is
                    if (wakeLock == null || !wakeLock!!.isHeld) {
                        acquireWakeLock()
                    }
                    
                    updateNotification()
                    
                    // Restart heartbeat
                    startNativeHeartbeat()
                } else {
                    reconnectionAttempts++
                    Log.w(TAG, "Reconnection attempt failed, will retry (attempt $reconnectionAttempts/$maxReconnectionAttempts)")
                    if (reconnectionAttempts < maxReconnectionAttempts) {
                        // Schedule next attempt
                        startReconnection()
                    } else {
                        connectionState = ConnectionState.DISCONNECTED
                        updateNotification()
                        Log.e(TAG, "All reconnection attempts failed")
                    }
                }
            } catch (e: Exception) {
                // Don't release wake lock on exception - keep it for retry
                Log.e(TAG, "Error during reconnection: ${e.message}", e)
                reconnectionAttempts++
                if (reconnectionAttempts < maxReconnectionAttempts) {
                    startReconnection()
                } else {
                    connectionState = ConnectionState.DISCONNECTED
                    updateNotification()
                    // Only release wake lock if we're giving up completely
                    // For now, keep it in case user manually reconnects
                }
            }
        }
    }
    
    /**
     * Attempt to reconnect to saved devices using BleManager
     */
    private suspend fun attemptReconnection(channelNumber: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                // Check if already connected
                if (BleManager.instance.isBleConnected()) {
                    Log.i(TAG, "Already connected, no need to reconnect")
                    return@withContext true
                }
                
                // Attempt reconnection via BleManager
                Log.d(TAG, "Reconnection attempt - trying to reconnect to channel $channelNumber")
                val success = BleManager.instance.reconnectToChannel(channelNumber)
                
                if (success) {
                    // Wait a bit to see if connection succeeds
                    delay(5000)
                    return@withContext BleManager.instance.isBleConnected()
                }
                
                false
            } catch (e: Exception) {
                Log.e(TAG, "Error in reconnection attempt: ${e.message}", e)
                false
            }
        }
    }
    
    /**
     * Stop reconnection attempts
     */
    private fun stopReconnection() {
        reconnectionJob?.cancel()
        reconnectionJob = null
    }
    
    /**
     * Build notification with actions and status
     */
    private fun buildNotification(): android.app.Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Try to use app icon, fallback to system icon
        val iconRes = try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            appInfo.icon
        } catch (e: Exception) {
            android.R.drawable.ic_menu_mylocation
        }
        
        // Build status text based on connection state
        val statusText = when (connectionState) {
            ConnectionState.CONNECTED -> {
                "Maintaining connection to glasses"
            }
            ConnectionState.RECONNECTING -> {
                "Reconnecting... (attempt ${reconnectionAttempts + 1}/$maxReconnectionAttempts)"
            }
            ConnectionState.DISCONNECTED -> {
                "Disconnected - Tap to reconnect"
            }
        }
        
        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Even AI ${connectionState.name.lowercase().capitalize()}")
            .setContentText(statusText)
            .setSmallIcon(if (iconRes != 0) iconRes else android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(connectionState != ConnectionState.DISCONNECTED)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setShowWhen(false)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        
        // Add action buttons
        if (connectionState == ConnectionState.DISCONNECTED || connectionState == ConnectionState.RECONNECTING) {
            // Reconnect action
            val reconnectIntent = Intent(ACTION_RECONNECT).apply {
                setClass(this@NotificationForwardingService, NotificationForwardingService::class.java)
            }
            val reconnectPendingIntent = PendingIntent.getService(
                this,
                1,
                reconnectIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(
                android.R.drawable.ic_menu_mylocation,
                "Reconnect",
                reconnectPendingIntent
            )
        }
        
        // Stop service action
        val stopIntent = Intent(ACTION_STOP_SERVICE).apply {
            setClass(this@NotificationForwardingService, NotificationForwardingService::class.java)
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            2,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        builder.addAction(
            android.R.drawable.ic_menu_close_clear_cancel,
            "Stop",
            stopPendingIntent
        )
        
        return builder.build()
    }
    
    /**
     * Update notification with current state
     */
    private fun updateNotification() {
        try {
            val notification = buildNotification()
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Error updating notification: ${e.message}", e)
        }
    }
    
}

