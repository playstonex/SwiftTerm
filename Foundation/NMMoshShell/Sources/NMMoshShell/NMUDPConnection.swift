//
//  NMUDPConnection.swift
//  NMMoshShell
//
//  UDP networking layer for Mosh using Network.framework.
//

import Foundation
import Network

/// UDP connection manager for Mosh protocol.
///
/// Handles:
/// - UDP packet sending and receiving
/// - Network state changes (WiFi <-> Cellular)
/// - Automatic reconnection
public final class NMUDPConnection: @unchecked Sendable {

    // MARK: - Types

    public enum State: Sendable, Equatable {
        case idle
        case connecting
        case connected
        case disconnected
        case failed(Error)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.disconnected, .disconnected):
                return true
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "wiki.qaq.mosh.udp", qos: .userInitiated)
    private var _state: State = .idle
    private var connection: NWConnection?

    // AsyncStream for receiving data
    private var receiveContinuation: AsyncStream<Data>.Continuation?

    // MARK: - Public Properties

    public var state: State {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Connect to remote endpoint
    public func connect(
        host: String,
        port: UInt16
    ) async throws {
        // Cancel existing connection
        connection?.cancel()

        // Create endpoint
        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            updateState(.failed(UDPError.invalidEndpoint))
            throw UDPError.invalidEndpoint
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: portEndpoint)

        // Create UDP connection
        let newConnection = NWConnection(to: endpoint, using: .udp)

        // Configure state update handler
        newConnection.stateUpdateHandler = { [weak self] newState in
            self?.handleConnectionState(newState)
        }

        // Start connection
        newConnection.start(queue: queue)
        connection = newConnection

        updateState(.connecting)

        // Start receiving
        startReceiving()

        // Wait for connection
        try await waitForConnection()
    }

    /// Disconnect
    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        connection?.cancel()
        connection = nil
        updateState(.disconnected)
    }

    /// Send data
    public func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let connection = self.connection else {
                continuation.resume(throwing: UDPError.notConnected)
                return
            }

            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Receive data (streams)
    public func receiveStream() -> AsyncStream<Data> {
        return AsyncStream { continuation in
            lock.lock()

            // If we already have a continuation, terminate it
            if let existing = receiveContinuation {
                existing.finish()
            }

            self.receiveContinuation = continuation

            // Set up termination handler
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.lock.lock()
                self?.receiveContinuation = nil
                self?.lock.unlock()
            }

            lock.unlock()
        }
    }

    /// Receive data asynchronously
    public func receive() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            guard let connection = connection else {
                continuation.resume(throwing: UDPError.notConnected)
                return
            }

            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: UDPError.notConnected)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            updateState(.connected)
        case .failed(let error):
            updateState(.failed(error))
        case .waiting(let error):
            // Connection waiting - log it
            print("UDP connection waiting: \(error)")
        default:
            break
        }
    }

    private func startReceiving() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("UDP receive error: \(error)")
            }

            if let data = data, !data.isEmpty {
                self.notifyReceive(data)
            }

            if !isComplete {
                // Continue receiving
                self.startReceiving()
            }
        }
    }

    private func waitForConnection() async throws {
        // Wait up to 5 seconds for connection
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                throw UDPError.connectionTimeout
            }

            group.addTask { [weak self] in
                while true {
                    guard let self = self else { return }

                    if case .connected = self.state {
                        return
                    }

                    if case .failed(let error) = self.state {
                        throw error
                    }

                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
            }

            try await group.next()
            group.cancelAll()
        }
    }

    private func updateState(_ newState: State) {
        lock.lock()
        let oldState = _state
        _state = newState
        lock.unlock()

        // Notify state change if needed
        if case .connecting = oldState, case .connected = newState {
            // Connection successful
        }
    }

    private func notifyReceive(_ data: Data) {
        lock.lock()
        let continuation = receiveContinuation
        lock.unlock()

        continuation?.yield(data)
    }
}

// MARK: - Error Types

enum UDPError: Error {
    case invalidEndpoint
    case notConnected
    case connectionTimeout
}
