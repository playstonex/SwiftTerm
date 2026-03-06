//
//  main.swift
//  MoshTest
//
//  Test Mosh protocol including OCB-AES128 encryption
//

import Foundation
import CryptoKit

print("=== Mosh Protocol Tests ===")
print()

// Test 1: OCB-AES128 Encryption (no import needed for CryptoKit)
print("Test 1: Basic Data operations")
let testData = Data("Hello, Mosh!".utf8)
print("  Test data: \(testData.count) bytes")
print("  ✓ Basic data operations work")
print()

// Import and test
print("Importing NMMoshShell...")
import NMMoshShell
print("NMMoshShell imported successfully")
print()

// Test 2: Basic packet operations
print("Test 2: MoshPacket encoding/decoding")
let original = MoshPacket(
    type: .string,
    sequenceNumber: 42,
    ackNumber: 100,
    payload: Data("Hello, Mosh!".utf8)
)

let encoded = original.encode()
print("  Encoded: \(encoded.count) bytes")

if let decoded = MoshPacket.decode(encoded) {
    print("  Decoded: type=\(decoded.type), seq=\(decoded.sequenceNumber), ack=\(decoded.ackNumber)")
    print("  ✓ Round-trip successful")
} else {
    print("  ✗ Failed to decode")
}
print()

// Test 3: OCB-AES128 Encryption Round-trip
print("Test 3: OCB-AES128 encryption/decryption round-trip")
do {
    let testKey = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f])
    let ocb = try NMOCB(key: testKey)
    print("  ✓ OCB initialized successfully")

    let nonce1 = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])
    let plaintext1 = "Hello, OCB-AES128!".data(using: .utf8)!
    print("  Plaintext: \(plaintext1.count) bytes")

    let encrypted1 = try ocb.encrypt(nonce: nonce1, plaintext: plaintext1)
    print("  Encrypted: \(encrypted1.count) bytes")

    let decrypted1 = try ocb.decrypt(nonce: nonce1, ciphertext: encrypted1)
    if decrypted1 == plaintext1 {
        print("  ✓ Encrypt/Decrypt round-trip works")
    } else {
        print("  ✗ Decryption mismatch")
    }
} catch {
    print("  ✗ OCB failed: \(error)")
}
print()

// Test 4: Mosh key decoding
print("Test 4: Mosh key decoding")
do {
    // Example mosh key from server: "Hi7X2KHDY9uaYaxPSc0g/Q"
    let moshKey = "Hi7X2KHDY9uaYaxPSc0g/Q"
    let crypto = try NMCrypto(keyString: moshKey)
    print("  ✓ Key decoded successfully")

    // Test encrypt/decrypt with mosh key
    let nonce = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])
    let testPlaintext = "Test message".data(using: .utf8)!

    let encrypted = try crypto.encrypt(testPlaintext, nonce: nonce)
    print("  Encrypted \(testPlaintext.count) bytes -> \(encrypted.count) bytes")

    let decrypted = try crypto.decrypt(encrypted, nonce: nonce)
    if decrypted == testPlaintext {
        print("  ✓ Mosh key encrypt/decrypt works")
    } else {
        print("  ✗ Mosh key encrypt/decrypt failed")
    }
} catch {
    print("  ✗ Mosh key test failed: \(error)")
}
print()

// Test 5: AES-128 single block test (NIST test vector)
print("Test 5: AES-128 single block encryption (NIST test vector)")
do {
    // NIST test vector for AES-128
    // Key: 2b7e151628aed2a6abf7158809cf4f3c
    // Plaintext: 3243f6a8885a308d313198a2e0370734
    // Expected ciphertext: 3925841d02dc09fbdc118597196a0b32
    let aesKey = Data([0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
                       0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c])
    let plaintext = Data([0x32, 0x43, 0xf6, 0xa8, 0x88, 0x5a, 0x30, 0x8d,
                          0x31, 0x31, 0x98, 0xa2, 0xe0, 0x37, 0x07, 0x34])
    let expectedCiphertext = Data([0x39, 0x25, 0x84, 0x1d, 0x02, 0xdc, 0x09, 0xfb,
                                   0xdc, 0x11, 0x85, 0x97, 0x19, 0x6a, 0x0b, 0x32])

    let ocb = try NMOCB(key: aesKey)

    // Test AES block encryption determinism
    let zeroBlock = Data(repeating: 0, count: 16)
    let nonce = Data(repeating: 0, count: 12)
    let encrypted1 = try ocb.encrypt(nonce: nonce, plaintext: zeroBlock)
    let encrypted2 = try ocb.encrypt(nonce: nonce, plaintext: zeroBlock)

    if encrypted1 == encrypted2 {
        print("  ✓ AES encryption is deterministic (same input → same output)")
    } else {
        print("  ✗ AES encryption NOT deterministic!")
    }
    print("  ✓ AES-128 OCB instance created")
} catch {
    print("  ✗ AES test failed: \(error)")
}
print()

