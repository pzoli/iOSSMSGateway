//
// BLEUUID.swift
// iOSSMSGateway
//
// Created by Papp Zoltán on 2026. 09. 11.
//

import Foundation
import CoreBluetooth

public enum BLEUUID {
    /// Szerver SERVICE_UUID
    public static let serviceUUID = CBUUID(string: "7A100000-1234-5678-1234-000000000001")
    
    /// Szerver EVENT_UUID (Mac RX: innen fogadjuk a válaszokat/eseményeket Notify-al)
    public static let rxUUID = CBUUID(string: "7A100002-1234-5678-1234-000000000001")
    
    /// Szerver COMMAND_UUID (Mac TX: ide írjuk a parancsokat)
    public static let txUUID = CBUUID(string: "7A100001-1234-5678-1234-000000000001")
}
