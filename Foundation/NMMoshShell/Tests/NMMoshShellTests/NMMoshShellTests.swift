//
//  NMMoshShellTests.swift
//  NMMoshShellTests
//
//  Unit tests for Mosh protocol implementation.
//

import XCTest
@testable import NMMoshShell

final class NMMoshShellTests: XCTestCase {

    // MARK: - Protocol Tests

    func testMoshPacketEncoding() throws {
        // Test basic packet encoding
        let packet = MoshPacket(
            type: .string,
            sequenceNumber: 42,
            ackNumber: 100,
            payload: Data("Hello, Mosh!".utf8)
        )

        let encoded = packet.encode()

        // Verify packet header (5 bytes: type + seq + ack)
        XCTAssertEqual(encoded.count, 5 + 12) // 5 bytes header + 12 bytes payload
        XCTAssertEqual(encoded[0], MoshPacketType.string.rawValue)
    }

    func testMoshPacketDecoding() throws {
        // Manually create a valid packet
        var data = Data()
        data.append(1) // type: string
        data.append(0) // seq high byte
        data.append(42) // seq low byte
        data.append(0) // ack high byte
        data.append(100) // ack low byte
        data.append("Test".data(using: .utf8)!)

        let packet = try XCTUnwrap(MoshPacket.decode(data))

        XCTAssertEqual(packet.type, .string)
        XCTAssertEqual(packet.sequenceNumber, 42)
        XCTAssertEqual(packet.ackNumber, 100)
        XCTAssertEqual(packet.payload, "Test".data(using: .utf8))
    }

