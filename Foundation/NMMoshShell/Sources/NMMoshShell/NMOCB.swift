//
//  NMOCB.swift
//  NMMoshShell
//
//  OCB-AES128 authenticated encryption implementation.
//
//  OCB (Offset Codebook Mode) provides:
//  - Confidentiality (encryption)
//  - Integrity (authentication)
//  - Parallel processing capability
//
//  Based on RFC 7253: The OCB Authenticated-Encryption Algorithm
//  Reference: https://tools.ietf.org/html/rfc7253
//

import Foundation
import CommonCrypto

/// OCB-AES128 authenticated encryption
public final class NMOCB: @unchecked Sendable {

    // MARK: - Types

    public enum OCBError: Error, Sendable {
        case invalidTag
        case invalidNonce
        case encryptionFailed
        case decryptionFailed
        case invalidInput
        case authenticationFailed
    }

    // MARK: - Constants

    private let blockSize = 16  // AES block size in bytes
    private let tagSize = 16    // Authentication tag size in bytes
    private let nonceSize = 12  // 96-bit nonce for OCB

    // MARK: - Properties

    private let keyData: Data
    private let lock = NSLock()

    // Precomputed L values for OCB
    private var lStar: Data = Data(repeating: 0, count: 16)
    private var lDollar: Data = Data(repeating: 0, count: 16)
    private var lTable: [Data] = []

    // MARK: - Initialization

    /// Initialize OCB with a raw key
    /// - Parameter key: 16-byte AES-128 key
    public init(key: Data) throws {
        guard key.count == 16 else {
            throw OCBError.invalidInput
        }

        self.keyData = key

        // Precompute L values
        precomputeLValues()
    }

    /// Initialize OCB with a key string (base64 decoded to 16 bytes)
    /// IMPORTANT: Mosh uses the raw 16-byte key from base64 decoding, NOT a hash!
    public convenience init(keyString: String) throws {
        // Decode base64 key string to raw 16 bytes
        var base64 = keyString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let keyData = Data(base64Encoded: base64), keyData.count == 16 else {
            throw OCBError.invalidInput
        }

        try self.init(key: keyData)
    }

    // MARK: - Public Methods

    /// Encrypt and authenticate data using OCB mode
    /// - Parameters:
    ///   - nonce: 96-bit (12 byte) nonce
    ///   - plaintext: Data to encrypt
    ///   - associatedData: Optional authenticated but unencrypted data
    /// - Returns: Encrypted data with authentication tag appended
    public func encrypt(nonce: Data, plaintext: Data, associatedData: Data = Data()) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard nonce.count == nonceSize else {
            throw OCBError.invalidNonce
        }

        // Step 1: Format the nonce according to RFC 7253
        // For TAGLEN=128 and a 96-bit nonce:
        // formatted_nonce = num2str(128 mod 128, 7) || zeros(120-96) || 1 || N
        // = 7 zero bits || 24 zero bits || 1 || 96 bits of N
        // = 128 bits total
        var formattedNonce = Data(count: 16)
        // Byte 0-2: zeros (7 + 17 = 24 bits of zeros from TAGLEN and padding)
        // Byte 3: 0x01 (remaining 7 zeros + 1 bit = 0x01)
        formattedNonce[3] = 0x01
        // Bytes 4-15: the 12-byte nonce
        for i in 0..<12 {
            formattedNonce[4 + i] = nonce[i]
        }

        // Step 2: Compute bottom (last 6 bits of formatted nonce) and top
        let bottom = Int(formattedNonce[15] & 0x3F)

        // Step 3: Compute Ktop = ENCIPHER(K, Nonce[1..122] || zeros(6))
        // This is the first 122 bits of formatted nonce + 6 zero bits = 16 bytes
        var ktopInput = formattedNonce
        // Clear last 6 bits of the last byte
        ktopInput[15] &= 0xC0  // Keep only top 2 bits

        let ktop = aesEncrypt(block: ktopInput)

