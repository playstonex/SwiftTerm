//
//  NMProtobuf.swift
//  NMMoshShell
//
//  Mosh protocol buffer message definitions.
//  Based on mosh/src/protobufs/*.proto
//

import Foundation

// MARK: - UserInput Protocol (Client -> Server)

/// UserMessage from client to server containing user input instructions
public struct UserMessage: Sendable {
    public var instructions: [UserInstruction]

    public init(instructions: [UserInstruction] = []) {
        self.instructions = instructions
    }
}

/// Instruction wrapper for user input
public struct UserInstruction: Sendable {
    public var keystroke: Keystroke?
    public var resize: ResizeMessage?

    public init(keystroke: Keystroke? = nil, resize: ResizeMessage? = nil) {
        self.keystroke = keystroke
        self.resize = resize
    }
}

/// Keystroke data from user
public struct Keystroke: Sendable {
    public var keys: Data

    public init(keys: Data = Data()) {
        self.keys = keys
    }

    public init(string: String) {
        self.keys = string.data(using: .utf8) ?? Data()
    }
}

/// Terminal resize message
public struct ResizeMessage: Sendable {
    public var width: Int32
    public var height: Int32

    public init(width: Int32 = 80, height: Int32 = 24) {
        self.width = width
        self.height = height
    }
}

// MARK: - HostInput Protocol (Server -> Client)

/// HostMessage from server to client containing terminal output
public struct HostMessage: Sendable {
    public var instructions: [HostInstruction]

    public init(instructions: [HostInstruction] = []) {
        self.instructions = instructions
    }
}

/// Instruction wrapper for host output
public struct HostInstruction: Sendable {
    public var hostbytes: HostBytes?
    public var resize: ResizeMessage?
    public var echoack: EchoAck?

    public init(hostbytes: HostBytes? = nil, resize: ResizeMessage? = nil, echoack: EchoAck? = nil) {
        self.hostbytes = hostbytes
        self.resize = resize
        self.echoack = echoack
    }
}

/// Host output bytes (terminal display data)
public struct HostBytes: Sendable {
    public var hoststring: Data

    public init(hoststring: Data = Data()) {
        self.hoststring = hoststring
    }

    public init(string: String) {
        self.hoststring = string.data(using: .utf8) ?? Data()
    }
}

/// Echo acknowledgment
public struct EchoAck: Sendable {
    public var echoAckNum: UInt64

    public init(echoAckNum: UInt64 = 0) {
        self.echoAckNum = echoAckNum
    }
}

// MARK: - Transport Protocol

/// Transport instruction for state synchronization
public struct TransportInstruction: Sendable {
    public var protocolVersion: UInt32
    public var oldNum: UInt64
    public var newNum: UInt64
    public var ackNum: UInt64
    public var throwawayNum: UInt64
    public var diff: Data
    public var chaff: Data

    public init(
        protocolVersion: UInt32 = 1,
        oldNum: UInt64 = 0,
        newNum: UInt64 = 0,
        ackNum: UInt64 = 0,
        throwawayNum: UInt64 = 0,
        diff: Data = Data(),
        chaff: Data = Data()
    ) {
        self.protocolVersion = protocolVersion
        self.oldNum = oldNum
        self.newNum = newNum
        self.ackNum = ackNum
        self.throwawayNum = throwawayNum
        self.diff = diff
        self.chaff = chaff
    }
}

// MARK: - Protobuf Encoding/Decoding

extension UserMessage {
    /// Encode to protobuf format
    public func encode() -> Data {
        var data = Data()

        // Field 1: repeated Instruction
        for instruction in instructions {
            let instructionData = instruction.encode()
            // Field tag: (field_number << 3) | wire_type = (1 << 3) | 2 = 10 (length-delimited)
            data.append(10)
            data.appendVarInt(UInt64(instructionData.count))
            data.append(instructionData)
        }

        return data
    }

