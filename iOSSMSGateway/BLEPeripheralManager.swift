import CoreBluetooth

class BLEPeripheralManager: NSObject, CBPeripheralManagerDelegate {
    private var peripheralManager: CBPeripheralManager!
    private var pendingChunks: [Data] = []
    private var characteristic: CBMutableCharacteristic!

    public func sendData(_ data: Data, framer: BLEFramer) {
        // Üzenet darabolása
        self.pendingChunks = framer.frame(data, maxChunkSize: 180)
        sendNextChunk()
    }

    private func sendNextChunk() {
        while !pendingChunks.isEmpty {
            let chunk = pendingChunks[0]
            
            // Megpróbáljuk elküldeni a következő chunkot
            let success = peripheralManager.updateValue(
                chunk,
                for: characteristic,
                onSubscribedCentrals: nil
            )
            
            if success {
                // Ha sikerült, eltávolítjuk a sorból
                pendingChunks.removeFirst()
            } else {
                // Ha false-t kaptunk, a BLE puffer megtelt!
                // Megállunk, és megvárjuk a peripheralManagerIsReady hívást.
                print("BLE adási puffer megtelt, várakozás...")
                break
            }
        }
    }

    // CBPeripheralManagerDelegate kötelező metódusa
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // Állapotváltozások kezelése
    }

    // Ezt a CBPeripheralManagerDelegate metódust kell megvalósítani:
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Amint a BLE puffer újra szabad, folytatjuk a küldést
        sendNextChunk()
    }
}
