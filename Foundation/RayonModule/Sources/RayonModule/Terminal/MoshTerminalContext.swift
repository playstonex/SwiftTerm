//
//  MoshTerminalContext.swift
//  RayonModule
//
//  Mosh terminal session context.
//

import Foundation
import NSRemoteShell
import SwiftTerminal

#if canImport(NMMoshShell)
import NMMoshShell
#endif

/// Mosh terminal session context for managing persistent mobile connections.
@MainActor
public final class MoshTerminalContext: ObservableObject, Identifiable {

    public let id: UUID = UUID()
    public let machine: RDMachine

    private var sshConnection: NSRemoteShell

    // MARK: - Published State

    @Published public private(set) var navigationTitle: String = ""
    @Published public var navigationSubtitle: String = ""

    @Published public var interfaceToken: UUID = UUID()
    @Published public var interfaceDisabled: Bool = false

    // MARK: - Terminal State

    public private(set) var closed: Bool = false

    private var _continueDecision: Bool = true
    public var continueDecision: Bool {
        get { _continueDecision }
        set {
            _continueDecision = newValue
            interfaceDisabled = !newValue
        }
    }

    private var _terminalSize: CGSize = CGSize(width: 80, height: 40)
    public var terminalSize: CGSize {
        get { _terminalSize }
        set {
            _terminalSize = newValue
            sshConnection.explicitRequestStatusPickup()
        }
    }

    // MARK: - I/O Buffers

    private var _dataBuffer: String = ""
    private let bufferLock = NSLock()
    private var outputHistory: String = ""
    private let maxHistorySize = 50000
    private let historyLock = NSLock()

    // MARK: - Terminal Interface

    public let termInterface: STerminalView = STerminalView()

    // MARK: - Initialization

    public init(machine: RDMachine) {
        self.machine = machine
        self.sshConnection = NSRemoteShell()
        self.navigationTitle = machine.shortDescription(withComment: false) + " [Mosh]"

        Task {
            await processBootstrap()
        }
    }

    // MARK: - Bootstrap

    private func processBootstrap() async {
        defer {
            Task { @MainActor in
                processShutdown(exitFromShell: true)
            }
        }

        putInformation("[*] Creating Mosh Connection")
        continueDecision = true

        // Setup terminal callbacks
        setupTerminalCallbacks()

        // Setup SSH connection for bootstrap
        setupSSHConnection()

        // Connect via SSH first
        putInformation("[*] Establishing SSH bootstrap")
        sshConnection.requestConnectAndWait()

        guard sshConnection.isConnected else {
            putInformation("Unable to connect for \(machine.remoteAddress):\(machine.remotePort)")
            return
        }

        // Authenticate
        putInformation("[*] Authenticating")
        do {
            try await authenticate()
        } catch {
            putInformation("Failed to authenticate: \(error.localizedDescription)")
            return
        }

        putInformation("[*] Starting Mosh session")

        // Update machine banner
        updateMachineBanner()

        // Try to start Mosh server via SSH
        if let moshParams = await startMoshServer() {
            putInformation("[*] Mosh server started on \(moshParams.ip):\(moshParams.port)")

            #if canImport(NMMoshShell)
            // Configure Mosh client with UDP connection
            // TODO: Implement full Mosh protocol
            putInformation("[i] Mosh UDP connection - implementing")
            #endif
        }

        // For now, fall back to SSH shell
        putInformation("[i] Falling back to SSH shell (Mosh protocol in progress)")
        beginSSHShell()
    }

    private func setupTerminalCallbacks() {
        termInterface
            .setupBellChain {
                // Terminal bell
            }
            .setupBufferChain { [weak self] buffer in
                self?.insertBuffer(buffer)
            }
            .setupTitleChain { [weak self] str in
                self?.navigationSubtitle = str
            }
            .setupSizeChain { [weak self] size in
                self?.terminalSize = size
            }
    }

    private func setupSSHConnection() {
        sshConnection
            .setupConnectionHost(machine.remoteAddress)
            .setupConnectionPort(NSNumber(value: Int(machine.remotePort) ?? 22))
            .setupConnectionTimeout(NSNumber(value: 30))
    }

    private func authenticate() async throws {
        if let rid = machine.associatedIdentity,
           let uid = UUID(uuidString: rid) {

            let identity = RayonStore.shared.identityGroup[uid]
            guard !identity.username.isEmpty else {
                putInformation("Malformed identity data")
                throw MoshContextError.authenticationFailed("Invalid identity")
            }

            // Try public key authentication first
            let pubKey: String? = identity.publicKey.isEmpty ? nil : identity.publicKey
            let privKey = identity.privateKey
            let password: String? = identity.password.isEmpty ? nil : identity.password

            if let pubKey = pubKey {
                sshConnection.authenticate(
                    with: identity.username,
                    andPublicKey: pubKey,
                    andPrivateKey: privKey,
                    andPassword: password
                )
            } else if let pwd = password {
                sshConnection.authenticate(with: identity.username, andPassword: pwd)
            }

            // Wait for auth
            try await waitForAuth()

        } else {
            // Try auto-authentication
            for identity in RayonStore.shared.identityGroupForAutoAuth {
                putInformation("[i] trying to authenticate with \(identity.shortDescription())")

                let pubKey: String? = identity.publicKey.isEmpty ? nil : identity.publicKey
                let privKey = identity.privateKey
                let password: String? = identity.password.isEmpty ? nil : identity.password

                if let pubKey = pubKey {
                    sshConnection.authenticate(
                        with: identity.username,
                        andPublicKey: pubKey,
                        andPrivateKey: privKey,
                        andPassword: password
                    )
                } else if let pwd = password {
                    sshConnection.authenticate(with: identity.username, andPassword: pwd)
                }

                if sshConnection.isAuthenticated {
                    break
                }
            }
        }

        guard sshConnection.isConnected, sshConnection.isAuthenticated else {
            throw MoshContextError.authenticationFailed("Authentication failed")
        }
    }

