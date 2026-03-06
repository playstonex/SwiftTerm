//
//  NMProtocol.swift
//  NMMoshShell
//
//  Mosh protocol implementation - packet encoding/decoding.
//
//  Mosh protocol specification:
//  - UDP-based state synchronization
//  - OCB-AES128 encrypted payloads
//  - Deterministic terminal emulation
//

import Foundation

/// Mosh protocol packet types
public enum MoshPacketType: UInt8, Sendable {
    case ack = 0           // Acknowledgment
    case string = 1         // String data
    case key = 2            // Key event
    case resize = 3         // Terminal resize
    case ping = 4           // Ping/pong
}

/// Mosh protocol packet
public struct MoshPacket: Sendable {
    public let type: MoshPacketType
    public let sequenceNumber: UInt16
    public let ackNumber: UInt16
    public let payload: Data

    public init(type: MoshPacketType, sequenceNumber: UInt16, ackNumber: UInt16, payload: Data = Data()) {
        self.type = type
        self.sequenceNumber = sequenceNumber
        self.ackNumber = ackNumber
        self.payload = payload
    }

    /// Encode packet to bytes for UDP transmission
    public func encode() -> Data {
        var data = Data()
        data.append(type.rawValue)
        data.append(sequenceNumber.bytes.0)
        data.append(sequenceNumber.bytes.1)
        data.append(ackNumber.bytes.0)
        data.append(ackNumber.bytes.1)
        data.append(payload)
        return data
    }

    /// Decode packet from received bytes
    public static func decode(_ data: Data) -> MoshPacket? {
        guard data.count >= 5 else { return nil }

        let typeValue = data[0]
        guard let type = MoshPacketType(rawValue: typeValue) else { return nil }

        let seqHigh = data[1]
        let seqLow = data[2]
        let sequenceNumber = UInt16(seqHigh) << 8 + UInt16(seqLow)

        let ackHigh = data[3]
        let ackLow = data[4]
        let ackNumber = UInt16(ackHigh) << 8 + UInt16(ackLow)

        let payload = data.dropFirst(5)

        return MoshPacket(type: type, sequenceNumber: sequenceNumber, ackNumber: ackNumber, payload: payload)
    }
}

/// Mosh string data packet (terminal output)
public struct MoshStringPacket: Sendable {
    public let data: Data
    public let startRow: UInt16
    public let startCol: UInt16
    public let endRow: UInt16
    public let endCol: UInt16

    public init(data: Data, startRow: UInt16, startCol: UInt16, endRow: UInt16, endCol: UInt16) {
        self.data = data
        self.startRow = startRow
        self.startCol = startCol
        self.endRow = endRow
        self.endCol = endCol
    }

    public func encode() -> Data {
        var result = Data()
        result.append(startRow.bytes.0)
        result.append(startRow.bytes.1)
        result.append(startCol.bytes.0)
        result.append(startCol.bytes.1)
        result.append(endRow.bytes.0)
        result.append(endRow.bytes.1)
        result.append(endCol.bytes.0)
        result.append(endCol.bytes.1)
        result.append(data)
        return result
    }

    public static func decode(_ data: Data) -> MoshStringPacket? {
        guard data.count >= 8 else { return nil }

        let startRow = UInt16(data[0]) << 8 + UInt16(data[1])
        let startCol = UInt16(data[2]) << 8 + UInt16(data[3])
        let endRow = UInt16(data[4]) << 8 + UInt16(data[5])
        let endCol = UInt16(data[6]) << 8 + UInt16(data[7])
        let packetData = data.dropFirst(8)

        return MoshStringPacket(data: packetData, startRow: startRow, startCol: startCol, endRow: endRow, endCol: endCol)
    }
}

/// Mosh key event packet
public struct MoshKeyEvent: Sendable {
    public enum KeyType: UInt8, Sendable {
        case press = 0
        case release = 1
    }

    public let type: KeyType
    public let keyCode: UInt8
    public let modifiers: UInt8

    public init(type: KeyType, keyCode: UInt8, modifiers: UInt8 = 0) {
        self.type = type
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public func encode() -> Data {
        return Data([type.rawValue, keyCode, modifiers])
    }

    public static func decode(_ data: Data) -> MoshKeyEvent? {
        guard data.count >= 3 else { return nil }
        let type = KeyType(rawValue: data[0]) ?? .press
        return MoshKeyEvent(type: type, keyCode: data[1], modifiers: data[2])
    }
}

// MARK: - Helper Extensions

extension UInt16 {
    var bytes: (UInt8, UInt8) {
        let high = UInt8((self >> 8) & 0xFF)
        let low = UInt8(self & 0xFF)
        return (high, low)
    }
}