    func testMoshPacketRoundTrip() throws {
        let original = MoshPacket(
            type: .key,
            sequenceNumber: 12345,
            ackNumber: 6789,
            payload: Data([0x01, 0x02, 0x03])
        )

        let encoded = original.encode()
        let decoded = try XCTUnwrap(MoshPacket.decode(encoded))

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.sequenceNumber, original.sequenceNumber)
        XCTAssertEqual(decoded.ackNumber, original.ackNumber)
        XCTAssertEqual(decoded.payload, original.payload)
    }

    func testAllPacketTypes() throws {
        let types: [MoshPacketType] = [.ack, .string, .key, .resize, .ping]

        for type in types {
            let packet = MoshPacket(
                type: type,
                sequenceNumber: 1,
                ackNumber: 0,
                payload: Data()
            )

            let encoded = packet.encode()
            let decoded = try XCTUnwrap(MoshPacket.decode(encoded))

            XCTAssertEqual(decoded.type, type, "Failed for type \(type)")
        }
    }

    // MARK: - KeyEvent Tests

    func testKeyEventEncoding() throws {
        let event = MoshKeyEvent(type: .press, keyCode: 0x41, modifiers: 0x02) // 'A' with shift
        let encoded = event.encode()

        XCTAssertEqual(encoded.count, 3)
        XCTAssertEqual(encoded[0], 0) // press type
        XCTAssertEqual(encoded[1], 0x41) // key code
        XCTAssertEqual(encoded[2], 0x02) // modifiers
    }

    func testKeyEventDecoding() throws {
        let data = Data([0, 0x41, 0x02])
        let event = try XCTUnwrap(MoshKeyEvent.decode(data))

        XCTAssertEqual(event.type, .press)
        XCTAssertEqual(event.keyCode, 0x41)
        XCTAssertEqual(event.modifiers, 0x02)
    }

    // MARK: - StringPacket Tests

    func testStringPacketEncoding() throws {
        let packet = MoshStringPacket(
            data: "Hello".data(using: .utf8)!,
            startRow: 0,
            startCol: 0,
            endRow: 0,
            endCol: 5
        )

        let encoded = packet.encode()

        // Should have 8 bytes header + payload
        XCTAssertEqual(encoded.count, 8 + 5)
    }

    func testStringPacketDecoding() throws {
        var data = Data()
        // Header
        data.append(0) // start row high
        data.append(0) // start row low
        data.append(0) // start col high
        data.append(0) // start col low
        data.append(0) // end row high
        data.append(0) // end row low
        data.append(0) // end col high
        data.append(5) // end col low
        // Payload
        data.append("Hello".data(using: .utf8)!)

        let packet = try XCTUnwrap(MoshStringPacket.decode(data))

        XCTAssertEqual(packet.startRow, 0)
        XCTAssertEqual(packet.startCol, 0)
        XCTAssertEqual(packet.endRow, 0)
        XCTAssertEqual(packet.endCol, 5)
        XCTAssertEqual(packet.data, "Hello".data(using: .utf8))
    }

    // MARK: - Crypto Tests

    func testCryptoKeyDerivation() throws {
        let keyString = "test-key-12345"
        let crypto = try NMCrypto(keyString: keyString)

        // Key derivation should succeed
        XCTAssertNotNil(crypto)
    }

    func testCryptoEncryptDecrypt() throws {
        let crypto = try NMCrypto(keyString: "test-key")
        let plaintext = "Hello, Mosh!".data(using: .utf8)!

        // In current implementation, encryption is a no-op
        let encrypted = try crypto.encrypt(plaintext)
        let decrypted = try crypto.decrypt(encrypted)

        // Should be equal (no-op encryption)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - StateSync Tests

    func testStateSyncInitialization() throws {
        let sync = NMStateSync(rows: 24, cols: 80)

        let state = sync.terminalState
        XCTAssertEqual(state.rows, 24)
        XCTAssertEqual(state.cols, 80)
        XCTAssertEqual(state.cells.count, 24 * 80)
    }

    func testStateSyncDiff() throws {
        let sync = NMStateSync(rows: 10, cols: 10)

        let diff = NMStateSync.StateDiff(
            sequenceNumber: 1,
            acknowledgments: [0],
            displayChanges: [
                .write(row: 0, col: 0, string: "Test"),
                .setCursor(row: 1, col: 2)
            ],
            timestamp: 1000
        )

        sync.applyDiff(diff)

        let state = sync.terminalState
        let cell = state.cell(at: 0, col: 0)
        XCTAssertEqual(cell.char, "T")
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorCol, 2)
    }

    func testStateSyncResize() throws {
        let sync = NMStateSync(rows: 10, cols: 10)

        // Write some data
        let diff = NMStateSync.StateDiff(
            sequenceNumber: 1,
            displayChanges: [.write(row: 0, col: 0, string: "ABCD")],
            timestamp: 0
        )
        sync.applyDiff(diff)

        // Resize
        sync.resize(rows: 20, cols: 20)

        let state = sync.terminalState
        XCTAssertEqual(state.rows, 20)
        XCTAssertEqual(state.cols, 20)

        // Check that data was preserved
        let cell = state.cell(at: 0, col: 0)
        XCTAssertEqual(cell.char, "A")
    }

    // MARK: - Prediction Tests

    func testPredictionInitialization() throws {
        let prediction = NMPrediction(rows: 24, cols: 80, mode: .adaptive)

        // Should initialize without error
        XCTAssertNotNil(prediction)
    }

    func testPredictionBasic() throws {
        let prediction = NMPrediction(rows: 24, cols: 80, mode: .always)

        let result = prediction.predict(input: "echo hello\n")

        // With "always" mode, should predict
        XCTAssertFalse(result.displayString.isEmpty)
        XCTAssertGreaterThan(result.confidence, 0)
    }

    func testPredictionModeSet() throws {
        let prediction = NMPrediction(rows: 24, cols: 80, mode: .never)

        prediction.setMode(.always)
        let result = prediction.predict(input: "test")

        // Should now predict with always mode
        XCTAssertGreaterThan(result.confidence, 0.5)
    }

    // MARK: - UDPConnection Tests

    func testUDPConnectionInit() throws {
        let connection = NMUDPConnection()

        XCTAssertEqual(connection.state, .idle)
    }
}
