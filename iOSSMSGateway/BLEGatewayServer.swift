//
//  BLEGatewayServer.swift
//  iOSSMSGateway
//
//  Created by Papp Zoltán on 2026. 09. 11.
//

import Foundation
import Combine
import CoreBluetooth
import UIKit
import MessageUI

public class BLEGatewayServer: NSObject, ObservableObject, CBPeripheralManagerDelegate, MFMessageComposeViewControllerDelegate {
    static let shared = BLEGatewayServer()
    @Published public var isAdvertising = false
    @Published public var pendingMessages: [BLEMessage<SendSmsPayload>] = []
    @Published public var logs: [String] = []
    @Published var statusMessage = "Inicializálás..."
    @Published var receivedData: String = ""
    @Published var keypass: String = ""

    private var peripheralManager: CBPeripheralManager!
    private var txCharacteristic: CBMutableCharacteristic?
    private let rxFramer = BLEFramer()
    private var pendingTxChunks: [Data] = []

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
            permissions: [.writeEncryptionRequired]
        )

        let txChar = CBMutableCharacteristic(
            type: BLEUUID.rxUUID, // Mac RX -> iOS TX (Notify)
            properties: [.notify, .read],
            value: nil,
            permissions: [.readEncryptionRequired]
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
        // Send server_stopping event to Mac before shutting down services
        let notifyMessage = BLEMessage<EmptyPayload>(
            type: .event,
            action: "server_stopping",
            payload: EmptyPayload()
        )
        sendResponseToMac(notifyMessage)
        
        // Short delay to allow the BLE characteristic update to go through before stopping advertising
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.peripheralManager.stopAdvertising()
            self.isAdvertising = false
            self.addLog("BLE hirdetés leállítva.")
        }
    }

    // MARK: - CBPeripheralManagerDelegate

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        sendPendingChunks()
    }

    public func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                switch result {
                case .sent:
                    self.addLog("SMS sikeresen elküldve.")
                case .cancelled:
                    self.addLog("SMS küldés megszakítva.")
                case .failed:
                    self.addLog("SMS küldés sikertelen.")
                @unknown default:
                    break
                }
            }
        }
    
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

        // keypass verification if keypass is set
        if !keypass.isEmpty && genericMessage.keypass != keypass {
            DispatchQueue.main.async {
                self.receivedData = "Biztonsági hiba:\nÉrvénytelen kulcs (keypass) érkezett."
            }
            sendResponse(id: genericMessage.id, action: "status", status: .error, code: 401, message: "Unauthorized: Invalid keypass")
            return
        }

        switch genericMessage.action {
        case "send_sms":
            do {
                let message = try BLECodec.decode(data, as: BLEMessage<SendSmsPayload>.self)
                let phone = message.payload?.phone ?? ""
                let bodyText = message.payload?.text ?? ""

                DispatchQueue.main.async {
                    self.pendingMessages.append(message)
                    self.addLog("SMS kérés érkezett BLE-n: \(phone)")

                    if MFMessageComposeViewController.canSendText() {
                        let composeVC = MFMessageComposeViewController()
                        composeVC.recipients = [phone]
                        composeVC.body = bodyText
                        composeVC.messageComposeDelegate = self

                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                            var topVC = rootVC
                            while let presented = topVC.presentedViewController {
                                topVC = presented
                            }
                            topVC.present(composeVC, animated: true)
                        }
                        self.sendResponse(id: message.id, action: "status", status: .ok, code: 200, message: "queued")
                    } else if let encodedBody = bodyText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                              let url = URL(string: "sms:\(phone)&body=\(encodedBody)"),
                              UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url, options: [:]) { success in
                            if success {
                                self.sendResponse(id: message.id, action: "status", status: .ok, code: 200, message: "Opened Messages app")
                            } else {
                                self.sendResponse(id: message.id, action: "status", status: .error, code: 500, message: "Failed to open Messages app")
                            }
                        }
                    } else {
                        self.sendResponse(id: message.id, action: "status", status: .error, code: 500, message: "SMS not supported on this device")
                    }
                }
            } catch {
                addLog("Nem sikerült dekódolni a send_sms payload-ot.")
                sendResponse(id: genericMessage.id, action: "status", status: .error, code: 400, message: "Invalid payload")
            }
        case "make_call":
            do {
                let message = try BLECodec.decode(data, as: BLEMessage<SendSmsPayload>.self)
                let phoneNumber = message.payload?.phone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "telprompt://\(phoneNumber)") {
                    DispatchQueue.main.async {
                        self.addLog("Hívás indítása BLE-n: \(message.payload?.phone)")
                        UIApplication.shared.open(url, options: [:], completionHandler: { success in
                            if success {
                                self.sendResponse(id: message.id, action: "status", status: .ok, code: 200, message: "Dialing")
                            } else {
                                self.sendResponse(id: message.id, action: "status", status: .error, code: 500, message: "Failed to open telprompt")
                            }
                        })
                    }
                } else {
                    sendResponse(id: message.id, action: "status", status: .error, code: 400, message: "Invalid phone number format")
                }
            } catch {
                addLog("Nem sikerült dekódolni a make_call payload-ot.")
                sendResponse(id: genericMessage.id, action: "status", status: .error, code: 400, message: "Invalid payload")
            }
        case "get_contacts":
            addLog("Kontaktok lekérése kérés érkezett.")
            ContactHelper.fetchContacts { contacts in
                let contactList = ContactListPayload(contacts: contacts)
                let response = BLEMessage<ContactListPayload>(
                    id: genericMessage.id,
                    type: .response,
                    action: "contacts_list",
                    payload: contactList
                )
                self.sendResponseToMac(response)
            }
        default:
            addLog("Ismeretlen parancs: \(genericMessage.action)")
            sendResponse(id: genericMessage.id, action: "status", status: .error, code: 404, message: "Unknown action")
        }
    }

    public func sendResponseToMac<T: Codable>(_ message: BLEMessage<T>) {
        do {
            let data = try BLECodec.encode(message)
            let chunks = BLEFramer().frame(data)
            pendingTxChunks.append(contentsOf: chunks)
            sendPendingChunks()
        } catch {
            addLog("Sikertelen kódolás a válasz küldésekor: \(error.localizedDescription)")
        }
    }

    private func sendPendingChunks() {
        guard let txChar = txCharacteristic else { return }
        
        while !pendingTxChunks.isEmpty {
            let chunk = pendingTxChunks[0]
            let success = peripheralManager.updateValue(chunk, for: txChar, onSubscribedCentrals: nil)
            
            if success {
                pendingTxChunks.removeFirst()
            } else {
                // A puffer megtelt, várunk a peripheralManagerIsReady(toUpdateSubscribers:) hívásra
                break
            }
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