    /// Decode from protobuf format
    public static func decode(from data: Data) -> UserMessage? {
        var instructions: [UserInstruction] = []
        var index = 0

        while index < data.count {
            guard index < data.count else { break }
            let tag = data[index]
            index += 1

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            guard fieldNumber == 1 && wireType == 2 else {
                // Skip unknown field
                if wireType == 0 {
                    while index < data.count && data[index] >= 0x80 { index += 1 }
                    index += 1
                } else if wireType == 2 {
                    let (_, len) = data.readVarInt(at: index)
                    index += len
                    let (length, len2) = data.readVarInt(at: index)
                    index += len2 + Int(length)
                }
                continue
            }

            let (length, len) = data.readVarInt(at: index)
            index += len

            let instructionData = data.subdata(in: index..<index+Int(length))
            index += Int(length)

            if let instruction = UserInstruction.decode(from: instructionData) {
                instructions.append(instruction)
            }
        }

        return UserMessage(instructions: instructions)
    }
}

extension UserInstruction {
    public func encode() -> Data {
        var data = Data()

        // Field 2: keystroke (optional)
        if let keystroke = keystroke {
            let keystrokeData = keystroke.encode()
            data.append(18) // (2 << 3) | 2 = 18
            data.appendVarInt(UInt64(keystrokeData.count))
            data.append(keystrokeData)
        }

        // Field 3: resize (optional)
        if let resize = resize {
            let resizeData = resize.encode()
            data.append(26) // (3 << 3) | 2 = 26
            data.appendVarInt(UInt64(resizeData.count))
            data.append(resizeData)
        }

        return data
    }

    public static func decode(from data: Data) -> UserInstruction? {
        var keystroke: Keystroke?
        var resize: ResizeMessage?
        var index = 0

        while index < data.count {
            guard index < data.count else { break }
            let tag = data[index]
            index += 1

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            if fieldNumber == 2 && wireType == 2 {
                // keystroke
                let (length, len) = data.readVarInt(at: index)
                index += len
                let keystrokeData = data.subdata(in: index..<index+Int(length))
                index += Int(length)
                keystroke = Keystroke.decode(from: keystrokeData)
            } else if fieldNumber == 3 && wireType == 2 {
                // resize
                let (length, len) = data.readVarInt(at: index)
                index += len
                let resizeData = data.subdata(in: index..<index+Int(length))
                index += Int(length)
                resize = ResizeMessage.decode(from: resizeData)
            } else {
                // Skip unknown field
                if wireType == 0 {
                    while index < data.count && data[index] >= 0x80 { index += 1 }
                    index += 1
                } else if wireType == 2 {
                    let (_, len) = data.readVarInt(at: index)
                    index += len
                    let (length, len2) = data.readVarInt(at: index)
                    index += len2 + Int(length)
                }
            }
        }

        return UserInstruction(keystroke: keystroke, resize: resize)
    }
}

extension Keystroke {
    public func encode() -> Data {
        var data = Data()

        // Field 4: keys (bytes)
        if !keys.isEmpty {
            data.append(34) // (4 << 3) | 2 = 34
            data.appendVarInt(UInt64(keys.count))
            data.append(keys)
        }

        return data
    }

    public static func decode(from data: Data) -> Keystroke? {
        var keys = Data()
        var index = 0

        while index < data.count {
            guard index < data.count else { break }
            let tag = data[index]
            index += 1

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            if fieldNumber == 4 && wireType == 2 {
                let (length, len) = data.readVarInt(at: index)
                index += len
                keys = data.subdata(in: index..<index+Int(length))
                index += Int(length)
            } else {
                // Skip unknown field
                if wireType == 0 {
                    while index < data.count && data[index] >= 0x80 { index += 1 }
                    index += 1
                } else if wireType == 2 {
                    let (_, len) = data.readVarInt(at: index)
                    index += len
                    let (length, len2) = data.readVarInt(at: index)
                    index += len2 + Int(length)
                }
            }
        }

        return Keystroke(keys: keys)
    }
}

