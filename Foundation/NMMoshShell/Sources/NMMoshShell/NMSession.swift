//
//  NMSession.swift
//  NMMoshShell
//
//  Mosh session manager - handles communication with mosh-server.
//
//  Mosh protocol format:
//  - Packet: Nonce (12 bytes) + Encrypted(timestamps + payload + auth_tag)
//  - Nonce: direction (4 bytes BE) + sequence (8 bytes BE)
//  - Timestamps: timestamp (2 bytes BE) + timestamp_reply (2 bytes BE) - inside encrypted payload
//  - Payload: protobuf TransportInstruction
//

import Foundation
import Network
import zlib

/// Mosh session manager for handling UDP communication with mosh-server
public final class NMSession: @unchecked Sendable {

    /// Enable/disable verbose debug logging
    public var debugLogging: Bool = true

    // MARK: - Types

    public enum State: Sendable {
        case disconnected
        case connecting
        case connected
        case failed(Error)
    }

    public typealias StateHandler = (State) -> Void
    public typealias ReceiveHandler = (Data) -> Void

    // MARK: - Constants

    /// Mosh protocol version
    public static let PROTOCOL_VERSION: UInt32 = 2

    /// Direction for nonce: client to server
    private static let DIRECTION_TO_SERVER: UInt32 = 0

    /// Direction for nonce: server to client
    private static let DIRECTION_TO_CLIENT: UInt32 = 1

    // MARK: - Properties

    private let queue = DispatchQueue(label: "wiki.qaq.mosh.session", qos: .userInitiated)
    private let lock = NSLock()
    private var connection: NWConnection?
    private var currentState: State = .disconnected

    // Sequence numbers (64-bit for mosh protocol)
    private var sendSequenceNumber: UInt64 = 0
    private var expectedReceiveSequence: UInt64 = 0
    private var acknowledgedSequence: UInt64 = 0
    private var receiverAckedState: UInt64 = 0
    private var lastAppliedRemoteState: UInt64 = 0
    private var lastAppliedNewNum: UInt64 = 0  // Track the actual new_num of last applied state
    private var nextFragmentID: UInt64 = 1

    // Timestamps (16-bit milliseconds, stored as network byte order in packets)
    private var lastSendTimestamp: UInt16 = 0
    private var lastReceiveTimestamp: UInt16 = 0

    private struct FragmentBuffer {
        var chunks: [UInt16: Data] = [:]
        var finalFragment: UInt16?
    }
    private struct PendingRemoteState {
        let oldNum: UInt64
        let diff: Data
    }
    private var fragmentBuffers: [UInt64: FragmentBuffer] = [:]
    private var pendingRemoteStates: [UInt64: PendingRemoteState] = [:]

    private var receiveHandler: ReceiveHandler?
    private var stateHandler: StateHandler?

    // Encryption
    private var crypto: NMCrypto?
    private var encryptionEnabled: Bool = false

    // Initial terminal size (set via connect())
    private var initialRows: UInt16 = 24
    private var initialCols: UInt16 = 80

    // MARK: - Public Properties

    public var state: State {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Connect to mosh-server
    public func connect(
        host: String,
        port: UInt16,
        key: String,
        initialRows: UInt16 = 24,
        initialCols: UInt16 = 80,
        stateHandler: StateHandler? = nil,
        receiveHandler: ReceiveHandler? = nil
    ) {
        lock.lock()
        self.stateHandler = stateHandler
        self.receiveHandler = receiveHandler
        self.initialRows = initialRows
        self.initialCols = initialCols

        // Initialize encryption with the provided key
        // Mosh key is base64-encoded 16-byte AES key
        do {
            self.crypto = try NMCrypto(keyString: key)
            encryptionEnabled = true
            print("[Mosh] Encryption initialized successfully")
        } catch {
            encryptionEnabled = false
            print("[Mosh] Encryption initialization failed: \(error), continuing without encryption")
        }

        // Mosh transport starts from state 0 as initial baseline.
        // First transmitted state must be new_num = 1.
        sendSequenceNumber = 1
        expectedReceiveSequence = 0
        receiverAckedState = 0
        lastAppliedRemoteState = 0
        pendingRemoteStates.removeAll()

        lock.unlock()

        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            print("[Mosh] Invalid port: \(port)")
            updateState(.failed(NMSessionError.invalidEndpoint))
            return
        }

        print("[Mosh] Connecting to \(host):\(port)")

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: portEndpoint)

