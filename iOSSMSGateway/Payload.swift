//
// Payload.swift
// iOSSMSGateway
//
// Created by Papp Zoltán on 2026. 09. 11.
//

import Foundation

public protocol Payload: Codable {
 
}

public struct StatusPayload: Codable, Payload {
    public let code: Int
    public let message: String
    
    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - SMS
public struct SendSmsPayload: Codable, Payload {
    public let phone: String
    public let text: String

    public init(phone: String, text: String) {
        self.phone = phone
        self.text = text
    }
}

public struct SmsReceivedPayload: Codable, Payload {
    public var id: UUID = UUID()
    public let from: String
    public let text: String
    public var name: String?
    
    public init(id: UUID = UUID(), from: String, text: String, name: String? = nil) {
        self.id = id
        self.from = from
        self.text = text
        self.name = name
    }
    
    enum CodingKeys: String, CodingKey {
        case from
        case text
    }
}

// MARK: - Contacts
public struct Contact: Codable, Identifiable {
    public var id: UUID = UUID()
    public let name: String
    public let numbers: [String]
    
    public init(id: UUID = UUID(), name: String, numbers: [String]) {
        self.id = id
        self.name = name
        self.numbers = numbers
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case numbers
    }
}

public struct ContactListPayload: Codable, Payload {
    public let contacts: [Contact]
    
    public init(contacts: [Contact]) {
        self.contacts = contacts
    }
}


// MARK: - Calls
public enum CallStatus: String, Codable {
    case ringing = "RINGING"
    case offhook = "OFFHOOK"
    case idle = "IDLE"
}

public enum CallAction: String, Codable {
    case dial = "DIAL"
    case answer = "ANSWER"
    case reject = "REJECT"
    case hangup = "HANGUP"
}

public struct SendCallPayload: Codable, Payload {
    public let action: CallAction
    public let phoneNumber: String?
    
    public init(action: CallAction, phoneNumber: String?) {
        self.action = action
        self.phoneNumber = phoneNumber
    }
}

public struct CallStatusPayload: Codable, Payload {
    public let status: CallStatus
    public let phoneNumber: String?
    
    public init(status: CallStatus, phoneNumber: String?) {
        self.status = status
        self.phoneNumber = phoneNumber
    }
}

public struct EmptyPayload: Codable, Payload {
    public init() {}
}
