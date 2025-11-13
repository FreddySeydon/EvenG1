package com.example.demo_ai_even.call

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.ContactsContract
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.example.demo_ai_even.bluetooth.BleChannelHelper
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

class CallStateListener(private val context: Context) {
    private val TAG = "CallStateListener"
    
    private var telephonyManager: TelephonyManager? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var telephonyCallback: TelephonyCallback? = null
    private var isListening = false
    private var lastCallNumber: String? = null
    private var lastCallState: Int = TelephonyManager.CALL_STATE_IDLE
    
    // Cache for caller name lookups
    private val callerNameCache = ConcurrentHashMap<String, String>()
    
    companion object {
        private var instance: CallStateListener? = null
        
        fun getInstance(context: Context): CallStateListener {
            if (instance == null) {
                instance = CallStateListener(context.applicationContext)
            }
            return instance!!
        }
    }
    
    /**
     * Start listening for call state changes
     */
    fun startListening() {
        if (isListening) {
            Log.d(TAG, "Already listening for call state changes")
            return
        }
        
        // Check if we have phone state permission
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE) 
            != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "READ_PHONE_STATE permission not granted, cannot listen for calls")
            return
        }
        
        try {
            telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            
            if (telephonyManager == null) {
                Log.e(TAG, "TelephonyManager not available")
                return
            }
            
            // Try PhoneStateListener first (works on all versions, deprecated but functional)
            // PhoneStateListener provides phone number directly in onCallStateChanged
            try {
                phoneStateListener = object : PhoneStateListener() {
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                        handleCallStateChanged(state, phoneNumber)
                    }
                }
                
                telephonyManager?.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE)
                Log.d(TAG, "Using PhoneStateListener for call detection")
            } catch (e: Exception) {
                Log.w(TAG, "PhoneStateListener failed, trying TelephonyCallback: ${e.message}")
                
                // Fallback to TelephonyCallback for Android 12+ if PhoneStateListener fails
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    telephonyCallback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                        override fun onCallStateChanged(state: Int) {
                            val phoneNumber = if (state == TelephonyManager.CALL_STATE_RINGING) {
                                getIncomingNumberForRinging()
                            } else {
                                null
                            }
                            handleCallStateChanged(state, phoneNumber)
                        }
                    }
                    
                    telephonyManager?.registerTelephonyCallback(
                        context.mainExecutor,
                        telephonyCallback as TelephonyCallback
                    )
                    Log.d(TAG, "Using TelephonyCallback for call detection")
                }
            }
            
            isListening = true
            Log.d(TAG, "Started listening for call state changes")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting call state listener: ${e.message}", e)
        }
    }
    
    /**
     * Stop listening for call state changes
     */
    fun stopListening() {
        if (!isListening) {
            return
        }
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyCallback?.let {
                    telephonyManager?.unregisterTelephonyCallback(it)
                }
            } else {
                phoneStateListener?.let {
                    telephonyManager?.listen(it, PhoneStateListener.LISTEN_NONE)
                }
            }
            
            phoneStateListener = null
            telephonyCallback = null
            isListening = false
            Log.d(TAG, "Stopped listening for call state changes")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping call state listener: ${e.message}", e)
        }
    }
    
    /**
     * Handle call state changes
     */
    private fun handleCallStateChanged(state: Int, phoneNumber: String?) {
        Log.d(TAG, "Call state changed: $state, phoneNumber: $phoneNumber")
        
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                // Incoming call is ringing
                val incomingNumber = phoneNumber ?: getIncomingNumberForRinging()
                if (incomingNumber != null && incomingNumber.isNotEmpty() && incomingNumber != lastCallNumber) {
                    lastCallNumber = incomingNumber
                    lastCallState = state
                    handleIncomingCall(incomingNumber)
                } else if (phoneNumber == null) {
                    // If we can't get the number, still show a generic incoming call notification
                    Log.d(TAG, "Incoming call detected but phone number unavailable")
                    // Note: On some devices, the NotificationListenerService may catch the call notification
                    // with caller info, so we don't duplicate here
                }
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                // Call is answered or outgoing call started
                if (lastCallState == TelephonyManager.CALL_STATE_RINGING) {
                    Log.d(TAG, "Call answered")
                    // Optionally clear or update notification
                }
                lastCallState = state
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                // Call ended
                if (lastCallState != TelephonyManager.CALL_STATE_IDLE) {
                    Log.d(TAG, "Call ended")
                    // Optionally clear notification
                }
                lastCallState = state
                lastCallNumber = null
            }
        }
    }
    
    /**
     * Get incoming number when call is ringing (Android 8+)
     * Note: This is limited due to privacy restrictions on newer Android versions
     */
    private fun getIncomingNumberForRinging(): String? {
        return try {
            // Try to get from call log (requires READ_CALL_LOG permission)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG) 
                    == PackageManager.PERMISSION_GRANTED) {
                    val cursor = context.contentResolver.query(
                        android.provider.CallLog.Calls.CONTENT_URI,
                        arrayOf(android.provider.CallLog.Calls.NUMBER),
                        "${android.provider.CallLog.Calls.TYPE} = ?",
                        arrayOf(android.provider.CallLog.Calls.INCOMING_TYPE.toString()),
                        "${android.provider.CallLog.Calls.DATE} DESC LIMIT 1"
                    )
                    cursor?.use {
                        if (it.moveToFirst()) {
                            val number = it.getString(it.getColumnIndexOrThrow(android.provider.CallLog.Calls.NUMBER))
                            if (!number.isNullOrEmpty()) {
                                return number
                            }
                        }
                    }
                }
            }
            // Fallback: try to get from telephony manager (may not work on all devices)
            null
        } catch (e: Exception) {
            Log.e(TAG, "Error getting incoming number: ${e.message}", e)
            null
        }
    }
    
    /**
     * Handle incoming call - extract info and send to Flutter
     */
    private fun handleIncomingCall(phoneNumber: String) {
        Log.d(TAG, "Handling incoming call from: $phoneNumber")
        
        // Resolve caller name
        val callerName = getCallerDisplayName(phoneNumber)
        
        // Format call notification
        val callNotification = JSONObject().apply {
            put("msg_id", System.currentTimeMillis().toInt() and 0x7FFFFFFF)
            put("app_identifier", "com.android.phone")
            put("title", "Incoming Call")
            put("subtitle", callerName)
            put("message", phoneNumber)
            put("time_s", (System.currentTimeMillis() / 1000).toInt())
            put("display_name", "Phone")
        }
        
        Log.d(TAG, "Sending call notification to Flutter: $callNotification")
        
        // Send to Flutter via existing notification channel
        BleChannelHelper.bleNotificationReceived(callNotification.toString())
    }
    
    fun getCallerDisplayName(phoneNumber: String): String {
        return resolveCallerNameInternal(phoneNumber)
    }

    private fun resolveCallerNameInternal(phoneNumber: String): String {
        // Check cache first
        callerNameCache[phoneNumber]?.let {
            return it
        }
        
        // Check if we have contacts permission
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) 
            != PackageManager.PERMISSION_GRANTED) {
            Log.d(TAG, "READ_CONTACTS permission not granted, using phone number")
            return phoneNumber
        }
        
        try {
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            )
            
            // Normalize phone number for lookup (remove formatting)
            val normalizedNumber = phoneNumber.replace(Regex("[^0-9]"), "")
            
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                projection,
                null,
                null,
                null
            )
            
            cursor?.use {
                while (it.moveToNext()) {
                    val name = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME))
                    val number = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER))
                    val normalizedContactNumber = number.replace(Regex("[^0-9]"), "")
                    
                    // Check if numbers match (last 10 digits for US numbers)
                    if (normalizedContactNumber.endsWith(normalizedNumber) || 
                        normalizedNumber.endsWith(normalizedContactNumber)) {
                        // Cache the result
                        callerNameCache[phoneNumber] = name
                        return name
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error resolving caller name: ${e.message}", e)
        }
        
        // If not found, return phone number and cache it
        callerNameCache[phoneNumber] = phoneNumber
        return phoneNumber
    }
    
    /**
     * Clear caller name cache
     */
    fun clearCache() {
        callerNameCache.clear()
    }
}

