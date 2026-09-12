//
//  BLEGatewayServer.swift
//  iOSSMSGateway
//
//  Created by Papp Zoltán on 2026. 09. 11.
//

import Foundation
import Combine
import CoreBluetooth

public class BLEGatewayServer: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    @Published public var isAdvertising = false
    @Published public var pendingMessages: [BLEMessage<SendSmsPayload>] = []
    @Published public var logs: [String] = []

    private var peripheralManager: CBPeripheralManager!
    private var txCharacteristic: CBMutableCharacteristic?
    private let rxFramer = BLEFramer()

    public override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    public func startAdvertising() {
        guard peripheralManager.state == .poweredOn else {
            addLog("A Bluetooth nincs bekapcsolva.")
            return
        }

        let rxChar = CBMutableCharacteristic(
            type: BLEUUID.txUUID, // Mac TX -> iOS RX (Write)
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        let txChar = CBMutableCharacteristic(
            type: BLEUUID.rxUUID, // Mac RX -> iOS TX (Notify)
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        self.txCharacteristic = txChar

        let service = CBMutableService(type: BLEUUID.serviceUUID, primary: true)
        service.characteristics = [rxChar, txChar]
        peripheralManager.add(service)

        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEUUID.serviceUUID],
            CBAdvertisementDataLocalNameKey: "iOS SMS Gateway"
        ])
        
        isAdvertising = true
        addLog("BLE hirdetés elindítva.")
    }

    public func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
        addLog("BLE hirdetés leállítva.")
    }

    // MARK: - CBPeripheralManagerDelegate

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            addLog("Bluetooth készen áll.")
            startAdvertising()
        case .poweredOff:
            addLog("Bluetooth kikapcsolva.")
            isAdvertising = false
        case .unauthorized:
            addLog("Bluetooth használata nem engedélyezett.")
        default:
            break
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == BLEUUID.txUUID, let data = request.value {
                let packets = rxFramer.append(data)
                for packet in packets {
                    parsePacket(packet)
                }
                peripheralManager.respond(to: request, withResult: .success)
            } else {
                peripheralManager.respond(to: request, withResult: .attributeNotFound)
            }
        }
    }

    private func parsePacket(_ data: Data) {
        // First try to parse generic message to inspect the action
        guard let genericMessage = try? BLECodec.decode(data, as: BLEMessage<EmptyPayload>.self) else {
            addLog("Érvénytelen parancs formátum (nem BLEMessage).")
            return
        }

        switch genericMessage.action {
        case "send_sms":
            do {
                let message = try BLECodec.decode(data, as: BLEMessage<SendSmsPayload>.self)
                DispatchQueue.main.async {
                    self.pendingMessages.append(message)
                    self.addLog("SMS kérés érkezett BLE-n: \(message.payload.phone)")
                }
                sendResponse(id: message.id, action: "status", status: .ok, code: 200, message: "queued")
            } catch {
                addLog("Nem sikerült dekódolni a send_sms payload-ot.")
                sendResponse(id: genericMessage.id, action: "status", status: .error, code: 400, message: "Invalid payload")
            }
        case "get_contacts":
            addLog("Kontaktok lekérése kérés érkezett.")
            let contactList = ContactListPayload(contacts: [
                Contact(name: "Papp Zoltán", numbers: ["+36301234567"]),
                Contact(name: "Teszt Elek", numbers: ["+36209876543"])
            ])
            let response = BLEMessage<ContactListPayload>(
                id: genericMessage.id,
                type: .response,
                action: "contacts",
                payload: contactList
            )
            sendResponseToMac(response)
        default:
            addLog("Ismeretlen parancs: \(genericMessage.action)")
            sendResponse(id: genericMessage.id, action: "status", status: .error, code: 404, message: "Unknown action")
        }
    }

    public func sendResponseToMac<T: Codable>(_ message: BLEMessage<T>) {
        guard let txChar = txCharacteristic else { return }
        do {
            let data = try BLECodec.encode(message)
            let chunks = BLEFramer().frame(data)
            for chunk in chunks {
                peripheralManager.updateValue(chunk, for: txChar, onSubscribedCentrals: nil)
            }
        } catch {
            addLog("Sikertelen kódolás a válasz küldésekor: \(error.localizedDescription)")
        }
    }

    private func sendResponse(id: Int64, action: String, status: Status, code: Int, message: String) {
        let payload = StatusPayload(code: code, message: message)
        let errorPayload: BLEError? = (status == .error) ? BLEError(code: String(code), message: message) : nil
        let response = BLEMessage<StatusPayload>(
            id: id,
            type: .response,
            action: action,
            payload: payload,
            status: status,
            error: errorPayload
        )
        sendResponseToMac(response)
    }

    private func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        DispatchQueue.main.async {
            self.logs.append("[\(timestamp)] \(message)")
        }
    }
}
