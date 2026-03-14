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

    // MARK: - Types

    public enum PredictionMode: String, Sendable {
        case adaptive = "adaptive"
        case always = "always"
        case never = "never"
        case experimental = "experimental"
    }

    private struct ConnectionConfiguration: Sendable {
        let host: String
        let port: UInt16
        let key: String
    }

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

    private let lock = NSLock()
    private var session: NMSession?
    private var sessionLoopTask: Task<Void, Never>?
    private var predictionMode: PredictionMode = .adaptive
    private var configuredBootstrapPort: UInt16 = 22
    private var connectionConfiguration: ConnectionConfiguration?
    private var outputHandler: ((String) -> Void)?

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
        configuredBootstrapPort = UInt16(truncating: port)
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

    /// Connect to remote server using external SSH bootstrap and establish a Mosh session.
    public func requestConnectAndWait() async throws {
        guard isAuthenticated else {
            throw MoshError.authenticationFailed("SSH bootstrap authentication is required before starting Mosh")
        }

        guard let configuration = lock.withLock({ connectionConfiguration }) else {
            throw MoshError.missingConnectionParameters
        }

        if lock.withLock({ isConnected && self.session != nil }) {
            return
        }

        let session = NMSession()
        session.debugLogging = false

        lock.withLock {
            self.session = session
            self.lastError = nil
            self.isConnected = false
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let continuationLock = NSLock()
            var resumed = false
            var timeoutTask: Task<Void, Never>?

            func finish(_ result: Result<Void, Error>) {
                continuationLock.withLock {
                    guard !resumed else { return }
                    resumed = true
                    timeoutTask?.cancel()
                    continuation.resume(with: result)
                }
            }

            timeoutTask = Task {
                let timeoutNanoseconds = UInt64(max(self.operationTimeout, 1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                finish(.failure(MoshError.connectionTimeout))
                session.disconnect()
            }

            session.connect(
                host: configuration.host,
                port: configuration.port,
                key: configuration.key,
                stateHandler: { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .connecting:
                        break
                    case .connected:
                        self.lock.withLock {
                            self.isConnected = true
                            self.lastError = nil
                        }
                        finish(.success(()))
                    case .disconnected:
                        self.lock.withLock {
                            self.isConnected = false
                        }
                        finish(.failure(MoshError.udpConnectionFailed("Mosh session disconnected before becoming ready")))
                    case .failed(let error):
                        self.lock.withLock {
                            self.isConnected = false
                            self.lastError = String(describing: error)
                            self.session = nil
                        }
                        finish(.failure(self.mapConnectionError(error)))
                    }
                },
                receiveHandler: { [weak self] output in
                    self?.forwardSessionOutput(output)
                }
            )
        }
    }

    /// Configure Mosh connection with parameters from SSH bootstrap.
    public func configureMoshConnection(ip: String, port: String, key: String) async throws {
        guard let portNum = UInt16(port) else {
            throw MoshError.invalidEndpoint
        }

        do {
            _ = try NMCrypto(keyString: key)
        } catch {
            lastError = String(describing: error)
            throw MoshError.udpConnectionFailed("Invalid Mosh key: \(error)")
        }

        let configuration = ConnectionConfiguration(host: ip, port: portNum, key: key)
        lock.withLock {
            connectionConfiguration = configuration
            remoteHost = ip
            remotePort = portNum
            connectionKey = key
            resolvedRemoteIpAddress = ip
            isConnected = false
            lastError = nil
        }
    }

    /// Disconnect from remote server
    public func requestDisconnectAndWait() async {
        let sessionToDisconnect = lock.withLock { () -> NMSession? in
            let activeSession = session
            sessionLoopTask?.cancel()
            sessionLoopTask = nil
            session = nil
            isConnected = false
            isAuthenticated = false
            outputHandler = nil
            return activeSession
        }

        sessionToDisconnect?.disconnect()
    }

    // MARK: - Authentication

    /// Authentication should be done via SSH before calling configureMoshConnection.
    public func setAuthenticated() {
        isAuthenticated = true
    }

    // MARK: - Shell Session

    /// Begin an interactive shell session with Mosh.
    public func begin(
        withTerminalType terminalType: String?,
        withOnCreate onCreate: @escaping () -> Void,
        withTerminalSize: @escaping () -> CGSize,
        withWriteDataBuffer: @escaping () -> String?,
        withOutputDataBuffer: @escaping (String) -> Void,
        withContinuationHandler: @escaping () -> Bool
    ) {
        guard let session = lock.withLock({ self.session }), isConnected else {
            lastError = "Mosh session not connected"
            return
        }

        lock.withLock {
            outputHandler = withOutputDataBuffer
            sessionLoopTask?.cancel()
        }

        onCreate()

        let prediction = NMPrediction(
            rows: max(Int(withTerminalSize().height), 1),
            cols: max(Int(withTerminalSize().width), 1),
            mode: NMPrediction.Mode(rawValue: predictionMode.rawValue) ?? .adaptive
        )

        let sessionTask = Task { [weak self] in
            var lastSize = CGSize(width: 0, height: 0)

            while withContinuationHandler() {
                let requestedSize = withTerminalSize()
                if requestedSize.width != lastSize.width || requestedSize.height != lastSize.height {
                    lastSize = requestedSize
                    let rows = UInt16(max(Int(requestedSize.height), 1))
                    let cols = UInt16(max(Int(requestedSize.width), 1))
                    prediction.resize(rows: Int(rows), cols: Int(cols))
                    session.sendResize(rows: rows, cols: cols)
                }

                if let pendingInput = withWriteDataBuffer(), !pendingInput.isEmpty {
                    _ = prediction.predict(input: pendingInput)
                    session.sendString(pendingInput)
                }

                try? await Task.sleep(nanoseconds: 20_000_000)
            }

            await self?.requestDisconnectAndWait()
        }

        lock.withLock {
            sessionLoopTask = sessionTask
        }
    }

    // MARK: - Helper Methods

    /// Get the last error message
    public func getLastError() -> String? {
        lastError
    }

    /// Request status pickup (event loop trigger)
    public func explicitRequestStatusPickup() {
        // The polling loop in `begin` is responsible for draining input and size updates.
    }

    /// Permanently destroy the shell and clean up resources
    public func destroyPermanently() {
        let sessionToDisconnect = lock.withLock { () -> NMSession? in
            let activeSession = session
            sessionLoopTask?.cancel()
            sessionLoopTask = nil
            session = nil
            outputHandler = nil
            isConnected = false
            isAuthenticated = false
            return activeSession
        }

        sessionToDisconnect?.disconnect()
    }

    private func mapConnectionError(_ error: Error) -> MoshError {
        if let moshError = error as? MoshError {
            return moshError
        }

        switch error {
        case let udpError as UDPError:
            switch udpError {
            case .invalidEndpoint:
                return .invalidEndpoint
            case .connectionTimeout:
                return .connectionTimeout
            case .notConnected:
                return .udpConnectionFailed("UDP socket is not connected")
            }
        default:
            return .udpConnectionFailed(String(describing: error))
        }
    }

    private func forwardSessionOutput(_ data: Data) {
        let text = decodeMoshText(data)
        let handler = lock.withLock { outputHandler }
        handler?(text)
    }

    private func decodeMoshText(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        return String(decoding: data, as: UTF8.self)
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
    case missingConnectionParameters
    case notImplemented
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