        let newConnection = NWConnection(to: endpoint, using: .udp)
        newConnection.stateUpdateHandler = { [weak self] newState in
            self?.handleConnectionState(newState)
        }

        newConnection.start(queue: queue)
        connection = newConnection

        updateState(.connecting)
        startReceiving()

        // Note: Initial packet will be sent when connection becomes ready
        // (see handleConnectionState .ready case)
    }

    /// Disconnect from mosh-server
    public func disconnect() {
        lock.lock()
        connection?.cancel()
        connection = nil
        lock.unlock()
        updateState(.disconnected)
    }

    /// Send string data to mosh-server (user keystrokes)
    public func sendString(_ string: String) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.debugLogging { print("[Mosh] >>> sendString: \"\(string.prefix(20).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r"))\" (\(string.count) chars)") }
            // Create UserMessage with keystroke instruction
            let keystroke = Keystroke(string: string)
            let instruction = UserInstruction(keystroke: keystroke)
            let userMessage = UserMessage(instructions: [instruction])
            let payload = userMessage.encode()

            self.sendTransportInstruction(payload: payload)
        }
    }

    /// Send key event to mosh-server
    public func sendKey(keyCode: UInt8, modifiers: UInt8 = 0) {
        queue.async { [weak self] in
            guard let self else { return }
            let keyData = Data([keyCode, modifiers])
            let keystroke = Keystroke(keys: keyData)
            let instruction = UserInstruction(keystroke: keystroke)
            let userMessage = UserMessage(instructions: [instruction])
            let payload = userMessage.encode()

            self.sendTransportInstruction(payload: payload)
        }
    }

    /// Send terminal resize to mosh-server
    public func sendResize(rows: UInt16, cols: UInt16) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.debugLogging { print("[Mosh] sendResize(rows: \(rows), cols: \(cols))") }
            let resize = ResizeMessage(width: Int32(cols), height: Int32(rows))
            let instruction = UserInstruction(resize: resize)
            let userMessage = UserMessage(instructions: [instruction])
            let payload = userMessage.encode()
            if self.debugLogging { print("[Mosh] Resize payload: \(payload.map { String(format: "%02x", $0) }.joined(separator: " "))") }

            self.sendTransportInstruction(payload: payload)
        }
    }

    // MARK: - Private Methods - Transport Layer

    /// Send a TransportInstruction packet
    private func sendTransportInstruction(payload: Data) {
        // Create TransportInstruction protobuf
        var transportData = Data()

        // Field 1: protocol_version (varint)
        transportData.append(8) // (1 << 3) | 0 = 8
        transportData.appendVarInt(UInt64(Self.PROTOCOL_VERSION))

        // Field 2: old_num (varint) - reference state number for diff application.
        // This must be the state we believe the receiver has acknowledged.
        lock.lock()
        let newNum = sendSequenceNumber
        sendSequenceNumber &+= 1
        let oldNum = (newNum == 0) ? 0 : (newNum - 1)  // Each payload is an incremental diff from previous state
        let ackNum = lastAppliedRemoteState
        let throwawayNum = receiverAckedState
        lock.unlock()

        if debugLogging { print("[Mosh] TX transport old=\(oldNum), new=\(newNum), ack=\(ackNum), diff=\(payload.count)") }

        transportData.append(16) // (2 << 3) | 0 = 16
        transportData.appendVarInt(oldNum)

        // Field 3: new_num (varint) - our new state number
        // This must match the nonce sequence used in sendMoshPacket.
        transportData.append(24) // (3 << 3) | 0 = 24
        transportData.appendVarInt(newNum)

        // Field 4: ack_num (varint) - acknowledge received state
        transportData.append(32) // (4 << 3) | 0 = 32
        transportData.appendVarInt(ackNum)

        // Field 5: throwaway_num (varint) - earliest state receiver should retain.
        // We can safely tell the peer to discard states below what it already ACKed.
        transportData.append(40) // (5 << 3) | 0 = 40
        transportData.appendVarInt(throwawayNum)

        // Field 6: diff (bytes) - the payload
        transportData.append(50) // (6 << 3) | 2 = 50
        transportData.appendVarInt(UInt64(payload.count))
        transportData.append(payload)

        // Mosh transport payload is zlib-compressed and wrapped in a 10-byte fragment header.
        guard let compressed = try? compressZlib(transportData) else {
            print("[Mosh] Failed to zlib-compress transport payload")
            return
        }

        let fragmentID: UInt64
        lock.lock()
        fragmentID = nextFragmentID
        nextFragmentID &+= 1
        lock.unlock()

        var fragmentPayload = Data(capacity: 10 + compressed.count)
        var idBE = fragmentID.bigEndian
        withUnsafeBytes(of: &idBE) { fragmentPayload.append(contentsOf: $0) }

        // Single-fragment packet: final bit set + fragment number 0.
        var fragmentHeader: UInt16 = 0x8000
        fragmentHeader = fragmentHeader.bigEndian
        withUnsafeBytes(of: &fragmentHeader) { fragmentPayload.append(contentsOf: $0) }

        fragmentPayload.append(compressed)

        sendMoshPacket(payload: fragmentPayload, sequence: newNum)
    }

    /// Send an empty packet (for keepalive/initial connection)
    private func sendEmptyPacket() {
        if debugLogging { print("[Mosh] sendEmptyPacket() called - sending initial resize packet") }
        // Send initial packet with terminal resize
        // This is what mosh-client does - sends Resize first
        // IMPORTANT: This MUST be sent as sequence 0
        sendResize(rows: initialRows, cols: initialCols)
    }

    /// Send a raw Mosh packet with encryption
    /// - Parameters:
    ///   - payload: The TransportInstruction payload to send
    ///   - sequence: The sequence number for this packet (must match new_num in payload)
    private func sendMoshPacket(payload: Data, sequence: UInt64? = nil) {
        guard let conn = connection else {
            print("[Mosh] Cannot send - no connection")
            return
        }

        // Get sequence number - either passed in or get current
        let seq: UInt64
        if let providedSeq = sequence {
            seq = providedSeq
        } else {
            lock.lock()
            seq = sendSequenceNumber
            lock.unlock()
        }

        // Add timestamp header (4 bytes: timestamp + timestamp_reply)
        var packetData = Data(capacity: 4 + payload.count)

        // Current timestamp (16-bit, ms since epoch mod 65536)
        let timestamp: UInt16 = UInt16(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000) % 65536)
        packetData.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian) { Array($0) })

        // Reply with last received server timestamp so server knows we received its data
        lock.lock()
        let replyTs: UInt16 = lastReceiveTimestamp
        lock.unlock()
        packetData.append(contentsOf: withUnsafeBytes(of: replyTs.bigEndian) { Array($0) })

        // Append payload
        packetData.append(payload)

        if debugLogging {
            print("[Mosh] Sending packet: \(packetData.count) bytes (4 header + \(payload.count) payload)")
            print("[Mosh] Payload hex: \(payload.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))")
        }

        // Encrypt if enabled
        var finalData = packetData

        if debugLogging { print("[Mosh] Encryption enabled: \(encryptionEnabled), crypto: \(crypto != nil ? "yes" : "no")") }

        if encryptionEnabled, let crypto = crypto {
            do {
                // Generate nonce for this packet
                // Mosh nonce format: 4 zero bytes + 8 bytes (direction bit 63 | sequence number)
                // Direction bit: TO_SERVER = 0 (bit 63 clear)
                let seqWithDirection: UInt64 = seq  // TO_SERVER means bit 63 is 0

                // Build 12-byte nonce: 4 zero bytes + 8 bytes big-endian sequence
                var nonce = Data(capacity: 12)
                nonce.append(contentsOf: [0, 0, 0, 0])  // First 4 bytes are zeros
                var seqBE = seqWithDirection.bigEndian
                withUnsafeBytes(of: &seqBE) { nonce.append(contentsOf: $0) }

                if self.debugLogging {
                    print("[Mosh] Nonce (12 bytes): \(nonce.map { String(format: "%02x", $0) }.joined(separator: " "))")
                    print("[Mosh] Sequence: \(seq)")
                    print("[Mosh] Encrypting \(packetData.count) bytes...")
                }

                let encrypted = try crypto.encrypt(packetData, nonce: nonce)
                if self.debugLogging { print("[Mosh] Encryption succeeded, encrypted size: \(encrypted.count)") }

                // Mosh wire format: 8-byte nonce suffix + encrypted data
                // The nonce suffix is the last 8 bytes of the 12-byte nonce
                let nonceSuffix = nonce.suffix(8)
                finalData = nonceSuffix + encrypted
                if self.debugLogging { print("[Mosh] Encrypted packet: \(finalData.count) bytes (nonce_suffix=8, encrypted=\(encrypted.count))") }
            } catch {
                print("[Mosh] Encryption FAILED: \(error)")
                print("[Mosh] Error details: \(error.localizedDescription)")
                // Continue without encryption for debugging
                print("[Mosh] WARNING: Sending UNENCRYPTED packet for debugging!")
            }
        } else {
            print("[Mosh] WARNING: Sending unencrypted packet!")
        }

        if debugLogging {
            print("[Mosh] Final packet hex: \(finalData.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))")
            if let path = conn.currentPath {
                print("[Mosh] Current path: \(path)")
                if let remote = path.remoteEndpoint {
                    print("[Mosh] Remote endpoint: \(remote)")
                }
                if let local = path.localEndpoint {
                    print("[Mosh] Local endpoint: \(local)")
                }
            }
        }

        conn.send(content: finalData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("[Mosh] ❌ Send error: \(error)")
            } else if self?.debugLogging == true {
                print("[Mosh] ✅ Sent \(finalData.count) bytes successfully")
            }
        })
    }

    /// Generate a 12-byte nonce for Mosh encryption
    /// Mosh format: 4 zero bytes + 8 bytes sequence with direction in MSB
    private func generateNonce(direction: UInt32, sequence: UInt64) -> Data {
        var nonce = Data(capacity: 12)

        // First 4 bytes: zeros (Mosh protocol)
        nonce.append(contentsOf: [0, 0, 0, 0])

        // Next 8 bytes: sequence number with direction bit in MSB
        // Direction bit: bit 63 (TO_CLIENT=1, TO_SERVER=0)
        var seqWithDirection = sequence
        if direction == Self.DIRECTION_TO_CLIENT {
            seqWithDirection |= (1 << 63)
        }
        var seqBE = seqWithDirection.bigEndian
        withUnsafeBytes(of: &seqBE) { nonce.append(contentsOf: $0) }

        return nonce
    }

    /// Generate send nonce (TO_SERVER direction)
    private func generateSendNonce() -> Data {
        lock.lock()
        let seq = sendSequenceNumber
        // Don't increment here - increment after successful send
        lock.unlock()
        return generateNonce(direction: Self.DIRECTION_TO_SERVER, sequence: seq)
    }

    /// Extract sequence number from an 8-byte nonce suffix
    private func extractSequenceFromNonce(_ nonceSuffix: Data) -> UInt64 {
        guard nonceSuffix.count >= 8 else { return 0 }

        // Read 8 bytes as big-endian sequence number (with direction bit in MSB)
        var seq: UInt64 = 0
        for i in 0..<8 {
            seq = (seq << 8) | UInt64(nonceSuffix[i])
        }

        // Clear the direction bit (bit 63) to get the actual sequence number
        let sequenceNum = seq & 0x7FFFFFFFFFFFFFFF
        let direction = (seq >> 63) & 1
        if debugLogging { print("[Mosh] Extracted seq=\(sequenceNum), direction=\(direction == 1 ? "TO_CLIENT" : "TO_SERVER")") }

        return sequenceNum
    }

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            print("[Mosh] UDP connection ready")
            updateState(.connected)
            // Send initial packet now that connection is ready
            sendEmptyPacket()
        case .failed(let error):
            print("[Mosh] UDP connection failed: \(error)")
            updateState(.failed(error))
        case .waiting(let error):
            print("[Mosh] UDP connection waiting: \(error)")
        case .setup:
            print("[Mosh] UDP connection setup")
        case .preparing:
            print("[Mosh] UDP connection preparing")
        case .cancelled:
            print("[Mosh] UDP connection cancelled")
        @unknown default:
            print("[Mosh] UDP connection unknown state: \(newState)")
        }
    }

    private func startReceiving() {
        guard let conn = connection else { return }

        conn.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[Mosh] Receive error: \(error)")
            }

            if let data = data, !data.isEmpty {
                if self.debugLogging { print("[Mosh] Received \(data.count) bytes: \(data.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))") }
                self.handleReceivedData(data)
            }

            // UDP datagrams are discrete messages; continue receiving unless disconnected.
            if case .disconnected = self.state {
                print("[Mosh] Receive loop stopped (disconnected)")
                return
            }
            if case .failed = self.state {
                print("[Mosh] Receive loop stopped (failed)")
                return
            }
            if isComplete, self.debugLogging {
                print("[Mosh] receiveMessage completed one datagram, continuing...")
            }
            self.startReceiving()
        }
    }

    private func handleReceivedData(_ data: Data) {
        if debugLogging { print("[Mosh] Handling received data: \(data.count) bytes") }

        var packetData = data

        // Decrypt if encryption is enabled
        if encryptionEnabled, let crypto = crypto {
            // Mosh wire format: 8-byte nonce suffix + encrypted payload (with 16-byte auth tag)
            // Minimum: 8 bytes nonce + 4 bytes timestamp header + 16 bytes auth tag = 28 bytes
            guard data.count >= 24 else {
                print("[Mosh] Data too short for encrypted packet (\(data.count) bytes)")
                return
            }

            // Extract 8-byte nonce suffix from wire
            let nonceSuffix = data.prefix(8)
            let encrypted = data.dropFirst(8)

            // Build full 12-byte nonce: 4 zero bytes + 8 bytes from wire
            // For server->client, direction bit (bit 63) is set
            var nonce = Data(capacity: 12)
            nonce.append(contentsOf: [0, 0, 0, 0])  // First 4 bytes are zeros
            nonce.append(nonceSuffix)

            // Extract sequence from nonce for verification
            let receivedSeq = extractSequenceFromNonce(Data(nonceSuffix))
            if debugLogging { print("[Mosh] Received nonce suffix: \(nonceSuffix.map { String(format: "%02x", $0) }.joined(separator: " ")), seq=\(receivedSeq)") }

            do {
                packetData = try crypto.decrypt(Data(encrypted), nonce: nonce)
                if debugLogging { print("[Mosh] Decrypted successfully: \(packetData.count) bytes") }
            } catch {
                print("[Mosh] Decryption failed: \(error)")
                return
            }
        }

        // Parse packet: 4-byte timestamp header + Fragment payload
        guard packetData.count >= 4 else {
            print("[Mosh] Packet too short: \(packetData.count) bytes")
            return
        }

        // Extract timestamps
        let timestamp = packetData.prefix(2).withUnsafeBytes { UInt16(bigEndian: $0.load(as: UInt16.self)) }
        let timestampReply = packetData.subdata(in: 2..<4).withUnsafeBytes { UInt16(bigEndian: $0.load(as: UInt16.self)) }
        let transportPayload = packetData.dropFirst(4)

        // Save the server's timestamp so we can echo it back as ts_reply
        lock.lock()
        lastReceiveTimestamp = timestamp
        lock.unlock()

        if debugLogging { print("[Mosh] Timestamps: ts=\(timestamp), ts_reply=\(timestampReply), payload=\(transportPayload.count) bytes") }

        // Parse mosh transport fragment envelope.
        handleTransportFragment(Data(transportPayload))
    }

    private func handleTransportFragment(_ data: Data) {
        // Fragment wire: 8-byte id + 2-byte (final_bit|fragment_num) + zlib-compressed bytes
        guard data.count >= 10 else {
            print("[Mosh] Fragment too short: \(data.count) bytes")
            return
        }

        let id: UInt64 = data.prefix(8).withUnsafeBytes { raw in
            UInt64(bigEndian: raw.load(as: UInt64.self))
        }
        let combined: UInt16 = data.subdata(in: 8..<10).withUnsafeBytes { raw in
            UInt16(bigEndian: raw.load(as: UInt16.self))
        }
        let isFinal = (combined & 0x8000) != 0
        let fragmentNum = combined & 0x7FFF
        let payload = data.dropFirst(10)

        lock.lock()
        var buffer = fragmentBuffers[id] ?? FragmentBuffer()
        buffer.chunks[fragmentNum] = Data(payload)
        if isFinal {
            buffer.finalFragment = fragmentNum
        }
        fragmentBuffers[id] = buffer

        guard let finalFragment = buffer.finalFragment else {
            lock.unlock()
            return
        }

        let expectedCount = Int(finalFragment) + 1
        guard buffer.chunks.count >= expectedCount else {
            lock.unlock()
            return
        }

        var assembledCompressed = Data()
        for index in 0...finalFragment {
            guard let chunk = buffer.chunks[index] else {
                lock.unlock()
                return
            }
            assembledCompressed.append(chunk)
        }
        fragmentBuffers.removeValue(forKey: id)
        lock.unlock()

        guard let assembled = try? decompressZlib(assembledCompressed) else {
            print("[Mosh] Failed to zlib-decompress fragment assembly (\(assembledCompressed.count) bytes)")
            return
        }

        parseTransportInstruction(assembled)
    }

    private func parseTransportInstruction(_ data: Data) {
        // Parse protobuf fields
        var oldNum: UInt64 = 0
        var newNum: UInt64 = 0
        var ackNum: UInt64 = 0
        var diff: Data?

        var index = 0
        while index < data.count {
            guard index < data.count else { break }
            let tag = data[index]
            index += 1

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            // Helper to read varint
            func readVarInt() -> UInt64 {
                var result: UInt64 = 0
                var shift: UInt64 = 0
                while index < data.count {
                    let byte = data[index]
                    index += 1
                    result |= UInt64(byte & 0x7F) << shift
                    shift += 7
                    if byte & 0x80 == 0 { break }
                }
                return result
            }

            // Helper to read length-delimited
            func readBytes() -> Data {
                let length = readVarInt()
                let bytes = data.subdata(in: index..<index+Int(length))
                index += Int(length)
                return bytes
            }

            switch fieldNumber {
            case 1: // protocol_version
                if wireType == 0 {
                    _ = readVarInt() // We know version 2
                }
            case 2: // old_num
                if wireType == 0 {
                    oldNum = readVarInt()
                }
            case 3: // new_num
                if wireType == 0 {
                    newNum = readVarInt()
                }
            case 4: // ack_num
                if wireType == 0 {
                    ackNum = readVarInt()
                }
            case 5: // throwaway_num
                if wireType == 0 {
                    _ = readVarInt()
                }
            case 6: // diff
                if wireType == 2 {
                    diff = readBytes()
                }
            case 7: // chaff
                if wireType == 2 {
                    _ = readBytes()
                }
            default:
                // Skip unknown field
                if wireType == 0 {
                    _ = readVarInt()
                } else if wireType == 2 {
                    _ = readBytes()
                }
            }
        }

        if debugLogging { print("[Mosh] Transport: old=\(oldNum), new=\(newNum), ack=\(ackNum), diff=\(diff?.count ?? 0) bytes, lastApplied=\(lastAppliedRemoteState)") }

        let transportDiff = diff ?? Data()

        // Update remote ACK for our transmitted states and cache remote state update.
        lock.lock()
        if ackNum > receiverAckedState {
            receiverAckedState = ackNum
        }
        let appliedState = lastAppliedRemoteState

        // Check if we've already seen this state
        if pendingRemoteStates[newNum] != nil {
            lock.unlock()
            if debugLogging { print("[Mosh] DUPLICATE state new=\(newNum) already pending, skipping") }
            return
        }

        if newNum <= appliedState {
            lock.unlock()
            if debugLogging { print("[Mosh] Ignoring stale state old=\(oldNum), new=\(newNum), lastApplied=\(appliedState)") }
            return
        }
        pendingRemoteStates[newNum] = PendingRemoteState(oldNum: oldNum, diff: transportDiff)
        let pendingCount = pendingRemoteStates.count
        lock.unlock()

        if debugLogging { print("[Mosh] Added pending state new=\(newNum), pending count=\(pendingCount)") }

        applyPendingRemoteStates()
    }

    private func applyPendingRemoteStates() {
        while true {
            lock.lock()
            // Mosh SSP (State Synchronization Protocol) semantics:
            // - Each state frame is a DIFF from oldNum to newNum
            // - States must be applied in order, each diff builds on the previous
            // - oldNum indicates which state this diff is based on
            // - We can only apply a diff if its base state (oldNum) matches our current state

            // Find the next state that can be applied (oldNum == lastAppliedRemoteState)
            // and has the lowest newNum (earliest in sequence)
            var targetState: UInt64?
            var targetPending: PendingRemoteState?
            var pendingCount: Int = 0

            for (stateNum, pending) in pendingRemoteStates {
                // A state can only be applied if its oldNum matches our current state exactly
                // This ensures we apply diffs in the correct order
                if pending.oldNum == lastAppliedRemoteState {
                    // Pick the earliest applicable state to maintain order
                    if targetState == nil || stateNum < targetState! {
                        targetState = stateNum
                        targetPending = pending
                    }
                }
            }
            pendingCount = pendingRemoteStates.count

            guard let state = targetState, let pending = targetPending else {
                lock.unlock()
                return
            }

            // Remove the state we're about to apply
            pendingRemoteStates.removeValue(forKey: state)

            // Update lastAppliedRemoteState to the new state number
            lastAppliedRemoteState = state
            lock.unlock()

            if debugLogging {
                print("[Mosh] Applying state new=\(state), old=\(pending.oldNum), diff=\(pending.diff.count) bytes, remaining=\(pendingCount - 1)")
            }
            applyRemoteDiff(pending.diff)
        }
    }

    private func applyRemoteDiff(_ diff: Data) {
        guard !diff.isEmpty else { return }

        // Try to parse as HostMessage
        if let hostMessage = HostMessage.decode(from: diff) {
            if debugLogging { print("[Mosh] Decoded HostMessage with \(hostMessage.instructions.count) instructions") }
            for instruction in hostMessage.instructions {
                if let hostbytes = instruction.hostbytes {
                    let payload = hostbytes.hoststring
                    if debugLogging {
                        let preview = previewTerminalBytes(payload)
                        print("[Mosh] HostBytes(\(payload.count) bytes): \(preview.prefix(80).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r"))...")
                    }
                    notifyReceive(payload)
                }
                if let echoack = instruction.echoack {
                    if debugLogging { print("[Mosh] EchoAck: \(echoack.echoAckNum)") }
                    // Handle echo acknowledgment - we can use this to confirm sent keystrokes
                }
            }
        } else {
            if debugLogging {
                let preview = previewTerminalBytes(diff)
                print("[Mosh] Raw diff(\(diff.count) bytes): \(preview.prefix(80).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r"))...")
            }
            notifyReceive(diff)
        }
    }

    private func previewTerminalBytes(_ data: Data) -> String {
        if let str = String(data: data, encoding: .utf8) {
            return str
        }
        // Do not drop control stream bytes when UTF-8 boundary/data is imperfect.
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            print("[Mosh] UTF-8 decode failed, fallback to ISO-8859-1 for \(data.count) bytes")
            return latin1
        }
        // Last resort: lossy replacement instead of dropping output.
        print("[Mosh] UTF-8 and ISO-8859-1 decode failed, using lossy decoding for \(data.count) bytes")
        return String(decoding: data, as: UTF8.self)
    }

    private func compressZlib(_ input: Data) throws -> Data {
        if input.isEmpty {
            // zlib stream for empty payload.
            return Data([0x78, 0x9c, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01])
        }

        let bound = compressBound(uLong(input.count))
        var output = Data(count: Int(bound))
        var outputLength = uLongf(bound)

        let status: Int32 = output.withUnsafeMutableBytes { outRaw in
            input.withUnsafeBytes { inRaw in
                guard let outBase = outRaw.baseAddress, let inBase = inRaw.baseAddress else {
                    return Z_BUF_ERROR
                }
                return compress2(
                    outBase.assumingMemoryBound(to: Bytef.self),
                    &outputLength,
                    inBase.assumingMemoryBound(to: Bytef.self),
                    uLong(input.count),
                    Z_DEFAULT_COMPRESSION
                )
            }
        }

        guard status == Z_OK else {
            throw NMSessionError.protocolError("zlib compress failed: \(status)")
        }

        output.removeSubrange(Int(outputLength)..<output.count)
        return output
    }

    private func decompressZlib(_ input: Data) throws -> Data {
        if input.isEmpty {
            return Data()
        }

        var capacity = max(1024, input.count * 8)

        while capacity <= 8 * 1024 * 1024 {
            var output = Data(count: capacity)
            var outputLength = uLongf(capacity)

            let status: Int32 = output.withUnsafeMutableBytes { outRaw in
                input.withUnsafeBytes { inRaw in
                    guard let outBase = outRaw.baseAddress, let inBase = inRaw.baseAddress else {
                        return Z_BUF_ERROR
                    }
                    return uncompress(
                        outBase.assumingMemoryBound(to: Bytef.self),
                        &outputLength,
                        inBase.assumingMemoryBound(to: Bytef.self),
                        uLong(input.count)
                    )
                }
            }

            if status == Z_OK {
                output.removeSubrange(Int(outputLength)..<output.count)
                return output
            }
            if status == Z_BUF_ERROR {
                capacity *= 2
                continue
            }
            throw NMSessionError.protocolError("zlib decompress failed: \(status)")
        }

        throw NMSessionError.protocolError("zlib decompress exceeded max output size")
    }

    private func updateState(_ newState: State) {
        lock.lock()
        currentState = newState
        let handler = stateHandler
        lock.unlock()

        handler?(newState)
    }

    private func notifyReceive(_ string: String) {
        receiveHandler?(Data(string.utf8))
    }

    private func notifyReceive(_ data: Data) {
        receiveHandler?(data)
    }
}

// MARK: - Data Extension for VarInt

private extension Data {
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

// MARK: - Errors

enum NMSessionError: Error {
    case invalidEndpoint
    case connectionFailed(String)
    case protocolError(String)
}