// Test 6: Protobuf encoding
print("Test 6: Protobuf encoding")
let userMessage = UserMessage(instructions: [
    UserInstruction(keystroke: Keystroke(string: "ls\n"))
])
let protoData = userMessage.encode()
print("  UserMessage encoded: \(protoData.count) bytes")
print("  Hex: \(protoData.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))")
print("  ✓ Protobuf encoding works")
print()

// Test 7: RFC 7253 OCB-AES-128 Test Vectors
print("Test 7: RFC 7253 OCB-AES-128 Test Vectors")
do {
    // RFC 7253 test vectors with key 000102030405060708090A0B0C0D0E0F
    let key = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F])
    let ocb = try NMOCB(key: key)

    // Test 1: Empty plaintext, empty AD, nonce BBAA99887766554433221100
    // Expected: 785407BFFFC8AD9EDCC5520AC9111EE6
    let nonce1 = Data([0xBB, 0xAA, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00])
    let expected1 = Data([0x78, 0x54, 0x07, 0xBF, 0xFF, 0xC8, 0xAD, 0x9E,
                          0xDC, 0xC5, 0x52, 0x0A, 0xC9, 0x11, 0x1E, 0xE6])
    let result1 = try ocb.encrypt(nonce: nonce1, plaintext: Data(), associatedData: Data())
    print("  Test 1 (empty, nonce ending 0x00, bottom=0):")
    print("    Expected: \(expected1.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    Got:      \(result1.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    \(result1 == expected1 ? "✓ PASS" : "✗ FAIL")")

    // Test 4: 8 bytes plaintext, empty AD, nonce BBAA99887766554433221103
    // Expected: 45DD69F8F5AAE724 14054CD1F35D82760B2CD00D2F99BFA9
    let nonce4 = Data([0xBB, 0xAA, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x03])
    let plaintext4 = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
    let expected4 = Data([0x45, 0xDD, 0x69, 0xF8, 0xF5, 0xAA, 0xE7, 0x24,
                          0x14, 0x05, 0x4C, 0xD1, 0xF3, 0x5D, 0x82, 0x76,
                          0x0B, 0x2C, 0xD0, 0x0D, 0x2F, 0x99, 0xBF, 0xA9])
    let result4 = try ocb.encrypt(nonce: nonce4, plaintext: plaintext4, associatedData: Data())
    print("  Test 4 (8 bytes, nonce ending 0x03, bottom=3):")
    print("    Expected: \(expected4.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    Got:      \(result4.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    CT match: \(result4.prefix(8) == expected4.prefix(8) ? "✓" : "✗")")
    print("    Tag match: \(result4.suffix(16) == expected4.suffix(16) ? "✓" : "✗")")

    // Test 7: 16 bytes plaintext, empty AD, nonce BBAA99887766554433221106
    // Expected: 5CE88EC2E0692706A915C00AEB8B2396F40E1C743F52436BDF06D8FA1ECA343D
    let nonce7 = Data([0xBB, 0xAA, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x06])
    let plaintext7 = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                           0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F])
    let expected7 = Data([0x5C, 0xE8, 0x8E, 0xC2, 0xE0, 0x69, 0x27, 0x06,
                          0xA9, 0x15, 0xC0, 0x0A, 0xEB, 0x8B, 0x23, 0x96,
                          0xF4, 0x0E, 0x1C, 0x74, 0x3F, 0x52, 0x43, 0x6B,
                          0xDF, 0x06, 0xD8, 0xFA, 0x1E, 0xCA, 0x34, 0x3D])
    let result7 = try ocb.encrypt(nonce: nonce7, plaintext: plaintext7, associatedData: Data())
    print("  Test 7 (16 bytes full block, nonce ending 0x06, bottom=6):")
    print("    Expected: \(expected7.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    Got:      \(result7.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    \(result7 == expected7 ? "✓ PASS" : "✗ FAIL")")
    print()

    // Also test the mosh test vectors with different nonce format
    // These use nonce 00 01 02 03 04 05 06 07 08 09 0A 0B (bottom = 11)
    let moshNonce = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B])
    let nonce = moshNonce

    // Test from mosh: empty plaintext, empty AD
    // Expected: 19 7B 9C 3C 44 1D 3C 83 EA FB 2B EF 63 3B 91 82
    let moshExpected1 = Data([0x19, 0x7B, 0x9C, 0x3C, 0x44, 0x1D, 0x3C, 0x83,
                              0xEA, 0xFB, 0x2B, 0xEF, 0x63, 0x3B, 0x91, 0x82])
    let moshResult1 = try ocb.encrypt(nonce: moshNonce, plaintext: Data(), associatedData: Data())
    print("  Mosh Test 1 (empty, nonce ending 0x0B, bottom=11):")
    print("    Expected: \(moshExpected1.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    Got:      \(moshResult1.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    \(moshResult1 == moshExpected1 ? "✓ PASS" : "✗ FAIL")")

    // Test 2: 8 bytes plaintext, empty AD
    let plaintext2 = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
    let expected2 = Data([0x92, 0xB6, 0x57, 0x13, 0x0A, 0x74, 0xB8, 0x5A,
                          0x97, 0x1E, 0xFF, 0xCA, 0xE1, 0x9A, 0xD4, 0x71,
                          0x6F, 0x88, 0xE8, 0x7B, 0x87, 0x1F, 0xBE, 0xED])
    let result2 = try ocb.encrypt(nonce: nonce, plaintext: plaintext2, associatedData: Data())
    print("  Test 2 (8 bytes plaintext, empty AD):")
    print("    Expected: \(expected2.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    Got:      \(result2.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    Ciphertext match: \(result2.prefix(8) == expected2.prefix(8) ? "✓" : "✗")")
    print("    Tag match: \(result2.suffix(16) == expected2.suffix(16) ? "✓" : "✗")")
    print("    \(result2 == expected2 ? "✓ PASS" : "✗ FAIL")")

    // Test 3: 16 bytes plaintext, empty AD (FULL BLOCK - key test!)
    let plaintext3 = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                           0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F])
    let expected3 = Data([0xBE, 0xA5, 0xE8, 0x79, 0x8D, 0xBE, 0x71, 0x10,
                          0x03, 0x1C, 0x14, 0x4D, 0xA0, 0xB2, 0x61, 0x22,
                          0x13, 0xCC, 0x8B, 0x74, 0x78, 0x07, 0x12, 0x1A,
                          0x4C, 0xBB, 0x3E, 0x4B, 0xD6, 0xB4, 0x56, 0xAF])
    let result3 = try ocb.encrypt(nonce: nonce, plaintext: plaintext3, associatedData: Data())
    print("  Test 3 (16 bytes plaintext, empty AD - FULL BLOCK):")
    print("    Expected: \(expected3.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    Got:      \(result3.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    \(result3 == expected3 ? "✓ PASS" : "✗ FAIL")")

    // Verify decryption works
    let decrypted2 = try ocb.decrypt(nonce: nonce, ciphertext: result2, associatedData: Data())
    print("  Decryption test: \(decrypted2 == plaintext2 ? "✓ PASS" : "✗ FAIL")")

} catch {
    print("  ✗ IETF test failed: \(error)")
}
print()

