//
//  CallStateListener.swift
//  Runner
//
//  Created for iOS call state detection
//

import Foundation
import CallKit
import Contacts

class CallStateListener: NSObject {
    static let shared = CallStateListener()
    
    private var callObserver: CXCallObserver?
    private var isListening = false
    private var lastCallUUID: UUID?
    private var callerNameCache: [String: String] = [:]
    
    // Event sink for sending call notifications to Flutter
    var callEventSink: FlutterEventSink?
    
    override init() {
        super.init()
        callObserver = CXCallObserver()
    }
    
    func startListening() {
        if isListening {
            print("CallStateListener: Already listening for call state changes")
            return
        }
        
        guard let observer = callObserver else {
            print("CallStateListener: CXCallObserver not available")
            return
        }
        
        // Set delegate to receive call updates
        observer.setDelegate(self, queue: nil)
        isListening = true
        print("CallStateListener: Started listening for call state changes")
    }
    
    func stopListening() {
        if !isListening {
            return
        }
        
        callObserver?.setDelegate(nil, queue: nil)
        isListening = false
        print("CallStateListener: Stopped listening for call state changes")
    }
    
    func getCallerDisplayName(phoneNumber: String) -> String {
        // Check cache first
        if let cachedName = callerNameCache[phoneNumber] {
            return cachedName
        }
        
        // Try to resolve from contacts
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        
        do {
            let request = CNContactFetchRequest(keysToFetch: keys)
            var foundName: String?
            
            try store.enumerateContacts(with: request) { contact, _ in
                for phone in contact.phoneNumbers {
                    let number = phone.value.stringValue
                    let normalizedNumber = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    let normalizedInput = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    
                    // Check if numbers match (last 10 digits for US numbers)
                    if normalizedNumber.hasSuffix(normalizedInput) || normalizedInput.hasSuffix(normalizedNumber) {
                        let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                        if !fullName.isEmpty {
                            foundName = fullName
                            return false // Stop enumeration
                        }
                    }
                }
                return true // Continue enumeration
            }
            
            if let name = foundName {
                callerNameCache[phoneNumber] = name
                return name
            }
        } catch {
            print("CallStateListener: Error resolving caller name: \(error)")
        }
        
        // If not found, return phone number and cache it
        callerNameCache[phoneNumber] = phoneNumber
        return phoneNumber
    }
    
    func clearCache() {
        callerNameCache.removeAll()
    }
    
    private func handleIncomingCall(call: CXCall) {
        // Note: iOS doesn't provide phone number directly from CXCall
        // We'll send a generic incoming call notification
        // The actual caller info might come from notification service extension
        
        let callNotification: [String: Any] = [
            "msg_id": Int(Date().timeIntervalSince1970) & 0x7FFFFFFF,
            "app_identifier": "com.apple.mobilephone",
            "title": "Incoming Call",
            "subtitle": "",
            "message": "Incoming call",
            "time_s": Int(Date().timeIntervalSince1970),
            "display_name": "Phone"
        ]
        
        print("CallStateListener: Sending call notification to Flutter")
        
        // Send to Flutter via event channel
        if let eventSink = callEventSink {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: callNotification)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    eventSink(jsonString)
                }
            } catch {
                print("CallStateListener: Error serializing call notification: \(error)")
            }
        }
    }
}

extension CallStateListener: CXCallObserverDelegate {
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        print("CallStateListener: Call state changed - hasConnected: \(call.hasConnected), hasEnded: \(call.hasEnded), isOutgoing: \(call.isOutgoing)")
        
        if !call.hasEnded && !call.hasConnected && !call.isOutgoing {
            // Incoming call is ringing
            if call.uuid != lastCallUUID {
                lastCallUUID = call.uuid
                handleIncomingCall(call: call)
            }
        } else if call.hasEnded {
            // Call ended
            if call.uuid == lastCallUUID {
                lastCallUUID = nil
                print("CallStateListener: Call ended")
            }
        } else if call.hasConnected {
            // Call answered
            print("CallStateListener: Call answered")
        }
    }
}