extension ResizeMessage {
    public func encode() -> Data {
        var data = Data()

        // Field 5: width (int32, varint)
        if width != 0 {
            data.append(40) // (5 << 3) | 0 = 40
            data.appendVarInt(UInt64(bitPattern: Int64(width)))
        }

        // Field 6: height (int32, varint)
        if height != 0 {
            data.append(48) // (6 << 3) | 0 = 48
            data.appendVarInt(UInt64(bitPattern: Int64(height)))
        }

        return data
    }

    public static func decode(from data: Data) -> ResizeMessage? {
        var width: Int32 = 0
        var height: Int32 = 0
        var index = 0

        while index < data.count {
            guard index < data.count else { break }
            let tag = data[index]
            index += 1

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            if fieldNumber == 5 && wireType == 0 {
                let (value, len) = data.readVarInt(at: index)
                index += len
                width = Int32(bitPattern: UInt32(truncatingIfNeeded: value))
            } else if fieldNumber == 6 && wireType == 0 {
                let (value, len) = data.readVarInt(at: index)
                index += len
                height = Int32(bitPattern: UInt32(truncatingIfNeeded: value))
            } else {
                // Skip unknown field
                if wireType == 0 {
                    while index < data.count && data[index] >= 0x80 { index += 1 }
                    index += 1
                } else if wireType == 2 {
                    let (_, len) = data.readVarInt(at: index)
                    index += len
                    let (length, len2) = data.readVarInt(at: index)
                    index += len2 + Int(length)
                }
            }
        }

        return ResizeMessage(width: width, height: height)
    }
}

extension HostMessage {
    public func encode() -> Data {
        var data = Data()

        for instruction in instructions {
            let instructionData = instruction.encode()
            data.append(10)
            data.appendVarInt(UInt64(instructionData.count))
            data.append(instructionData)
        }

        return data
    }

    public static func decode(from data: Data) -> HostMessage? {
        var instructions: [HostInstruction] = []
        var index = 0

        while index < data.count {
            guard index < data.count else { break }
            let tag = data[index]
            index += 1

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            guard fieldNumber == 1 && wireType == 2 else {
                // Skip unknown field
                if wireType == 0 {
                    while index < data.count && data[index] >= 0x80 { index += 1 }
                    index += 1
                } else if wireType == 2 {
                    let (_, len) = data.readVarInt(at: index)
                    index += len
                    let (length, len2) = data.readVarInt(at: index)
                    index += len2 + Int(length)
                }
                continue
            }

            let (length, len) = data.readVarInt(at: index)
            index += len

            let instructionData = data.subdata(in: index..<index+Int(length))
            index += Int(length)

            if let instruction = HostInstruction.decode(from: instructionData) {
                instructions.append(instruction)
            }
        }

        return HostMessage(instructions: instructions)
    }
}

extension HostInstruction {
    public func encode() -> Data {
        var data = Data()

        if let hostbytes = hostbytes {
            let hostbytesData = hostbytes.encode()
            data.append(18) // (2 << 3) | 2 = 18
            data.appendVarInt(UInt64(hostbytesData.count))
            data.append(hostbytesData)
        }

        if let resize = resize {
            let resizeData = resize.encode()
            data.append(26) // (3 << 3) | 2 = 26
            data.appendVarInt(UInt64(resizeData.count))
            data.append(resizeData)
        }

        if let echoack = echoack {
            let echoackData = echoack.encode()
            data.append(58) // (7 << 3) | 2 = 58
            data.appendVarInt(UInt64(echoackData.count))
            data.append(echoackData)
        }

        return data
    }

