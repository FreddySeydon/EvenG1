//
//  BluetoothManager.swift
//  Runner
//
//  Created by Hawk on 2024/10/23.
//

import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var blueInstance = BluetoothManager.shared

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
 
        GeneratedPluginRegistrant.register(with: self)
        let controller = window?.rootViewController as! FlutterViewController
        let messenger : FlutterBinaryMessenger = window?.rootViewController as! FlutterBinaryMessenger
        let channel = FlutterMethodChannel(name: "method.bluetooth", binaryMessenger: controller.binaryMessenger)
        
        blueInstance = BluetoothManager(channel: channel)

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
            // iOS: Notification interception not supported without Notification Service Extension
            // Events will not be sent
        } else if (arguments as? String == "eventNotificationListenerStatus") {
            // iOS: Always report as disabled since we don't support it
            events(false)
        } else {
            // TODO
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}

