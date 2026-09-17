//
// BLEMessage.swift
// iOSSMSGateway
//
// Created by Papp Zoltán on 2026. 09. 11.
//

import Foundation

public enum MessageType: String, Codable {
    case request
    case response
    case event
}

public enum Status: String, Codable {
    case ok
    case error
}

public struct BLEError: Codable {
    public let code: String
    public let message: String
    
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct BLEMessage<T: Codable>: Codable {
    public let id: Int64
    public let type: MessageType
    public let action: String
    public let payload: T?
    public let status: Status?
    public let error: BLEError?
    public let keypass: String?

    public init(id: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
                type: MessageType,
                action: String,
                payload: T,
                status: Status? = nil,
                error: BLEError? = nil,
                keypass: String? = nil) {
        self.id = id
        self.type = type
        self.action = action
        self.payload = payload
        self.status = status
        self.error = error
        self.keypass = keypass
    }
}
