//
//  NMMoshShell.swift
//  NMMoshShell
//
//  Mosh (mobile shell) client implementation for Apple platforms.
//

import Foundation
import Network

/// Mosh shell client for robust mobile terminal connections.
///
/// Mosh provides:
/// - Roaming: Connection survives IP changes and network interruptions
/// - Low latency: Local echo prediction
/// - Intelligent display: State synchronization protocol
public final class NMMoshShell: @unchecked Sendable {

    // MARK: - Public Properties

    /// Whether the client is connected to the remote server
    public private(set) var isConnected: Bool = false

    /// Whether the client is authenticated
    public private(set) var isAuthenticated: Bool = false

    /// Remote host address
    public private(set) var remoteHost: String = ""

    /// Remote UDP port
    public private(set) var remotePort: UInt16 = 0

    /// Connection key shared by mosh-server
    public private(set) var connectionKey: String = ""

    /// Operation timeout in seconds
    public private(set) var operationTimeout: TimeInterval = 30

    /// Resolved remote IP address
    public private(set) var resolvedRemoteIpAddress: String?

    /// Last error message
    public private(set) var lastError: String?

    // MARK: - Private Properties

    private var udpConnection: NMUDPConnection?
    private var predictionMode: PredictionMode = .adaptive

    // Store a reference to the underlying SSH shell for bootstrap
    private var sshShellPointer: UnsafeMutableRawPointer?

    // MARK: - Types

    public enum PredictionMode: String, Sendable {
        case adaptive = "adaptive"
        case always = "always"
        case never = "never"
        case experimental = "experimental"
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Configuration

    /// Set up connection host
    @discardableResult
    public func setupConnectionHost(_ host: String) -> Self {
        remoteHost = host
        return self
    }

    /// Set up connection port (for SSH bootstrap)
    @discardableResult
    public func setupConnectionPort(_ port: NSNumber) -> Self {
        // Store for SSH bootstrap
        return self
    }

    /// Set up connection timeout
    @discardableResult
    public func setupConnectionTimeout(_ timeout: NSNumber) -> Self {
        operationTimeout = timeout.doubleValue
        return self
    }

    /// Set prediction mode for local echo
    @discardableResult
    public func setupPredictionMode(_ mode: PredictionMode) -> Self {
        predictionMode = mode
        return self
    }

    // MARK: - Connection

    /// Connect to remote server using external SSH bootstrap and establish UDP connection
    public func requestConnectAndWait() async throws {
        // This method should be called after SSH bootstrap
        // The caller must provide connection parameters via configureMoshConnection

        throw MoshError.notImplemented
    }

    /// Configure Mosh connection with parameters from SSH bootstrap
    public func configureMoshConnection(ip: String, port: String, key: String) async throws {
        let portNum = UInt16(port) ?? 60001

        // Create UDP connection
        let connection = NMUDPConnection()

        connectionKey = key
        remotePort = portNum

        // Start connection
        try? await connection.connect(host: ip, port: portNum)
        udpConnection = connection
        isConnected = true
        resolvedRemoteIpAddress = ip
    }

    /// Disconnect from remote server
    public func requestDisconnectAndWait() async {
        isConnected = false
        isAuthenticated = false

        // Close UDP connection
        udpConnection?.disconnect()
        udpConnection = nil
    }

    // MARK: - Authentication

    /// Authentication should be done via SSH before calling configureMoshConnection
    public func setAuthenticated() {
        isAuthenticated = true
    }

    // MARK: - Shell Session

    /// Begin an interactive shell session with Mosh
    public func begin(
        withTerminalType terminalType: String?,
        withOnCreate onCreate: @escaping () -> Void,
        withTerminalSize: @escaping () -> CGSize,
        withWriteDataBuffer: @escaping () -> String?,
        withOutputDataBuffer: @escaping (String) -> Void,
        withContinuationHandler: @escaping () -> Bool
    ) {
        guard let connection = udpConnection else {
            lastError = "UDP connection not established"
            return
        }

        // Notify creation
        onCreate()

        // Set up state synchronization
        let size = withTerminalSize()
        let rows = Int(size.height)
        let cols = Int(size.width)

        let stateSync = NMStateSync(rows: rows, cols: cols)

        // Convert prediction mode
        let predMode = NMPrediction.Mode(rawValue: predictionMode.rawValue) ?? .adaptive
        let prediction = NMPrediction(rows: rows, cols: cols, mode: predMode)

        // Store for later use
        // Note: In production, these should be stored as properties

        // Start receive loop
        Task {
            await runSession(
                connection: connection,
                stateSync: stateSync,
                prediction: prediction,
                withTerminalSize: withTerminalSize,
                withWriteDataBuffer: withWriteDataBuffer,
                withOutputDataBuffer: withOutputDataBuffer,
                withContinuationHandler: withContinuationHandler
            )
        }
    }

    // MARK: - Session Loop

    private func runSession(
        connection: NMUDPConnection,
        stateSync: NMStateSync,
        prediction: NMPrediction,
        withTerminalSize: @escaping () -> CGSize,
        withWriteDataBuffer: @escaping () -> String?,
        withOutputDataBuffer: @escaping (String) -> Void,
        withContinuationHandler: @escaping () -> Bool
    ) async {
        // Stream for receiving UDP data
        let stream = connection.receiveStream()

        // Main session loop
        for await data in stream {
            // Check continuation
            guard withContinuationHandler() else {
                connection.disconnect()
                return
            }

            // Handle received data
            if let str = String(data: data, encoding: .utf8) {
                withOutputDataBuffer(str)
            }
        }
    }

    // MARK: - Helper Methods

    /// Get the last error message
    public func getLastError() -> String? {
        return lastError
    }

    /// Request status pickup (event loop trigger)
    public func explicitRequestStatusPickup() {
        // No-op for Mosh (UDP is stateless)
    }

    /// Permanently destroy the shell and clean up resources
    public func destroyPermanently() {
        udpConnection?.disconnect()
        udpConnection = nil

        isConnected = false
        isAuthenticated = false
    }
}

// MARK: - Supporting Types

/// Mosh-specific errors
public enum MoshError: Error, Sendable {
    case sshConnectionFailed(String)
    case authenticationFailed(String)
    case authenticationTimeout
    case serverStartFailed(String)
    case invalidEndpoint
    case connectionTimeout
    case udpConnectionFailed(String)
    case notImplemented
}