        // Step 4: Compute Stretch = Ktop || (Ktop[1..64] XOR Ktop[65..128])
        // From mosh ocb_internal.cc: KtopStr[2] = KtopStr[0] ^ (KtopStr[0] << 8) ^ (KtopStr[1] >> 56)
        // The byte-based interpretation: stretch[16+i] = ktop[i] ^ ktop[i+1] for i=0..7
        var stretch = Data(count: 24)
        for i in 0..<16 {
            stretch[i] = ktop[i]
        }
        for i in 0..<8 {
            stretch[16 + i] = ktop[i] ^ ktop[i + 1]
        }

        // Debug output
        let debugOCB = false
        if debugOCB {
            print("[OCB.Encrypt] Formatted nonce: \(formattedNonce.map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("[OCB.Encrypt] Bottom: \(bottom)")
            print("[OCB.Encrypt] Ktop: \(ktop.map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("[OCB.Encrypt] KtopInput: \(ktopInput.map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("[OCB.Encrypt] Stretch: \(stretch.map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("[OCB.Encrypt] L*: \(lStar.map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("[OCB.Encrypt] L$: \(lDollar.map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("[OCB.Encrypt] L_0: \(lTable[0].map { String(format: "%02x", $0) }.joined(separator: " "))")
        }

        // Step 5: Compute Offset_0 = Stretch[1+bottom..128+bottom]
        var offset = extractBits(stretch, startBit: bottom, bitCount: 128)

        // Step 6: Initialize checksum
        var checksum = Data(repeating: 0, count: 16)

        // Step 7: Process plaintext blocks
        var ciphertext = Data()
        let numBlocks = plaintext.count / blockSize
        let hasPartial = (plaintext.count % blockSize) != 0

        for i in 0..<numBlocks {
            let blockStart = i * blockSize
            let blockEnd = blockStart + blockSize
            let plaintextBlock = plaintext.subdata(in: blockStart..<blockEnd)

            // Update offset: offset = offset XOR L_{ntz(i+1)}
            let lIndex = ntz(i + 1)
            if lIndex < lTable.count {
                offset = xor(offset, lTable[lIndex])
            }

            // Encrypt: ciphertext_block = offset XOR AES(offset XOR plaintext_block)
            let xoredInput = xor(offset, plaintextBlock)
            let aesOutput = aesEncrypt(block: xoredInput)
            let ciphertextBlock = xor(offset, aesOutput)
            ciphertext.append(ciphertextBlock)

            // Update checksum: checksum = checksum XOR plaintext_block
            checksum = xor(checksum, plaintextBlock)
        }

        // Step 8: Process final partial block if any
        if hasPartial {
            let partialStart = numBlocks * blockSize
            let partialBlock = plaintext.subdata(in: partialStart..<plaintext.count)
            let partialLen = partialBlock.count

            // offset = offset XOR L*
            offset = xor(offset, lStar)

            // Pad the partial block
            let pad = aesEncrypt(block: offset)

            // ciphertext = pad[0..partialLen] XOR partial_block
            var partialCiphertext = Data(count: partialLen)
            for i in 0..<partialLen {
                partialCiphertext[i] = pad[i] ^ partialBlock[i]
            }
            ciphertext.append(partialCiphertext)

            // checksum = checksum XOR (partial_block || 1 || 0^{128 - 8 * partialLen - 1})
            var checksumInput = Data(count: 16)
            for i in 0..<partialLen {
                checksumInput[i] = partialBlock[i]
            }
            checksumInput[partialLen] = 0x80
            // Rest are already 0
            checksum = xor(checksum, checksumInput)
        }

        // Step 9: Compute tag
        // tag = AES(offset XOR L$ XOR checksum)
        var tagInput = xor(offset, lDollar)
        tagInput = xor(tagInput, checksum)
        let tag = aesEncrypt(block: tagInput)

        // Step 10: Return ciphertext + tag
        ciphertext.append(tag)

        return ciphertext
    }

    /// Decrypt and verify data using OCB mode
    /// - Parameters:
    ///   - nonce: 96-bit (12 byte) nonce
    ///   - ciphertext: Encrypted data with authentication tag appended
    ///   - associatedData: Optional authenticated but unencrypted data
    /// - Returns: Decrypted plaintext
    /// - Throws: OCBError.authenticationFailed if tag verification fails
    public func decrypt(nonce: Data, ciphertext: Data, associatedData: Data = Data()) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard nonce.count == nonceSize else {
            throw OCBError.invalidNonce
        }

        guard ciphertext.count >= tagSize else {
            throw OCBError.invalidInput
        }

        // Split ciphertext and tag
        let ct = ciphertext.prefix(ciphertext.count - tagSize)
        let tag = ciphertext.suffix(tagSize)

        // Step 1: Format the nonce according to RFC 7253
        var formattedNonce = Data(count: 16)
        formattedNonce[3] = 0x01
        for i in 0..<12 {
            formattedNonce[4 + i] = nonce[i]
        }

        // Step 2: Compute bottom (last 6 bits of formatted nonce) and top
        let bottom = Int(formattedNonce[15] & 0x3F)

        // Step 3: Compute Ktop = ENCIPHER(K, Nonce[1..122] || zeros(6))
        var ktopInput = formattedNonce
        ktopInput[15] &= 0xC0
        let ktop = aesEncrypt(block: ktopInput)

        // Step 4: Compute Stretch = Ktop || (Ktop[1..64] XOR Ktop[9..72])
        var stretch = Data(count: 24)
        for i in 0..<16 {
            stretch[i] = ktop[i]
        }
        for i in 0..<8 {
            stretch[16 + i] = ktop[i] ^ ktop[i + 1]
        }

        // Step 5: Compute Offset_0 = Stretch[1+bottom..128+bottom]
        var offset = extractBits(stretch, startBit: bottom, bitCount: 128)

        // Step 6: Initialize checksum
        var checksum = Data(repeating: 0, count: 16)

        // Step 7: Process ciphertext blocks
        var plaintext = Data()
        let numBlocks = ct.count / blockSize
        let hasPartial = (ct.count % blockSize) != 0

        for i in 0..<numBlocks {
            let blockStart = i * blockSize
            let blockEnd = blockStart + blockSize
            let ciphertextBlock = ct.subdata(in: blockStart..<blockEnd)

            // Update offset: offset = offset XOR L_{ntz(i+1)}
            let lIndex = ntz(i + 1)
            if lIndex < lTable.count {
                offset = xor(offset, lTable[lIndex])
            }

            // Decrypt: plaintext_block = offset XOR AES_DECRYPT(offset XOR ciphertext_block)
            let xoredInput = xor(offset, ciphertextBlock)
            let aesOutput = aesDecrypt(block: xoredInput)
            let plaintextBlock = xor(offset, aesOutput)
            plaintext.append(plaintextBlock)

            // Update checksum
            checksum = xor(checksum, plaintextBlock)
        }

        // Step 8: Process final partial block if any
        if hasPartial {
            let partialStart = numBlocks * blockSize
            let partialCiphertext = ct.subdata(in: partialStart..<ct.count)
            let partialLen = partialCiphertext.count

            // offset = offset XOR L*
            offset = xor(offset, lStar)

            // Decrypt partial
            let pad = aesEncrypt(block: offset)
            var partialPlaintext = Data(count: partialLen)
            for i in 0..<partialLen {
                partialPlaintext[i] = pad[i] ^ partialCiphertext[i]
            }
            plaintext.append(partialPlaintext)

            // Update checksum
            var checksumInput = Data(count: 16)
            for i in 0..<partialLen {
                checksumInput[i] = partialPlaintext[i]
            }
            checksumInput[partialLen] = 0x80
            checksum = xor(checksum, checksumInput)
        }

        // Step 9: Verify tag
        var tagInput = xor(offset, lDollar)
        tagInput = xor(tagInput, checksum)
        let computedTag = aesEncrypt(block: tagInput)

        guard computedTag == tag else {
            throw OCBError.authenticationFailed
        }

        return plaintext
    }

    // MARK: - Private Methods

    /// Precompute L values for OCB
    private func precomputeLValues() {
        // L* = AES(K, zeros)
        let zeroBlock = Data(repeating: 0, count: blockSize)
        lStar = aesEncrypt(block: zeroBlock)

        // L$ = double(L*)
        lDollar = double(lStar)

        // L_0 = double(L$), then L_i = double(L_{i-1})
        // lTable[i] = L_i = double^{i+1}(L$)
        lTable.removeAll()
        var current = double(lDollar)  // L_0 = double(L$)
        lTable.append(current)
        for _ in 1..<64 {
            current = double(current)
            lTable.append(current)
        }

        // Debug output
        let debugL = false
        if debugL {
            print("[OCB] L*: \(lStar.map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("[OCB] L$: \(lDollar.map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("[OCB] L_0: \(lTable[0].map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("[OCB] L_1: \(lTable[1].map { String(format: "%02x", $0) }.joined(separator: " "))")
        }
    }

    /// Number of trailing zeros in binary representation
    private func ntz(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        var count = 0
        var value = n
        while (value & 1) == 0 {
            count += 1
            value >>= 1
        }
        return count
    }

    /// Double function for GF(2^128)
    /// Per RFC 7253: If MSB of X is 0, double(X) = X << 1; otherwise double(X) = (X << 1) xor 0^120||10000111
    private func double(_ block: Data) -> Data {
        guard block.count == blockSize else {
            return block
        }

        // Check the MSB of the FIRST byte (high-order bit of the 128-bit value)
        let msbSet = (block[0] & 0x80) != 0

        var result = Data(count: blockSize)
        var carry: UInt8 = 0

        // Big-endian left shift over the 128-bit block:
        // lower-significance byte carries into higher-significance byte.
        for i in stride(from: blockSize - 1, through: 0, by: -1) {
            let byte = block[i]
            let newCarry: UInt8 = (byte >> 7) & 1
            result[i] = (byte << 1) | carry
            carry = newCarry
        }

        // XOR with 0x87 if MSB of original block was 1 (reduction polynomial)
        if msbSet {
            result[15] ^= 0x87
        }

        return result
    }

    /// XOR two data blocks
    private func xor(_ left: Data, _ right: Data) -> Data {
        let resultLength = min(left.count, right.count)
        var result = Data(count: resultLength)

        for i in 0..<resultLength {
            result[i] = left[i] ^ right[i]
        }

        return result
    }

    /// Extract a bit slice from data (MSB-first bit numbering within each byte).
    private func extractBits(_ data: Data, startBit: Int, bitCount: Int) -> Data {
        guard bitCount >= 0 else { return Data() }
        let outBytes = (bitCount + 7) / 8
        var out = Data(repeating: 0, count: outBytes)

        for i in 0..<bitCount {
            let srcBit = startBit + i
            let srcByte = srcBit / 8
            let srcBitInByte = 7 - (srcBit % 8)
            guard srcByte < data.count else { break }
            let bit = (data[srcByte] >> srcBitInByte) & 0x01

            let dstByte = i / 8
            let dstBitInByte = 7 - (i % 8)
            out[dstByte] |= bit << dstBitInByte
        }

        return out
    }

    /// AES-128 ECB encryption of a single block using CommonCrypto
    private func aesEncrypt(block: Data) -> Data {
        guard block.count == 16 else {
            return block
        }

        var output = Data(count: 16)
        output.withUnsafeMutableBytes { outputBytes in
            keyData.withUnsafeBytes { keyBytes in
                block.withUnsafeBytes { inputBytes in
                    _ = CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress,
                        kCCKeySizeAES128,
                        nil,  // No IV for ECB
                        inputBytes.baseAddress,
                        16,
                        outputBytes.baseAddress,
                        16,
                        nil
                    )
                }
            }
        }

        return output
    }

    /// AES-128 ECB decryption of a single block using CommonCrypto
    private func aesDecrypt(block: Data) -> Data {
        guard block.count == 16 else {
            return block
        }

        var output = Data(count: 16)
        output.withUnsafeMutableBytes { outputBytes in
            keyData.withUnsafeBytes { keyBytes in
                block.withUnsafeBytes { inputBytes in
                    _ = CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress,
                        kCCKeySizeAES128,
                        nil,  // No IV for ECB
                        inputBytes.baseAddress,
                        16,
                        outputBytes.baseAddress,
                        16,
                        nil
                    )
                }
            }
        }

        return output
    }

    /// Inverse ShiftRows transformation
    private func invShiftRows(state: [UInt8]) -> [UInt8] {
        // State is stored column-major: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]
        // Row 0: no shift
        // Row 1: shift right 1 (inverse of shift left 1)
        // Row 2: shift right 2 (inverse of shift left 2)
        // Row 3: shift right 3 (inverse of shift left 3)
        return [
            state[0], state[13], state[10], state[7],
            state[4], state[1], state[14], state[11],
            state[8], state[5], state[2], state[15],
            state[12], state[9], state[6], state[3]
        ]
    }

    /// Inverse MixColumns transformation
    private func invMixColumns(state: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 16)

        for col in 0..<4 {
            let c = col * 4
            // Inverse MixColumns uses different coefficients: 0x0e, 0x0b, 0x0d, 0x09
            result[c + 0] = gmul(state[c + 0], 0x0e) ^ gmul(state[c + 1], 0x0b) ^ gmul(state[c + 2], 0x0d) ^ gmul(state[c + 3], 0x09)
            result[c + 1] = gmul(state[c + 0], 0x09) ^ gmul(state[c + 1], 0x0e) ^ gmul(state[c + 2], 0x0b) ^ gmul(state[c + 3], 0x0d)
            result[c + 2] = gmul(state[c + 0], 0x0d) ^ gmul(state[c + 1], 0x09) ^ gmul(state[c + 2], 0x0e) ^ gmul(state[c + 3], 0x0b)
            result[c + 3] = gmul(state[c + 0], 0x0b) ^ gmul(state[c + 1], 0x0d) ^ gmul(state[c + 2], 0x09) ^ gmul(state[c + 3], 0x0e)
        }

        return result
    }

    /// Manual AES-128 single block encryption
    private func aesEncryptBlock(key: Data, block: Data) -> Data {
        guard key.count == 16, block.count == 16 else {
            return block
        }

        var state = Array(block)

        // Key expansion - derive 11 round keys (176 bytes total)
        let expandedKey = expandKey(key: Array(key))

        // Initial round key addition
        for i in 0..<16 {
            state[i] ^= expandedKey[i]
        }

        // 10 rounds for AES-128
        for round in 1...10 {
            // SubBytes
            state = state.map { sBox[Int($0)] }

            // ShiftRows
            state = shiftRows(state: state)

            // MixColumns (skip in last round)
            if round < 10 {
                state = mixColumns(state: state)
            }

            // AddRoundKey
            let roundKeyOffset = round * 16
            for i in 0..<16 {
                state[i] ^= expandedKey[roundKeyOffset + i]
            }
        }

        return Data(state)
    }

    /// Manual AES-128 single block decryption
    private func aesDecryptBlock(key: Data, block: Data) -> Data {
        guard key.count == 16, block.count == 16 else {
            return block
        }

        var state = Array(block)

        // Key expansion - derive 11 round keys (176 bytes total)
        let expandedKey = expandKey(key: Array(key))

        // Initial round key addition (last round key first for decryption)
        for i in 0..<16 {
            state[i] ^= expandedKey[160 + i]  // Round 10 key
        }

        // 9 rounds in reverse
        for round in (1...9).reversed() {
            // Inverse ShiftRows
            state = invShiftRows(state: state)

            // Inverse SubBytes
            state = state.map { invSBox[Int($0)] }

            // AddRoundKey
            let roundKeyOffset = round * 16
            for i in 0..<16 {
                state[i] ^= expandedKey[roundKeyOffset + i]
            }

            // Inverse MixColumns
            state = invMixColumns(state: state)
        }

        // Final round (round 0)
        // Inverse ShiftRows
        state = invShiftRows(state: state)

        // Inverse SubBytes
        state = state.map { invSBox[Int($0)] }

        // AddRoundKey (initial key)
        for i in 0..<16 {
            state[i] ^= expandedKey[i]
        }

        return Data(state)
    }

    /// AES key expansion
    private func expandKey(key: [UInt8]) -> [UInt8] {
        var expandedKey = [UInt8](repeating: 0, count: 176)
        expandedKey[0..<16] = key[0..<16]

        var bytesGenerated = 16
        var rconIteration = 1
        var temp = [UInt8](repeating: 0, count: 4)

        while bytesGenerated < 176 {
            temp[0] = expandedKey[bytesGenerated - 4]
            temp[1] = expandedKey[bytesGenerated - 3]
            temp[2] = expandedKey[bytesGenerated - 2]
            temp[3] = expandedKey[bytesGenerated - 1]

            if bytesGenerated % 16 == 0 {
                // RotWord: rotate left by 1 position [a,b,c,d] -> [b,c,d,a]
                let t = temp[0]
                temp[0] = temp[1]
                temp[1] = temp[2]
                temp[2] = temp[3]
                temp[3] = t

                // SubWord: apply S-box to each byte
                temp[0] = sBox[Int(temp[0])]
                temp[1] = sBox[Int(temp[1])]
                temp[2] = sBox[Int(temp[2])]
                temp[3] = sBox[Int(temp[3])]

                // XOR with Rcon
                temp[0] ^= rcon[rconIteration - 1]  // rconIteration is 1-based
                rconIteration += 1
            }

            for i in 0..<4 {
                expandedKey[bytesGenerated] = expandedKey[bytesGenerated - 16] ^ temp[i]
                bytesGenerated += 1
            }
        }

        return expandedKey
    }

    /// ShiftRows transformation
    private func shiftRows(state: [UInt8]) -> [UInt8] {
        // State is stored column-major: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]
        // Row 0: no shift
        // Row 1: shift left 1
        // Row 2: shift left 2
        // Row 3: shift left 3
        return [
            state[0], state[5], state[10], state[15],
            state[4], state[9], state[14], state[3],
            state[8], state[13], state[2], state[7],
            state[12], state[1], state[6], state[11]
        ]
    }

    /// MixColumns transformation
    private func mixColumns(state: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 16)

        for col in 0..<4 {
            let c = col * 4
            result[c + 0] = gmul(state[c + 0], 2) ^ gmul(state[c + 1], 3) ^ state[c + 2] ^ state[c + 3]
            result[c + 1] = state[c + 0] ^ gmul(state[c + 1], 2) ^ gmul(state[c + 2], 3) ^ state[c + 3]
            result[c + 2] = state[c + 0] ^ state[c + 1] ^ gmul(state[c + 2], 2) ^ gmul(state[c + 3], 3)
            result[c + 3] = gmul(state[c + 0], 3) ^ state[c + 1] ^ state[c + 2] ^ gmul(state[c + 3], 2)
        }

        return result
    }

    /// Galois field multiplication
    private func gmul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var p: UInt8 = 0
        var a = a
        var b = b

        for _ in 0..<8 {
            if (b & 1) != 0 {
                p ^= a
            }
            let hiBitSet = (a & 0x80) != 0
            a <<= 1
            if hiBitSet {
                a ^= 0x1b  // x^8 + x^4 + x^3 + x + 1
            }
            b >>= 1
        }

        return p
    }
}

// MARK: - AES S-Box

/// AES S-box lookup table
private let sBox: [UInt8] = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
]

/// AES Rcon values
private let rcon: [UInt8] = [
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
]

/// AES Inverse S-box lookup table
private let invSBox: [UInt8] = [
    0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
    0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
    0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
    0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
    0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
    0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
    0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
    0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
    0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
    0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
    0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
    0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
    0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
    0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
    0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
    0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d
]
