package com.example.demo_ai_even.bluetooth

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.util.Log
import android.widget.Toast
import com.example.demo_ai_even.cpp.Cpp
import com.example.demo_ai_even.model.BleDevice
import com.example.demo_ai_even.model.BlePairDevice
import com.example.demo_ai_even.speech.SpeechRecognitionManager
import com.example.demo_ai_even.utils.ByteUtil
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import java.lang.ref.WeakReference
import java.util.UUID

@SuppressLint("MissingPermission")
class BleManager private constructor() {

    companion object {
        val LOG_TAG = BleManager::class.simpleName

        private const val SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
        private const val WRITE_CHARACTERISTIC_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
        private const val READ_CHARACTERISTIC_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
        
        // Heartbeat constants
        private const val HEARTBEAT_INTERVAL_MS = 15000L // 15 seconds

        //  SingleInstance
        private var mInstance: BleManager? = null
        val instance: BleManager = mInstance ?: BleManager()
    }

    //  Context
    private lateinit var weakActivity: WeakReference<Activity>
    //  Scan，Connect，Disconnect，Send
    private lateinit var bluetoothManager: BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter
        get() = bluetoothManager.adapter
    //  Save device address
    private val bleDevices: MutableList<BleDevice> = mutableListOf()
    private var connectedDevice: BlePairDevice? = null

    /// Scan Config
    //  - Setting: Low latency
    private val scanSettings = ScanSettings
        .Builder()
        .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
        .build()
    //  -
    private val scanCallback: ScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            super.onScanResult(callbackType, result)
            val device = result?.device ?: return
            
            //  eg. G1_45_L_92333
            if (device.name.isNullOrEmpty()) {
                return
            }
            
            if (!device.name.contains("G\\d+".toRegex())) {
                return
            }
            
            val nameParts = device.name.split("_")
            if (nameParts.size != 4) {
                return
            }
            
            if (bleDevices.firstOrNull { it.address == device.address } != null) {
                return
            }
            
            //  1. Get same channel num device,and make pair
            val channelNum = device.name.split("_")[1]
            bleDevices.add(BleDevice.createByDevice(device.name, device.address, channelNum))
            
            val pairDevices = bleDevices.filter { it.name.contains("_$channelNum" + "_") }
            