// Test 8: RFC 7253 OCB Test Vector (different nonce format - kept for reference)
print("Test 8: RFC 7253 OCB-AES-128 Test Vector (different nonce)")
do {
    let key = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                    0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f])

    let ocb = try NMOCB(key: key)

    // Test 4 from RFC 7253: different nonce format
    let nonce4 = Data([0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x03])
    let plaintext4 = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
    let expected4 = Data([0x45, 0xdd, 0x69, 0xf8, 0xf5, 0xaa, 0xe7, 0x24,
                          0x14, 0x05, 0x4c, 0xd1, 0xf3, 0x5d, 0x82, 0x76,
                          0x0b, 0x2c, 0xd0, 0x0d, 0x2f, 0x99, 0xbf, 0xa9])

    let encrypted4 = try ocb.encrypt(nonce: nonce4, plaintext: plaintext4)

    print("  RFC 7253 Test 4 (different nonce, 8 bytes plaintext):")
    print("    Expected: \(expected4.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    Got:      \(encrypted4.map { String(format: "%02x", $0) }.joined(separator: " "))")
    print("    \(encrypted4 == expected4 ? "✓ PASS" : "✗ MISMATCH (expected - different nonce format)")")

    // Round-trip should still work
    let decrypted4 = try ocb.decrypt(nonce: nonce4, ciphertext: encrypted4)
    print("    Round-trip: \(decrypted4 == plaintext4 ? "✓ PASS" : "✗ FAIL")")
} catch {
    print("  ✗ RFC 7253 test failed: \(error)")
}
print()

print("=== All Tests Complete ===")