    public static func decode(from data: Data) -> HostInstruction? {
        var hostbytes: HostBytes?
        var resize: ResizeMessage?
        var echoack: EchoAck?
        var index = 0

        while index < data.count {
            guard index < data.count else { break }
            let tag = data[index]
            index += 1

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            if fieldNumber == 2 && wireType == 2 {
                let (length, len) = data.readVarInt(at: index)
                index += len
                let hostbytesData = data.subdata(in: index..<index+Int(length))
                index += Int(length)
                hostbytes = HostBytes.decode(from: hostbytesData)
            } else if fieldNumber == 3 && wireType == 2 {
                let (length, len) = data.readVarInt(at: index)
                index += len
                let resizeData = data.subdata(in: index..<index+Int(length))
                index += Int(length)
                resize = ResizeMessage.decode(from: resizeData)
            } else if fieldNumber == 7 && wireType == 2 {
                let (length, len) = data.readVarInt(at: index)
                index += len
                let echoackData = data.subdata(in: index..<index+Int(length))
                index += Int(length)
                echoack = EchoAck.decode(from: echoackData)
            } else {
                // Skip unknown field
                if wireType == 0 {
                    while index < data.count && data[index] >= 0x80 { index += 1 }
                    index += 1
                } else if wireType == 2 {
                    let (_, len) = data.readVarInt(at: index)
                    index += len
                    let (length, len2) = data.readVarInt(at: index)
                    index += len2 + Int(length)
                }
            }
        }

        return HostInstruction(hostbytes: hostbytes, resize: resize, echoack: echoack)
    }
}

extension HostBytes {
    public func encode() -> Data {
        var data = Data()

        if !hoststring.isEmpty {
            data.append(34) // (4 << 3) | 2 = 34
            data.appendVarInt(UInt64(hoststring.count))
            data.append(hoststring)
        }

        return data
    }

    public static func decode(from data: Data) -> HostBytes? {
        var hoststring = Data()
        var index = 0

        while index < data.count {
            guard index < data.count else { break }
            let tag = data[index]
            index += 1

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            if fieldNumber == 4 && wireType == 2 {
                let (length, len) = data.readVarInt(at: index)
                index += len
                hoststring = data.subdata(in: index..<index+Int(length))
                index += Int(length)
            } else {
                // Skip unknown field
                if wireType == 0 {
                    while index < data.count && data[index] >= 0x80 { index += 1 }
                    index += 1
                } else if wireType == 2 {
                    let (_, len) = data.readVarInt(at: index)
                    index += len
                    let (length, len2) = data.readVarInt(at: index)
                    index += len2 + Int(length)
                }
            }
        }

        return HostBytes(hoststring: hoststring)
    }
}

extension EchoAck {
    public func encode() -> Data {
        var data = Data()

        if echoAckNum != 0 {
            data.append(64) // (8 << 3) | 0 = 64
            data.appendVarInt(echoAckNum)
        }

        return data
    }

    public static func decode(from data: Data) -> EchoAck? {
        var echoAckNum: UInt64 = 0
        var index = 0

        while index < data.count {
            guard index < data.count else { break }
            let tag = data[index]
            index += 1

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            if fieldNumber == 8 && wireType == 0 {
                let (value, len) = data.readVarInt(at: index)
                index += len
                echoAckNum = value
            } else {
                // Skip unknown field
                if wireType == 0 {
                    while index < data.count && data[index] >= 0x80 { index += 1 }
                    index += 1
                } else if wireType == 2 {
                    let (_, len) = data.readVarInt(at: index)
                    index += len
                    let (length, len2) = data.readVarInt(at: index)
                    index += len2 + Int(length)
                }
            }
        }

        return EchoAck(echoAckNum: echoAckNum)
    }
}

// MARK: - VarInt Helpers

private extension Data {
    /// Read a varint from the data at the given index
    func readVarInt(at index: Int) -> (value: UInt64, length: Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var i = index

        while i < count {
            let byte = self[i]
            i += 1

            result |= UInt64(byte & 0x7F) << shift
            shift += 7

            if byte & 0x80 == 0 {
                break
            }
        }

        return (result, i - index)
    }

    /// Append a varint to the data
    mutating func appendVarInt(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 {
                byte |= 0x80
            }
            append(byte)
        } while v != 0
    }
}
