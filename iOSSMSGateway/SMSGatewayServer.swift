//
//  SMSGatewayServer.swift
//  iOSSMSGateway
//
//  Created by Papp Zoltán on 2026. 09. 11.
//

import Foundation
import Combine
import CoreBluetooth

public class SMSGatewayServer: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    @Published public var isRunning = false
    @Published public var pendingMessages: [BLEMessage<SendSmsPayload>] = []
    @Published public var logs: [String] = []

    private var peripheralManager: CBPeripheralManager?
    private var txCharacteristic: CBMutableCharacteristic?
    private let rxFramer = BLEFramer()

    public override init() {
        super.init()
    }

    public func startServer() {
        startBluetoothServer()
    }

    private func startBluetoothServer() {
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        } else if peripheralManager?.state == .poweredOn {
            setupBluetoothService()
        }
    }

    public func stopServer() {
        if let peripheralManager = peripheralManager, peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
            peripheralManager.removeAllServices()
        }

        DispatchQueue.main.async {
            self.isRunning = false
            self.addLog("Bluetooth szolgáltatás leállítva.")
        }
    }

    private func setupBluetoothService() {
        guard let peripheralManager = peripheralManager, peripheralManager.state == .poweredOn else { return }

        peripheralManager.removeAllServices()

        // Mac TX -> iOS RX (Write)
        let rxChar = CBMutableCharacteristic(
            type: BLEUUID.txUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        // Mac RX -> iOS TX (Notify / Read)
        let txChar = CBMutableCharacteristic(
            type: BLEUUID.rxUUID,
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

        DispatchQueue.main.async {
            self.isRunning = true
            self.addLog("Bluetooth periféria hirdetés elindítva.")
        }
    }

    public func addLog(_ message: String) {
        DispatchQueue.main.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.logs.append("[\(timestamp)] \(message)")
        }
    }

    // MARK: - CBPeripheralManagerDelegate

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        DispatchQueue.main.async {
            switch peripheral.state {
            case .poweredOn:
                self.addLog("Bluetooth bekapcsolva.")
                self.setupBluetoothService()
            case .poweredOff:
                self.isRunning = false
                self.addLog("Bluetooth kikapcsolva.")
            case .unauthorized:
                self.isRunning = false
                self.addLog("Bluetooth használata nem engedélyezett.")
            case .unsupported:
                self.isRunning = false
                self.addLog("Az eszköz nem támogatja a Bluetooth-t.")
            default:
                break
            }
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == BLEUUID.txUUID, let data = request.value {
                let packets = rxFramer.append(data)
                for packet in packets {
                    parsePacket(packet)
                }
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .attributeNotFound)
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
                    self.addLog("SMS kérés érkezett: \(message.payload.phone)")
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
        guard let txChar = txCharacteristic, let peripheralManager = peripheralManager else { return }
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
}