            if (pairDevices.size <= 1) {
                return
            }
            val leftDevice = pairDevices.firstOrNull { it.isLeft() }
            val rightDevice = pairDevices.firstOrNull { it.isRight() }
            if (leftDevice == null || rightDevice == null) {
                return
            }
            BleChannelHelper.bleMC.flutterFoundPairedGlasses(BlePairDevice(leftDevice, rightDevice))
        }
        override fun onScanFailed(errorCode: Int) {
            super.onScanFailed(errorCode)
            Log.e(LOG_TAG, "Scan failed: $errorCode")
        }
    }

    /// UI Thread
    private val  mainScope: CoroutineScope = MainScope()

    //*================= Method - Public =================*//

    /**
     * Init bluetooth manager and get bluetooth adapter
     *
     * @param context
     *
     */
    fun initBluetooth(context: Activity) {
        weakActivity = WeakReference(context)
        bluetoothManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.getSystemService(BluetoothManager::class.java)
        } else {
            context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        }
        Log.v(LOG_TAG, "BleManager init success")
    }

    /**
     *
     */
    fun startScan(result: MethodChannel.Result) {
        if (!checkBluetoothStatus()) {
            result.error("Permission", "Bluetooth not enabled or permissions not granted", null)
            return
        }
        bleDevices.clear()
        try {
            bluetoothAdapter.bluetoothLeScanner.startScan(null, scanSettings, scanCallback)
            result.success("Scanning for devices...")
        } catch (e: Exception) {
            Log.e(LOG_TAG, "Failed to start scan: ${e.message}", e)
            result.error("ScanError", "Failed to start scan: ${e.message}", null)
        }
    }

    /**
     *
     */
    fun stopScan(result: MethodChannel.Result? = null) {
        if (!checkBluetoothStatus()) {
            result?.error("Permission", "", null)
            return
        }
        bluetoothAdapter.bluetoothLeScanner.stopScan(scanCallback)
        Log.v(LOG_TAG, "Stop scan")
        result?.success("Scan stopped")
    }

    /**
     *
     */
    fun connectToGlass(deviceChannel: String, result: MethodChannel.Result) {
        Log.i(LOG_TAG, "connectToGlass: deviceChannel = $deviceChannel")
        val leftPairChannel = "_$deviceChannel" + "_L_"
        var leftDevice = connectedDevice?.leftDevice
        if (leftDevice?.name?.contains(leftPairChannel) != true) {
            leftDevice = bleDevices.firstOrNull { it.name.contains(leftPairChannel) }
        }
        val rightPairChannel = "_$deviceChannel" + "_R_"
        var rightDevice = connectedDevice?.rightDevice
        if (rightDevice?.name?.contains(rightPairChannel) != true) {
            rightDevice = bleDevices.firstOrNull { it.name.contains(rightPairChannel) }
        }
        if (leftDevice == null || rightDevice == null) {
            result.error("PeripheralNotFound", "One or both peripherals are not found", null)
            // Notify Flutter about connection failure
            BleChannelHelper.bleMC.flutterGlassesConnectionFailed(-1)
            return
        }
        connectedDevice = BlePairDevice(leftDevice, rightDevice)
        weakActivity.get()?.let {
            // Notify Flutter that connection is starting
            BleChannelHelper.bleMC.flutterGlassesConnecting(emptyMap())
            
            bluetoothAdapter.getRemoteDevice(leftDevice.address).connectGatt(it, false, bleGattCallBack())
            bluetoothAdapter.getRemoteDevice(rightDevice.address).connectGatt(it, false, bleGattCallBack())
        }
        result.success("Connecting to G1_$deviceChannel ...")
    }

    /**
     *
     */
    fun disconnectFromGlasses(result: MethodChannel.Result) {
        Log.i(LOG_TAG, "connectToGlass: G1_${connectedDevice?.deviceName()}")
        result.success("Disconnected all devices.")
    }

    /**
     * Check if BLE devices are currently connected
     * @return true if both left and right devices are connected, false otherwise
     */
    fun isBleConnected(): Boolean {
        val device = connectedDevice ?: return false
        // Check both that the flag is set AND that the GATT connection is actually active
        val leftGatt = device.leftDevice?.gatt
        val rightGatt = device.rightDevice?.gatt
        val leftConnected = device.leftDevice?.isConnect == true && 
                            leftGatt != null
        val rightConnected = device.rightDevice?.isConnect == true && 
                             rightGatt != null
        return leftConnected && rightConnected
    }

    /**
     * Send heartbeat data to both left and right devices
     * This is used by the foreground service to maintain connection in background
     * @param data The heartbeat packet data
     * @return true if both devices sent successfully, false otherwise
     */
    fun sendHeartbeatData(data: ByteArray): Boolean {
        if (!isBleConnected()) {
            Log.w(LOG_TAG, "sendHeartbeatData: Devices not connected, skipping")
            return false
        }
        try {
            val leftResult = connectedDevice?.leftDevice?.sendData(data) ?: false
            val rightResult = connectedDevice?.rightDevice?.sendData(data) ?: false
            
            if (leftResult && rightResult) {
                Log.v(LOG_TAG, "Heartbeat data sent successfully to both devices")
                return true
            } else {
                Log.w(LOG_TAG, "Heartbeat send failed - Left: $leftResult, Right: $rightResult")
                return false
            }
        } catch (e: Exception) {
            Log.e(LOG_TAG, "Error sending heartbeat data", e)
            return false
        }
    }
    
    /**
     * Reconnect to devices using saved channel number
     * This is called by the service to attempt automatic reconnection
     * @param channelNumber The channel number to reconnect to
     * @return true if reconnection was initiated successfully, false otherwise
     */
    fun reconnectToChannel(channelNumber: String): Boolean {
        Log.i(LOG_TAG, "Attempting to reconnect to channel: $channelNumber")
        
        if (!checkBluetoothStatus()) {
            Log.w(LOG_TAG, "Cannot reconnect: Bluetooth not available")
            return false
        }
        
        // Check if already connected to this channel
        val currentChannel = connectedDevice?.leftDevice?.channelNumber
        if (currentChannel == channelNumber && isBleConnected()) {
            Log.i(LOG_TAG, "Already connected to channel $channelNumber")
            return true
        }
        
        // Clear existing connection if any
        connectedDevice?.let {
            it.leftDevice?.gatt?.disconnect()
            it.rightDevice?.gatt?.disconnect()
            it.leftDevice?.gatt?.close()
            it.rightDevice?.gatt?.close()
        }
        connectedDevice = null
        bleDevices.clear()
        
        // Start scan and connect
        try {
            // Start scan to find devices
            bluetoothAdapter.bluetoothLeScanner.startScan(null, scanSettings, scanCallback)
            
            // Use a coroutine to wait a bit for devices to be found, then connect
            mainScope.launch {
                kotlinx.coroutines.delay(2000) // Wait 2 seconds for scan
                stopScan()
                
                // Try to connect
                val leftPairChannel = "_$channelNumber" + "_L_"
                val rightPairChannel = "_$channelNumber" + "_R_"
                val leftDevice = bleDevices.firstOrNull { it.name.contains(leftPairChannel) }
                val rightDevice = bleDevices.firstOrNull { it.name.contains(rightPairChannel) }
                
                if (leftDevice != null && rightDevice != null) {
                    connectedDevice = BlePairDevice(leftDevice, rightDevice)
                    weakActivity.get()?.let { activity ->
                        bluetoothAdapter.getRemoteDevice(leftDevice.address).connectGatt(activity, false, bleGattCallBack())
                        bluetoothAdapter.getRemoteDevice(rightDevice.address).connectGatt(activity, false, bleGattCallBack())
                        Log.i(LOG_TAG, "Reconnection initiated for channel $channelNumber")
                    }
                } else {
                    Log.w(LOG_TAG, "Could not find devices for channel $channelNumber")
                }
            }
            
            return true
        } catch (e: Exception) {
            Log.e(LOG_TAG, "Error during reconnection: ${e.message}", e)
            return false
        }
    }

    /**
     *
     */
    fun senData(params: Map<*, *>?) {
        val data = params?.get("data") as ByteArray? ?: byteArrayOf()
        if (data.isEmpty()) {
            Log.e(LOG_TAG, "Send data is empty")
            return
        }
        val lr = params?.get("lr") as String?
        when (lr) {
            null -> requestData(data)
            "L" -> requestData(data, sendLeft = true)
            "R" -> requestData(data, sendRight = true)
        }
    }

    //*================= Method - Private =================*//

    /**
     *  Check if Bluetooth is turned on and permission status
     */
    private fun checkBluetoothStatus(): Boolean {
        if (weakActivity.get() == null) {
            return false
        }
        if (!bluetoothAdapter.isEnabled) {
            Toast.makeText(weakActivity.get()!!, "Bluetooth is turned off, please turn it on first!", Toast.LENGTH_SHORT).show()
            return false
        }
        return BlePermissionUtil.checkBluetoothPermission(weakActivity.get()!!)
    }

    /**
     *
     */
    private fun bleGattCallBack(): BluetoothGattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            super.onConnectionStateChange(gatt, status, newState)
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    gatt?.discoverServices()
                } else {
                    // Connection failed
                    Log.e(LOG_TAG, "Connection failed with status: $status")
                    weakActivity.get()?.runOnUiThread {
                        BleChannelHelper.bleMC.flutterGlassesConnectionFailed(status)
                    }
                }
            } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                // Handle disconnection
                Log.d(LOG_TAG, "Device disconnected: ${gatt?.device?.address}, status: $status")
                
                // Update device connection state
                connectedDevice?.let { device ->
                    if (gatt?.device?.address == device.leftDevice?.address) {
                        device.update(isLeftConnect = false)
                        Log.d(LOG_TAG, "Left device marked as disconnected")
                    } else if (gatt?.device?.address == device.rightDevice?.address) {
                        device.update(isRightConnected = false)
                        Log.d(LOG_TAG, "Right device marked as disconnected")
                    }
                }
                
                if (status != BluetoothGatt.GATT_SUCCESS && connectedDevice != null) {
                    // Connection failed during connection attempt
                    weakActivity.get()?.runOnUiThread {
                        BleChannelHelper.bleMC.flutterGlassesConnectionFailed(status)
                    }
                } else {
                    // Normal disconnection - check if both devices are disconnected
                    val isBothDisconnected = connectedDevice?.isBothConnected() != true
                    if (isBothDisconnected) {
                        Log.d(LOG_TAG, "Both devices disconnected, notifying Flutter")
                        weakActivity.get()?.runOnUiThread {
                            BleChannelHelper.bleMC.flutterGlassesDisconnected(emptyMap())
                        }
                    } else {
                        Log.d(LOG_TAG, "One device disconnected, but connection still active")
                    }
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            super.onServicesDiscovered(gatt, status)
            Log.e(
                LOG_TAG,
                "BluetoothGattCallback - onServicesDiscovered: $gatt, status = $status"
            )
            connectedDevice?.let {
                //  1. Save gatt
                var isLeft = false
                var isRight = false
                if (gatt?.device?.address == it.leftDevice?.address) {
                    it.update(leftGatt = gatt)
                    isLeft = true
                } else if (gatt?.device?.address == it.rightDevice?.address) {
                    it.update(rightGatt = gatt)
                    isRight = true
                }
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    //  1. Check if it is already connected, and if it is, do not repeat the process
                    if ((isLeft && it.leftDevice?.isConnect == true) ||
                        (isRight && it.rightDevice?.isConnect == true)) {
                        return
                    }
                    //  2. Get Bluetooth read-write services
                    val server = gatt?.getService(UUID.fromString(SERVICE_UUID))
                    //  3. Check if gatt can read character
                    val readCharacteristic =
                        server?.getCharacteristic(UUID.fromString(READ_CHARACTERISTIC_UUID))
                    if (readCharacteristic == null) {
                        Log.e(
                            LOG_TAG,
                            "BluetoothGattCallback - onServicesDiscovered: $gatt, Not found readCharacteristicUuid from $server"
                        )
                        return
                    }
                    gatt.setCharacteristicNotification(readCharacteristic, true)
                    //  4. Check if gatt can write character
                    val writeCharacteristic =
                        server.getCharacteristic(UUID.fromString(WRITE_CHARACTERISTIC_UUID))
                    if (writeCharacteristic == null) {
                        Log.e(LOG_TAG, "BluetoothGattCallback - onServicesDiscovered: $gatt, Not found readCharacteristicUuid from $server")
                        return
                    }
                    if (isLeft) {
                        connectedDevice?.leftDevice?.writeCharacteristic = writeCharacteristic
                    } else {
                        connectedDevice?.rightDevice?.writeCharacteristic = writeCharacteristic
                    }
                    //  5.
                    val descriptor =
                        readCharacteristic.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))
                    Log.d(LOG_TAG, "BluetoothGattCallback - onServicesDiscovered: $gatt, get descriptor :${descriptor}")
                    descriptor?.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                    val isWrite = gatt.writeDescriptor(descriptor)
                    Log.d(LOG_TAG, "BluetoothGattCallback - onServicesDiscovered: descriptor isWrite :${isWrite}")
                    //  6.
                    gatt.requestMtu(251)
                    //  7.
                    gatt.device?.createBond()
                    //  8. Update connect status，and check is both connected
                    if (isLeft) {
                        it.update(leftGatt = gatt, isLeftConnect = true)
                    } else if (isRight) {
                        it.update(rightGatt = gatt, isRightConnected = true)
                    }
                    requestData(byteArrayOf(0xf4.toByte(), 0x01.toByte()))
                    if (it.isBothConnected()) {
                        // Save connection state to service
                        try {
                            val service = com.example.demo_ai_even.notification.NotificationForwardingService
                            val leftName = it.leftDevice?.name ?: ""
                            val rightName = it.rightDevice?.name ?: ""
                            val channel = it.leftDevice?.channelNumber ?: ""
                            if (leftName.isNotEmpty() && rightName.isNotEmpty() && channel.isNotEmpty()) {
                                // We need to call saveConnectionState, but it's an instance method
                                // So we'll save it via a static method or save to SharedPreferences directly
                                val prefs = weakActivity.get()?.getSharedPreferences(
                                    "even_ai_service_state",
                                    android.content.Context.MODE_PRIVATE
                                )
                                prefs?.edit()?.apply {
                                    putString("left_device_name", leftName)
                                    putString("right_device_name", rightName)
                                    putString("channel_number", channel)
                                    putLong("connection_timestamp", System.currentTimeMillis())
                                    apply()
                                }
                                Log.d(LOG_TAG, "Connection state saved: $leftName / $rightName (channel: $channel)")
                            }
                        } catch (e: Exception) {
                            Log.w(LOG_TAG, "Could not save connection state: ${e.message}")
                        }
                        
                        weakActivity.get()?.runOnUiThread {
                            BleChannelHelper.bleMC.flutterGlassesConnected(it.toConnectedJson())
                        }
                    }
                }
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            super.onCharacteristicChanged(gatt, characteristic, value)
            mainScope.launch {
                val isLeft = gatt.device.address == connectedDevice?.leftDevice?.address
                val isRight = gatt.device.address == connectedDevice?.rightDevice?.address
                if (!isLeft && !isRight) {
                    return@launch
                }
                //  Mic data:
                //  - each pack data length must be 202
                //  - data index: 0 = cmd, 1 = pack serial number，2～201 = real mic data
                val isMicData = value[0] == 0xF1.toByte()
                if(isMicData && value.size != 202) {
                    return@launch
                }
                //  eg. LC3 to PCM
                if (isMicData) {
                    val lc3 = value.copyOfRange(2, 202)
                    val pcmData = Cpp.decodeLC3(lc3)!!//200

                    // Pass PCM data to SpeechRecognitionManager
                    // This will use Google Cloud Speech-to-Text if credentials are available,
                    // otherwise falls back to Android SpeechRecognizer (phone mic only)
                    SpeechRecognitionManager.instance.appendPCMData(pcmData)
                    
                    // Only log if recognition is active - don't spam logs after recognition is done
                    if (com.example.demo_ai_even.speech.SpeechRecognitionManager.instance.isRecognitionActive()) {
                        Log.d(this::class.simpleName,"============Lc3 data = $lc3, Pcm = $pcmData")
                    }
                }
                BleChannelHelper.bleReceive(mapOf(
                    "lr" to if (isLeft)  "L" else "R",
                    "data" to value,
                    "type" to if (isMicData)  "VoiceChunk" else "Receive",
                 ))
            }
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int
        ) {
            super.onCharacteristicRead(gatt, characteristic, value, status)
            print("===========onCharacteristicRead: $value")
        }

    }

    /**
     *
     */
    private fun requestData(data: ByteArray, sendLeft: Boolean = false, sendRight: Boolean = false) {
        val isBothSend = !sendLeft && !sendRight
        Log.d(LOG_TAG, "Send ${ if (isBothSend) "both" else if (sendLeft)  "left" else "right"} data = ${ByteUtil.byteToHexArray(data)}")
        if (sendLeft || isBothSend) {
            connectedDevice?.leftDevice?.sendData(data)
        }
        if (sendRight || isBothSend) {
            connectedDevice?.rightDevice?.sendData(data)
        }
    }

}