    private func waitForAuth() async throws {
        let timeout: TimeInterval = 30
        let startTime = Date()

        while !sshConnection.isAuthenticated {
            if Date().timeIntervalSince(startTime) > timeout {
                throw MoshContextError.authenticationTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }

    private func updateMachineBanner() {
        var machine = RayonStore.shared.machineGroup[self.machine.id]
        if machine.isNotPlaceholder() {
            machine.lastBanner = sshConnection.remoteBanner ?? "No Banner"
            RayonStore.shared.machineGroup[self.machine.id] = machine
        }
    }

    private struct MoshServerParams {
        let ip: String
        let port: String
        let key: String
    }

    private func startMoshServer() async -> MoshServerParams? {
        let colors = "256"
        let serverCmd = [
            "mosh-server", "new", "-s", "-c", colors,
            "-l", "LC_ALL=en_US.UTF-8"
        ].joined(separator: " ")

        var capturedOutput = ""
        let timeout = NSNumber(value: 10)

        sshConnection.beginExecute(
            withCommand: serverCmd,
            withTimeout: timeout,
            withOnCreate: {},
            withOutput: { output in
                capturedOutput += output
            },
            withContinuationHandler: {
                // Parse output for connection parameters
                if let params = self.parseMoshServerOutput(capturedOutput) {
                    return true
                }
                return true
            }
        )

        return parseMoshServerOutput(capturedOutput)
    }

    private func parseMoshServerOutput(_ output: String) -> MoshServerParams? {
        let lines = output.split(separator: "\n")

        var ip: String?
        var port: String?
        var key: String?

        for line in lines {
            let stringLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)

            if stringLine.contains("Connected") {
                if let range = stringLine.range(of: "Connected to\\s+(\\S+)", options: .regularExpression) {
                    let after = String(stringLine[range.upperBound...])
                    ip = after.components(separatedBy: .whitespacesAndNewlines).first
                }
            }

            if stringLine.contains("MOSH CONNECT") {
                let pattern = "MOSH\\s+CONNECT\\s+(\\d+)\\s+(\\S+)"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: stringLine, range: NSRange(stringLine.startIndex..., in: stringLine)) {

                    if let portRange = Range(match.range(at: 1), in: stringLine) {
                        port = String(stringLine[portRange])
                    }
                    if let keyRange = Range(match.range(at: 2), in: stringLine) {
                        key = String(stringLine[keyRange])
                    }
                }
            }
        }

        if ip == nil {
            ip = machine.remoteAddress
        }

        guard let finalIP = ip,
              let finalPort = port,
              let finalKey = key else {
            return nil
        }

        return MoshServerParams(ip: finalIP, port: finalPort, key: finalKey)
    }

    private func beginSSHShell() {
        sshConnection.begin(
            withTerminalType: "xterm"
        ) {
            // Channel opened
        } withTerminalSize: { [weak self] in
            var size = self?.terminalSize ?? CGSize(width: 80, height: 40)
            if size.width < 8 || size.height < 8 {
                size = CGSize(width: 80, height: 40)
            }
            return size
        } withWriteDataBuffer: { [weak self] in
            self?.getBuffer() ?? ""
        } withOutputDataBuffer: { [weak self] output in
            let sem = DispatchSemaphore(value: 0)
            Task { @MainActor in
                self?.termInterface.write(output)
                self?.handleShellOutput(output)
                sem.signal()
            }
            sem.wait()
        } withContinuationHandler: { [weak self] in
            self?.continueDecision ?? false
        }
    }

    // MARK: - Buffer Management

    public func getBuffer() -> String {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        let copy = _dataBuffer
        _dataBuffer = ""
        return copy
    }

    public func insertBuffer(_ str: String) {
        bufferLock.lock()
        _dataBuffer += str
        bufferLock.unlock()

        Task {
            self.sshConnection.explicitRequestStatusPickup()
        }
    }

    private func handleShellOutput(_ output: String) {
        historyLock.lock()
        outputHistory += output
        if outputHistory.count > maxHistorySize {
            let removeCount = outputHistory.count - maxHistorySize
            outputHistory = String(outputHistory.dropFirst(removeCount))
        }
        historyLock.unlock()
    }

    public func getOutputHistory() -> String {
        historyLock.lock()
        defer { historyLock.unlock() }
        return outputHistory
    }

    // MARK: - Output

    public func putInformation(_ str: String) {
        termInterface.write(str + "\r\n")
    }

    // MARK: - Shutdown

    public func processShutdown(exitFromShell: Bool = false) {
        if exitFromShell {
            putInformation("")
            putInformation("[*] Connection Closed")
        }

        if let lastError = sshConnection.getLastError() {
            putInformation("[i] Last Error Provided By Backend")
            putInformation("    " + lastError)
        }

        continueDecision = false

        Task {
            self.sshConnection.requestDisconnectAndWait()
        }
    }
}

// MARK: - Error Types

enum MoshContextError: Error {
    case authenticationFailed(String)
    case authenticationTimeout
    case connectionFailed(String)
}
