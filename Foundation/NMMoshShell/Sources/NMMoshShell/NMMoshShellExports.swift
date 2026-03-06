//
//  NMMoshShellExports.swift
//  NMMoshShell
//
//  Public API exports.
//

@_exported import Foundation
@_exported import Network

// Re-export main types
public typealias NMShell = NMMoshShell
public typealias NMUDP = NMUDPConnection
public typealias NMState = NMStateSync
public typealias NMPredict = NMPrediction
public typealias NMCryptoSession = NMSession
public typealias NMEncryption = NMCrypto

// Version information
public struct NMMoshVersion {
    public static let major = 0
    public static let minor = 2
    public static let patch = 1

    public static let string = "\(major).\(minor).\(patch)"
}
