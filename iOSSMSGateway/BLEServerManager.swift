//
//  BLEServerManager.swift
//  iOSSMSGateway
//
//  Created by Papp Zoltán on 2026. 09. 11.
//

import Foundation
import CoreBluetooth
import Combine

class BLEServerManager: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    @Published var isAdvertising = false
    @Published var statusMessage = "Inicializálás..."
    @Published var receivedData: String = ""

    private var peripheralManager: CBPeripheralManager!
    private var txCharacteristic: CBMutableCharacteristic?
    private let rxFramer = BLEFramer()

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    // MARK: - Szerver Vezérlés
    func startAdvertising() {
        guard peripheralManager.state == .poweredOn else {
            statusMessage = "A Bluetooth nincs bekapcsolva."
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
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BLEUUID.serviceUUID],
            CBAdvertisementDataLocalNameKey: "iOS SMS Gateway"
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
        statusMessage = "Hirdetés indítva..."
    }

    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
        statusMessage = "Hirdetés leállítva."
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            statusMessage = "Bluetooth bekapcsolva. Kész a hirdetésre."
            startAdvertising()
        case .poweredOff:
            statusMessage = "Bluetooth kikapcsolva."
            isAdvertising = false
        case .unauthorized:
            statusMessage = "Nincs engedély a Bluetooth használatára."
        case .unsupported:
            statusMessage = "A BLE nem támogatott ezen az eszközön."
        default:
            statusMessage = "Ismeretlen állapot."
        }
    }

    // Kliens olvasási kérésének kezelése
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == BLEUUID.rxUUID {
            let responseString = "SMS Gateway Active"
            request.value = responseString.data(using: .utf8)
            peripheralManager.respond(to: request, withResult: .success)
        } else {
            peripheralManager.respond(to: request, withResult: .attributeNotFound)
        }
    }

    // Kliens írási kérésének (küldött adat) kezelése
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == BLEUUID.txUUID, let value = request.value {
                let packets = rxFramer.append(value)
                for packet in packets {
                    parsePacket(packet)
                }
            }
            peripheralManager.respond(to: request, withResult: .success)
        }
    }

    private func parsePacket(_ data: Data) {
        guard let genericMessage = try? BLECodec.decode(data, as: BLEMessage<EmptyPayload>.self) else {
            DispatchQueue.main.async {
                self.receivedData = "Érvénytelen parancs formátum (nem BLEMessage)."
            }
            return
        }

        switch genericMessage.action {
        case "send_sms":
            do {
                let message = try BLECodec.decode(data, as: BLEMessage<SendSmsPayload>.self)
                DispatchQueue.main.async {
                    self.receivedData = "SMS küldés kérés:\nCímzett: \(message.payload.phone)\nSzöveg: \(message.payload.text)"
                }
                sendResponse(id: message.id, action: "status", status: .ok, code: 200, message: "queued")
            } catch {
                DispatchQueue.main.async {
                    self.receivedData = "Hiba a send_sms payload dekódolásakor."
                }
                sendResponse(id: genericMessage.id, action: "status", status: .error, code: 400, message: "Invalid payload")
            }
        case "get_contacts":
            DispatchQueue.main.async {
                self.receivedData = "Kontakt lekérés kérés érkezett."
            }
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
            DispatchQueue.main.async {
                self.receivedData = "Ismeretlen parancs: \(genericMessage.action)"
            }
            sendResponse(id: genericMessage.id, action: "status", status: .error, code: 404, message: "Unknown action")
        }
    }

    func sendResponseToMac<T: Codable>(_ message: BLEMessage<T>) {
        guard let txChar = txCharacteristic else { return }
        do {
            let data = try BLECodec.encode(message)
            let chunks = BLEFramer().frame(data)
            for chunk in chunks {
                peripheralManager.updateValue(chunk, for: txChar, onSubscribedCentrals: nil)
            }
        } catch {
            print("Sikertelen kódolás a válasz küldésekor: \(error.localizedDescription)")
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
}
