//
//  NMCrypto.swift
//  NMMoshShell
//
//  Encryption support for Mosh protocol using OCB-AES128.
//
//  Mosh uses OCB (Offset Codebook Mode) AES-128 for encrypting
//  UDP payloads. This module implements the crypto operations.
//

import Foundation
import CommonCrypto

/// Mosh encryption manager
public final class NMCrypto: @unchecked Sendable {

    // MARK: - Types

    public enum CryptoError: Error, Sendable {
        case invalidKey
        case invalidNonce
        case encryptionFailed
        case decryptionFailed
    }

    // MARK: - Properties

    private let keyData: Data
    private let ocb: NMOCB  // Store OCB directly, not lazily
    private let lock = NSLock()
    private var nonceCounter: UInt64 = 0

    // MARK: - Initialization

    /// Initialize crypto with a base key string
    /// - Parameter keyString: The connection key from mosh-server (base64 encoded 16-byte key)
    public convenience init(keyString: String) throws {
        // Mosh key is a base64-encoded 16-byte AES-128 key
        // Format: 22 characters of base64 (e.g., "CR9kUHUG9JJ9sfOf4pVRXw")
        let key = Self.decodeBase64Key(from: keyString)
        try self.init(keyData: key)
    }

    /// Initialize with raw key data (16 bytes for AES-128)
    /// - Parameter keyData: Raw key data (16 bytes for AES-128)
    public init(keyData: Data) throws {
        guard keyData.count == 16 else {
            throw CryptoError.invalidKey
        }
        self.keyData = keyData
        self.ocb = try NMOCB(key: keyData)
        print("[NMCrypto] Initialized with key: \(keyData.map { String(format: "%02x", $0) }.joined(separator: " "))")
    }

    // MARK: - Public Methods

    /// Encrypt data for transmission
    /// - Parameter data: Plaintext data
    /// - Returns: Encrypted data with authentication tag appended
    public func encrypt(_ data: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let nonce = generateNonce()
        return try ocb.encrypt(nonce: nonce, plaintext: data)
    }

    /// Decrypt received data
    /// - Parameter data: Ciphertext data with authentication tag appended
    /// - Returns: Plaintext data
    /// - Throws: CryptoError.decryptionFailed if authentication fails
    public func decrypt(_ data: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        // For Mosh, we need to extract the nonce from the packet
        // In a real implementation, the nonce would be sent with the packet
        // For now, use the counter-based nonce
        let nonce = generateNonce()
        return try ocb.decrypt(nonce: nonce, ciphertext: data)
    }

    /// Encrypt data with explicit nonce
    /// - Parameters:
    ///   - data: Plaintext data
    ///   - nonce: 12-byte nonce
    /// - Returns: Encrypted data with authentication tag
    public func encrypt(_ data: Data, nonce: Data) throws -> Data {
        return try ocb.encrypt(nonce: nonce, plaintext: data)
    }

    /// Decrypt data with explicit nonce
    /// - Parameters:
    ///   - data: Ciphertext data with authentication tag
    ///   - nonce: 12-byte nonce
    /// - Returns: Plaintext data
    public func decrypt(_ data: Data, nonce: Data) throws -> Data {
        return try ocb.decrypt(nonce: nonce, ciphertext: data)
    }

    // MARK: - Private Methods

    private func generateNonce() -> Data {
        lock.lock()
        nonceCounter = nonceCounter &+ 1
        let counter = nonceCounter
        lock.unlock()

        // Generate 12-byte (96-bit) nonce as required by OCB
        var result = Data(capacity: 12)
        withUnsafeBytes(of: counter.littleEndian) { ptr in
            result.append(ptr.bindMemory(to: UInt8.self))
        }
        // Pad to 12 bytes
        while result.count < 12 {
            result.append(0)
        }
        return result
    }

    // MARK: - Key Decoding

    /// Decode a base64-encoded Mosh key to raw 16-byte AES key
    /// - Parameter keyString: Base64-encoded key (22 characters, e.g., "CR9kUHUG9JJ9sfOf4pVRXw")
    /// - Returns: 16-byte raw key data
    private static func decodeBase64Key(from keyString: String) -> Data {
        // Mosh uses base64-encoded 16-byte keys
        // The key string is typically 22 characters of base64 (without padding)
        // We need to decode it to get the raw 16 bytes

        // Handle standard base64 and base64url
        var base64 = keyString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed (base64 strings must be multiple of 4)
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        print("[NMCrypto] Decoding key string: '\(keyString)' (padded: '\(base64)')")

        // Decode base64 - this gives us the raw 16-byte AES-128 key
        guard let data = Data(base64Encoded: base64) else {
            print("[NMCrypto] ERROR: Failed to decode base64 key")
            // Fallback: use the string bytes directly (for backwards compatibility)
            return keyString.prefix(16).data(using: .utf8) ?? Data(count: 16)
        }

        print("[NMCrypto] Decoded key: \(data.count) bytes")
        print("[NMCrypto] Key hex: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")

        return data
    }
}

// MARK: - Nonce Generation for Mosh Protocol

/// Mosh nonce format: direction (4 bytes) + sequence number (8 bytes)
public struct MoshNonce {
    public let direction: UInt32  // 0 = TO_SERVER, 1 = TO_CLIENT
    public let sequenceNumber: UInt64

    public init(direction: UInt32, sequenceNumber: UInt64) {
        self.direction = direction
        self.sequenceNumber = sequenceNumber
    }

    /// Create nonce for client-to-server packet
    public init(clientToServer sequenceNumber: UInt64) {
        self.direction = 0  // TO_SERVER
        self.sequenceNumber = sequenceNumber
    }

    /// Create nonce for server-to-client packet
    public init(serverToClient sequenceNumber: UInt64) {
        self.direction = 1  // TO_CLIENT
        self.sequenceNumber = sequenceNumber
    }

    /// Convert to 12-byte Data for OCB encryption
    public func toData() -> Data {
        var result = Data(capacity: 12)
        // Direction: 4 bytes big-endian
        var dir = direction.bigEndian
        result.append(contentsOf: withUnsafeBytes(of: &dir) { Array($0) })
        // Sequence number: 8 bytes big-endian
        var seq = sequenceNumber.bigEndian
        result.append(contentsOf: withUnsafeBytes(of: &seq) { Array($0) })
        return result
    }
}
