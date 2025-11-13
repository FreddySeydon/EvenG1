//
//  AppDelegate.swift
//  Runner
//
//  Created by Hawk on 2024/10/23.
//

import UIKit
import Flutter
import BackgroundTasks
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var blueInstance = BluetoothManager.shared
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
 
        GeneratedPluginRegistrant.register(with: self)
        let controller = window?.rootViewController as! FlutterViewController
        let messenger : FlutterBinaryMessenger = window?.rootViewController as! FlutterBinaryMessenger
        let channel = FlutterMethodChannel(name: "method.bluetooth", binaryMessenger: controller.binaryMessenger)
        
        blueInstance = BluetoothManager(channel: channel)
        
        // Initialize call state listener
        CallStateListener.shared.startListening()

        // Set method call handler for Flutter channel
        channel.setMethodCallHandler { [weak self] (call, result) in
            print("AppDelegate----call----\(call)----\(call.method)---------")
            guard let self = self else { return }

            switch call.method {
            case "startScan":
                self.blueInstance.startScan(result: result)
            case "stopScan":
                self.blueInstance.stopScan(result: result)
            case "connectToGlasses":
                if let args = call.arguments as? [String: Any], let deviceName = args["deviceName"] as? String {
                    self.blueInstance.connectToDevice(deviceName: deviceName, result: result)
                } else {
                    result(FlutterError(code: "InvalidArguments", message: "Invalid arguments", details: nil))
                }
            case "disconnectFromGlasses":
                self.blueInstance.disconnectFromGlasses(result: result)
            case "send":
                let params = call.arguments as? [String : Any]
                self.blueInstance.sendData(params: params!)
                result(nil)
            case "startEvenAI":
                // todo dynamic language
                SpeechStreamRecognizer.shared.startRecognition(identifier: "EN")
                result(nil)
            case "stopEvenAI":
                SpeechStreamRecognizer.shared.stopRecognition()
                result(nil)
            case "checkNotificationPermission":
                // iOS doesn't support notification listener service like Android
                // Full notification interception requires Notification Service Extension
                result(false)
            case "openNotificationSettings":
                // Open iOS notification settings
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                result(nil)
            case "getInstalledApps":
                // iOS doesn't allow querying all installed apps for privacy reasons
                // Return empty list or apps we can query (requires special entitlements)
                result([])
            case "startForegroundService":
                // iOS equivalent: Start background task to keep app running
                self.startBackgroundService(result: result)
            case "stopForegroundService":
                // iOS equivalent: Stop background task
                self.stopBackgroundService(result: result)
            case "checkBleConnectionStatus":
                // Check if BLE is connected
                let isConnected = self.blueInstance.leftPeripheral != nil && 
                                 self.blueInstance.rightPeripheral != nil &&
                                 self.blueInstance.leftWChar != nil &&
                                 self.blueInstance.rightWChar != nil
                result(isConnected)
            case "requestNotificationPermission":
                // iOS notification permission is handled by system
                // Return true as iOS handles this automatically
                result(true)
            case "requestBatteryOptimization":
                // iOS doesn't have battery optimization like Android
                // Return true as iOS handles background execution differently
                result(true)
            case "checkBatteryOptimization":
                // iOS doesn't have battery optimization like Android
                // Return true as iOS handles background execution differently
                result(true)
            case "showWeatherNotification":
                // Show local notification for weather update
                if let args = call.arguments as? [String: Any], let message = args["message"] as? String {
                    self.showWeatherNotification(message: message, result: result)
                } else {
                    result(FlutterError(code: "InvalidArguments", message: "message is required", details: nil))
                }
            case "resolveCallerName":
                // Resolve caller name from phone number
                if let args = call.arguments as? [String: Any], let phoneNumber = args["phoneNumber"] as? String {
                    let name = CallStateListener.shared.getCallerDisplayName(phoneNumber: phoneNumber)
                    result(name)
                } else {
                    result(FlutterError(code: "InvalidArguments", message: "phoneNumber is required", details: nil))
                }
            case "glassesConnectionFailed":
                // Handle connection failure if needed
                break
            default:
                result(FlutterMethodNotImplemented)
            }
        }
     
        let scheduleEvent = FlutterEventChannel(name: "eventBleReceive", binaryMessenger: messenger)
        scheduleEvent.setStreamHandler(self)
        
        let eventSpeechRecognizeEvent = FlutterEventChannel(name: "eventSpeechRecognize", binaryMessenger: messenger)
        eventSpeechRecognizeEvent.setStreamHandler(self)
        
        // Notification event channels (iOS doesn't support full notification interception)
        let eventNotificationReceived = FlutterEventChannel(name: "eventNotificationReceived", binaryMessenger: messenger)
        eventNotificationReceived.setStreamHandler(self)
        
        let eventNotificationListenerStatus = FlutterEventChannel(name: "eventNotificationListenerStatus", binaryMessenger: messenger)
        eventNotificationListenerStatus.setStreamHandler(self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - Background Service Methods (iOS equivalent of foreground service)
    
    private func startBackgroundService(result: @escaping FlutterResult) {
        // iOS doesn't have foreground services like Android
        // Instead, we use background tasks and background modes
        // The app will continue running in background if background modes are enabled
        
        // Request background time if needed
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            // Background task expired
            if let taskID = self?.backgroundTaskID {
                UIApplication.shared.endBackgroundTask(taskID)
                self?.backgroundTaskID = .invalid
            }
        }
        
        print("AppDelegate: Background service started (background task ID: \(backgroundTaskID.rawValue))")
        result(true)
    }
    
    private func stopBackgroundService(result: @escaping FlutterResult) {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
            print("AppDelegate: Background service stopped")
        }
        result(true)
    }
    
    private func showWeatherNotification(message: String, result: @escaping FlutterResult) {
        let content = UNMutableNotificationContent()
        content.title = "Weather Updated"
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "weather_update_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Show immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("AppDelegate: Error showing weather notification: \(error)")
                result(FlutterError(code: "NOTIFICATION_ERROR", message: error.localizedDescription, details: nil))
            } else {
                print("AppDelegate: Weather notification shown successfully")
                result(true)
            }
        }
    }
    
    // MARK: - Background App Refresh
    
    override func applicationDidEnterBackground(_ application: UIApplication) {
        super.applicationDidEnterBackground(application)
        print("AppDelegate: App entered background")
    }
    
    override func applicationWillEnterForeground(_ application: UIApplication) {
        super.applicationWillEnterForeground(application)
        print("AppDelegate: App will enter foreground")
    }
}

// MARK: - FlutterStreamHandler
extension AppDelegate : FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    
       if (arguments as? String == "eventBleStatus"){
            //self.blueInstance.blueStatusSink = events
        } else if (arguments as? String == "eventBleReceive") {
            self.blueInstance.blueInfoSink = events
        } else if (arguments as? String == "eventSpeechRecognize") {
            BluetoothManager.shared.blueSpeechSink = events
        } else if (arguments as? String == "eventNotificationReceived") {
            // iOS: Set up call event sink for call notifications
            // Note: Full notification interception requires Notification Service Extension
            CallStateListener.shared.callEventSink = events
        } else if (arguments as? String == "eventNotificationListenerStatus") {
            // iOS: Always report as disabled since we don't support full notification interception
            events(false)
        } else {
            // TODO
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if (arguments as? String == "eventNotificationReceived") {
            CallStateListener.shared.callEventSink = nil
        }
        return nil
    }
}

