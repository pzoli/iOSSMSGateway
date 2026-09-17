//
// BLEFramer.swift
// iOSSMSGateway
//
// Created by Papp Zoltán on 2026. 09. 11.
//

import Foundation

public class BLEFramer {

    private var buffer = Data()

    public init() {}

    public func append(
        _ data: Data
    ) -> [Data] {
        buffer.append(data)
        var result: [Data] = []

        while let index = buffer.firstIndex(of: 0x0A) {
            let packet = buffer.prefix(upTo: index)
            result.append(Data(packet))
            buffer.removeSubrange(...index)
        }

        return result
    }

    /// Kimenő üzenet felkészítése: soremelés (0x0A) hozzáfűzése és darabolás (chunking)
    /// - Parameters:
    ///   - data: A küldendő adatok
    ///   - maxChunkSize: A maximális darabméret bájtban (pl. `central.maximumUpdateValueLength`)
    /// - Returns: A darabolt adatcsomagok tömbje
    public func frame(_ data: Data, maxChunkSize: Int = 180) -> [Data] {
        guard maxChunkSize > 0 else { return [] }

        var framedData = data
        if framedData.last != 0x0A {
            framedData.append(0x0A) // 0x0A (LF) lezáró bájt hozzáadása
        }
        
        var chunks: [Data] = []
        var offset = 0
        while offset < framedData.count {
            let chunkSize = min(maxChunkSize, framedData.count - offset)
            let chunk = framedData.subdata(in: offset..<(offset + chunkSize))
            chunks.append(chunk)
            offset += chunkSize
        }
        return chunks
    }
}
