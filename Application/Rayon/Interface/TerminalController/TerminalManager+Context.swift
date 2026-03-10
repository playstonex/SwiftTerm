//
//  TerminalManager+Context.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/10.
//

import Foundation
import NSRemoteShell
import NMMoshShell
import RayonModule
import SwiftUI
import SwiftTerminal

extension TerminalManager {
    class Context: ObservableObject, Identifiable, Equatable {
        var id: UUID = .init()

        var navigationTitle: String {
            switch remoteType {
            case .machine: return machine.shortDescription(withComment: false)
            case .command: return command?.command ?? "Unknown Command"
            }
        }

        @Published var navigationSubtitle: String = ""

        private var title: String = "" {
            didSet {
                DispatchQueue.main.async {
                    self.navigationSubtitle = self.title
                }
            }
        }

        enum RemoteType {
            case machine
            case command
        }

        let remoteType: RemoteType

        let machine: RDMachine
        let command: SSHCommandReader?
        var shell: NSRemoteShell = .init()

        // Mosh session (optional, used when connectionType is Mosh)
        private var moshSession: NMSession?
        private var moshConnected: Bool = false
        private var moshModeActive: Bool { machine.connectionType == .mosh }

        // MARK: - SHELL CONTEXT

        var closed: Bool { !continueDecision }

        @Published var interfaceToken: UUID = .init()
        @Published var interfaceDisabled: Bool = false
        @Published var isInTmuxSession: Bool = false

        static let defaultTerminalSize = CGSize(width: 80, height: 40)

        var terminalSize: CGSize = defaultTerminalSize {
            didSet {
                // Send resize to Mosh if connected
                if moshConnected, let mosh = moshSession {
                    let rows = UInt16(terminalSize.height)
                    let cols = UInt16(terminalSize.width)
                    mosh.sendResize(rows: rows, cols: cols)
                }
                if !moshConnected {
                    shell.explicitRequestStatusPickup()
                }
            }
        }

        private var _dataBuffer: String = ""
        private var bufferAccessLock = NSLock()

        // Persistent history for copy and AI analysis (keeps last 50000 chars)
        private var outputHistory: String = ""
        private let maxHistorySize = 50000
        private let historyLock = NSLock()

        // Output Observers (for Skills and other non-destructive consumers)
        private var outputObservers: [UUID: (String) -> Void] = [:]
        private let observerLock = NSLock()

        func addOutputObserver(_ observer: @escaping (String) -> Void) -> UUID {
            observerLock.lock()
            defer { observerLock.unlock() }
            let id = UUID()
            outputObservers[id] = observer
            return id
        }

        func removeOutputObserver(_ id: UUID) {
            observerLock.lock()
            defer { observerLock.unlock() }
            outputObservers.removeValue(forKey: id)
        }

        // MARK: Output Handling

        /// Handle output received from the shell
        /// - Parameter str: The output string from the shell
        func handleShellOutput(_ str: String) {
            // Notify observers (Skills, etc.)
            observerLock.lock()
            let observers = outputObservers.values
            observerLock.unlock()

            for observer in observers {
                observer(str)
            }

            // Add to persistent history (for copy and AI analysis)
            historyLock.lock()
            outputHistory += str
            // Keep history at max size by removing old content
            if outputHistory.count > maxHistorySize {
                let removeCount = outputHistory.count - maxHistorySize
                outputHistory = String(outputHistory.dropFirst(removeCount))
            }
            historyLock.unlock()
        }

        /// Handle output received from Mosh UDP session
        /// - Parameter str: The output string from Mosh
        func handleMoshOutput(_ data: Data) {
            let output = Context.decodeMoshText(data)
            Task { @MainActor in
                self.termInterface.write(data: data)
            }
            
            // Notify observers (Skills, etc.)
            observerLock.lock()
            let observers = outputObservers.values
            observerLock.unlock()

            for observer in observers {
                observer(output)
            }

            // Add to persistent history (for copy and AI analysis)
            historyLock.lock()
            outputHistory += output
            // Keep history at max size by removing old content
            if outputHistory.count > maxHistorySize {
                let removeCount = outputHistory.count - maxHistorySize
                outputHistory = String(outputHistory.dropFirst(removeCount))
            }
            historyLock.unlock()
        }

        private static func decodeMoshText(_ data: Data) -> String {
            if let utf8 = String(data: data, encoding: .utf8) {
                return utf8
            }
            if let latin1 = String(data: data, encoding: .isoLatin1) {
                return latin1
            }
            return String(decoding: data, as: UTF8.self)
        }

        func getBuffer() -> String {
            bufferAccessLock.lock()
            defer { bufferAccessLock.unlock() }
            let copy = _dataBuffer
            _dataBuffer = ""
            return copy
        }

        func insertBuffer(_ str: String) {
            bufferAccessLock.lock()
            let shouldRouteToMosh = moshConnected && moshSession != nil
            if !shouldRouteToMosh {
                // Add to data buffer (for SSH/UI/Shell Input)
                _dataBuffer += str
            }
            bufferAccessLock.unlock()

            // Route to Mosh if connected, otherwise use SSH
            if shouldRouteToMosh, let mosh = moshSession {
                mosh.sendString(str)
            } else {
                Context.queue.async { [weak self] in
                    self?.shell.explicitRequestStatusPickup()
                }
            }
        }

        func getOutputHistory() -> String {
            historyLock.lock()
            defer { historyLock.unlock() }
            return outputHistory
        }

        func getOutputHistoryStrippedANSI() -> String {
            let history = getOutputHistory()
            return history.stripANSIEscapeCodes()
        }

        var continueDecision: Bool = true {
            didSet {
                DispatchQueue.main.async {
                    self.interfaceDisabled = !self.continueDecision
                }
            }
        }

        // MARK: SHELL CONTEXT -

        let termInterface: STerminalView = .init()

        private static let queue = DispatchQueue(
            label: "wiki.qaq.terminal",
            qos: DispatchQoS.userInitiated,
            attributes: .concurrent
        )

        init(machine: RDMachine) {
            self.machine = machine
            command = nil
            remoteType = .machine
            title = machine.name
            Context.queue.async {
                self.processBootstrap()
            }
        }

        init(command: SSHCommandReader) {
            machine = RDMachine(
                remoteAddress: command.remoteAddress,
                remotePort: command.remotePort,
                name: command.remoteAddress,
                group: "SSHCommandReader",
                associatedIdentity: nil
            )
            self.command = command
            title = command.command
            remoteType = .machine
            Context.queue.async {
                self.processBootstrap()
            }
        }

        func setupShellData() {
            shell
                .setupConnectionHost(machine.remoteAddress)
                .setupConnectionPort(NSNumber(value: Int(machine.remotePort) ?? 0))
                .setupConnectionTimeout(RayonStore.shared.timeoutNumber)
        }

        static func == (lhs: Context, rhs: Context) -> Bool {
            lhs.id == rhs.id
        }

        func putInformation(_ str: String) {
            termInterface.write(str + "\r\n")
        }

        private func normalizedTmuxSessionName(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "default" }
            let sanitized = trimmed.replacingOccurrences(
                of: #"[^A-Za-z0-9_-]"#,
                with: "_",
                options: .regularExpression
            )
            return sanitized.isEmpty ? "default" : sanitized
        }

        private func singleQuotedShellString(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        }

        private func buildTmuxBootstrapCommand(sessionName: String, autoCreate: Bool) -> String {
            let quotedSession = singleQuotedShellString(sessionName)
            let tmuxAction = autoCreate
                ? "\"$TMUX_BIN\" new-session -A -s \(quotedSession)"
                : "\"$TMUX_BIN\" attach-session -t \(quotedSession)"
            return """
            TMUX_BIN="$(command -v tmux 2>/dev/null || true)"; \
            if [ -z "$TMUX_BIN" ]; then \
              for p in /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do \
                [ -x "$p" ] && TMUX_BIN="$p" && break; \
              done; \
            fi; \
            if [ -z "$TMUX_BIN" ]; then \
              echo '[!] tmux not found in PATH or common install paths'; \
            else \
              \(tmuxAction); \
            fi
            """
        }

        private struct MoshServerParams {
            let ip: String
            let port: String
            let key: String
        }

        private func startMoshServer() -> MoshServerParams? {
            let serverCmd = [
                "mosh-server", "new", "-s",
                "-c", "256",
                "-l", "LC_ALL=en_US.UTF-8"
            ].joined(separator: " ")

            var capturedOutput = ""
            let timeout = NSNumber(value: 10)

            putInformation("[*] Executing: \(serverCmd)")

            shell.beginExecute(
                withCommand: serverCmd,
                withTimeout: timeout,
                withOnCreate: {},
                withOutput: { output in
                    // Capture and log each chunk of output
                    capturedOutput += output
                    print("[Mosh Debug] Output chunk: \(output.prefix(100))")
                },
                withContinuationHandler: {
                    print("[Mosh Debug] Complete output: \(capturedOutput)")
                    // Parse output for connection parameters
                    if let params = self.parseMoshServerOutput(capturedOutput) {
                        print("[Mosh Debug] Parsed params: IP=\(params.ip), PORT=\(params.port), KEY=\(params.key.prefix(10))...")
                        return true
                    }
                    print("[Mosh Debug] Failed to parse mosh-server output")
                    return true
                }
            )

            // Wait for command to complete (on background thread - acceptable)
            Thread.sleep(forTimeInterval: 2.0)

            print("[Mosh Debug] After sleep, captured output length: \(capturedOutput.count)")

            let params = parseMoshServerOutput(capturedOutput)
            if params == nil {
                putInformation("[!] No mosh-server response received")
                putInformation("[i] Output: \(capturedOutput.prefix(200))")
            }
            return params
        }

        private func parseMoshServerOutput(_ output: String) -> MoshServerParams? {
            let lines = output.split(separator: "\n")

            var ip: String?
            var port: String?
            var key: String?

            for line in lines {
                let stringLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)

                // Look for IP address
                if stringLine.contains("Connected") {
                    if let range = stringLine.range(of: "Connected to\\s+(\\S+)", options: .regularExpression) {
                        let after = String(stringLine[range.upperBound...])
                        ip = after.components(separatedBy: .whitespacesAndNewlines).first
                    }
                }

                // Look for MOSH CONNECT line
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

            // Fallback: use remoteHost as IP if not found
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

        func processBootstrap() {
            defer {
                DispatchQueue.main.async { self.processShutdown(exitFromShell: true) }
            }

            setupShellData()

            // Check connection type (SSH vs Mosh)
            let useMosh = machine.connectionType == .mosh
            if useMosh {
                putInformation("[*] Creating Mosh Connection")
            } else {
                putInformation("[*] Creating Connection")
            }
            continueDecision = true

            termInterface
                .setupBellChain {
                    // Terminal bell
                }
                .setupBufferChain { [weak self] buffer in
                    self?.insertBuffer(buffer)
                }
                .setupTitleChain { [weak self] str in
                    self?.title = str
                }
                .setupSizeChain { [weak self] size in
                    self?.terminalSize = size
                }

            // For Mosh mode, we still use SSH for bootstrap
            shell.requestConnectAndWait()

            guard shell.isConnected else {
                putInformation("Unable to connect for \(machine.remoteAddress):\(machine.remotePort)")
                return
            }

            if let rid = machine.associatedIdentity {
                guard let uid = UUID(uuidString: rid) else {
                    putInformation("Malformed machine data")
                    return
                }
                let identity = RayonStore.shared.identityGroup[uid]
                guard !identity.username.isEmpty else {
                    putInformation("Malformed identity data")
                    return
                }
                identity.callAuthenticationWith(remote: shell)
            } else {
                var previousUsername: String?
                for identity in RayonStore.shared.identityGroupForAutoAuth {
                    putInformation("[i] trying to authenticate with \(identity.shortDescription())")
                    if let prev = previousUsername, prev != identity.username {
                        shell.requestDisconnectAndWait()
                        shell.requestConnectAndWait()
                    }
                    previousUsername = identity.username
                    identity.callAuthenticationWith(remote: shell)
                    if shell.isConnected, shell.isAuthenticated {
                        break
                    }
                }
                putInformation("")
                // user may get confused if multiple session opened the picker
//                if !shell.isAuthenticated,
//                   let identity = RayonUtil.selectIdentity()
//                {
//                    RayonStore.shared
//                        .identityGroup[identity]
//                        .callAuthenticationWith(remote: shell)
//                }
            }

            guard shell.isConnected, shell.isAuthenticated else {
                putInformation("Failed to authenticate connection")
                putInformation("Did you forget to add identity or enable auto authentication?")
                return
            }

            DispatchQueue.main.async {
                guard self.remoteType == .machine else {
                    return
                }
                var read = RayonStore.shared.machineGroup[self.machine.id]
                if read.isNotPlaceholder() {
                    read.lastBanner = self.shell.remoteBanner ?? "No Banner"
                    RayonStore.shared.machineGroup[self.machine.id] = read
                }
            }

            // Mosh bootstrap: start mosh-server via SSH
            putInformation("[*] Connection type: \(machine.connectionType.rawValue.uppercased())")
            if moshModeActive {
                putInformation("[*] Starting Mosh session")
                if let moshParams = self.startMoshServer() {
                    putInformation("[i] Mosh server available at \(moshParams.ip):\(moshParams.port)")
                    putInformation("[*] Connecting via UDP...")

                    // Create and connect Mosh session
                    let session = NMSession()
                    moshSession = session
                    let moshConnectionResult = DispatchSemaphore(value: 0)
                    let moshStateLock = NSLock()
                    var didEstablishMosh = false

                    session.connect(
                        host: moshParams.ip,
                        port: UInt16(moshParams.port) ?? 60001,
                        key: moshParams.key,
                        initialRows: UInt16(self.terminalSize.height),
                        initialCols: UInt16(self.terminalSize.width),
                        stateHandler: { @MainActor [weak self] state in
                            switch state {
                            case .connecting:
                                self?.putInformation("[i] UDP connecting...")
                            case .connected:
                                moshStateLock.lock()
                                didEstablishMosh = true
                                moshStateLock.unlock()
                                self?.moshConnected = true
                                self?.putInformation("[+] UDP socket ready")
                                moshConnectionResult.signal()
                            case .disconnected:
                                self?.putInformation("[!] UDP disconnected")
                                moshConnectionResult.signal()
                            case .failed(let error):
                                self?.putInformation("[!] UDP connection failed: \(error)")
                                moshConnectionResult.signal()
                            }
                        },
                        receiveHandler: { @MainActor [weak self] output in
                            self?.handleMoshOutput(output)
                        }
                    )

                    let waitResult = moshConnectionResult.wait(timeout: .now() + 5)
                    moshStateLock.lock()
                    let shouldUseMosh = didEstablishMosh
                    moshStateLock.unlock()

                    if waitResult == .success, shouldUseMosh {
                        putInformation("[+] Mosh session active (SSH bootstrap detached)")
                        shell.requestDisconnectAndWait()
                        while continueDecision {
                            Thread.sleep(forTimeInterval: 0.05)
                        }
                        return
                    }

                    putInformation("[i] UDP session was not established, falling back to SSH")
                    session.disconnect()
                    moshSession = nil
                    moshConnected = false
                } else {
                    putInformation("[i] mosh-server not available, using SSH")
                    moshConnected = false
                }
            }

            // Prepare tmux bootstrap command before entering the terminal loop.
            if RayonStore.shared.useTmux {
                DispatchQueue.main.async {
                    self.isInTmuxSession = true
                }
                let configuredSessionName = RayonStore.shared.tmuxSessionName
                let sessionName = normalizedTmuxSessionName(configuredSessionName)
                let autoCreate = RayonStore.shared.tmuxAutoCreate

                let tmuxCmd = buildTmuxBootstrapCommand(sessionName: sessionName, autoCreate: autoCreate)

                if configuredSessionName.trimmingCharacters(in: .whitespacesAndNewlines) != sessionName {
                    putInformation("[i] Normalized tmux session name to: \(sessionName)")
                }
                putInformation("[*] Attaching to tmux session: \(sessionName)")
                insertBuffer(tmuxCmd + "\n")
            }

            shell.begin(withTerminalType: "xterm") {
                // Channel opened
            } withTerminalSize: { [weak self] in
                var size = self?.terminalSize ?? Context.defaultTerminalSize
                if size.width < 8 || size.height < 8 {
                    // something went wrong
                    size = Context.defaultTerminalSize
                }
                return size
            } withWriteDataBuffer: { [weak self] in
                self?.getBuffer() ?? ""
            } withOutputDataBuffer: { [weak self] output in
                Task { @MainActor in
                    self?.termInterface.write(output)
                }
                
                // Process for Logic (History, Observers)
                self?.handleShellOutput(output)
            } withContinuationHandler: { [weak self] in
                self?.continueDecision ?? false
            }
        }

        func processShutdown(exitFromShell: Bool = false) {
            moshSession?.disconnect()
            moshSession = nil
            moshConnected = false

            if exitFromShell {
                putInformation("")
                putInformation("[*] Connection Closed")
            }
            if let lastError = shell.getLastError() {
                putInformation("[i] Last Error Provided By Backend")
                putInformation("    " + lastError)
            }
            continueDecision = false

            Context.queue.async {
                self.shell.requestDisconnectAndWait()
            }
        }

        // MARK: - SKILL EXECUTION

        /// Execute command and capture output within skill context
        func executeCommandForSkill(_ command: String, timeout: Int = 30) async throws -> (output: String, exitCode: Int?) {
            var output = ""

            // Wrap command to capture exit code
            let wrappedCommand = wrapCommandWithExitCode(command)

            return try await withCheckedThrowingContinuation { continuation in
                // Track whether we've already resumed to prevent double-resume
                var resumed = false
                let lock = NSLock()

                self.shell.beginExecute(
                    withCommand: wrappedCommand,
                    withTimeout: NSNumber(value: timeout),
                    withOnCreate: {},
                    withOutput: { chunk in
                        output.append(chunk)
                    },
                    withContinuationHandler: { [capturedContinuation = continuation] in
                        lock.lock()
                        defer { lock.unlock() }

                        guard !resumed else {
                            // Already resumed, return true to indicate termination
                            return true
                        }
                        resumed = true

                        // Parse exit code from output
                        let (cleanOutput, code) = self.parseExitCode(from: output)

                        capturedContinuation.resume(returning: (cleanOutput, code))
                        return true
                    }
                )
            }
        }
        
        // MARK: - Helpers

        private func wrapCommandWithExitCode(_ command: String) -> String {
            return " \(command); echo \"\nTYPE_RAYON_EXIT_CODE:$?\""
        }

        private func parseExitCode(from output: String) -> (String, Int) {
            var cleanOutput = output
            var exitCode = 1 // Default to failure if not found

            if let range = output.range(of: "TYPE_RAYON_EXIT_CODE:", options: .backwards) {
                let exitCodeStr = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                exitCode = Int(exitCodeStr) ?? 1
                
                // Remove the exit code marker from output
                // Try to find the newline before the marker to remove it as well
                if range.lowerBound > output.startIndex {
                     let beforeIndex = output.index(before: range.lowerBound)
                     if output[beforeIndex] == "\n" {
                         cleanOutput = String(output[..<beforeIndex])
                     } else {
                         cleanOutput = String(output[..<range.lowerBound])
                     }
                } else {
                     cleanOutput = String(output[..<range.lowerBound])
                }
            }

            return (cleanOutput, exitCode)
        }

        // MARK: - Tmux Commands

        /// Sends a tmux command by first pressing Ctrl+B, then the command key
        func sendTmuxCommand(_ command: String) {
            guard isInTmuxSession else { return }
            // Send Ctrl+B (prefix key), then the command
            insertBuffer("\u{02}\(command)")
        }

        /// Sends raw key sequences to the terminal
        func sendTmuxKeySequence(_ sequence: String) {
            guard isInTmuxSession else { return }
            insertBuffer(sequence)
        }

        /// Detach from the current tmux session
        func tmuxDetach() {
            sendTmuxCommand("d")
            DispatchQueue.main.async {
                self.isInTmuxSession = false
            }
        }

        /// Create a new tmux window
        func tmuxNewWindow() {
            sendTmuxCommand("c")
        }

        /// List all tmux windows
        func tmuxListWindows() {
            sendTmuxCommand("w")
        }

        /// Switch to the next tmux window
        func tmuxNextWindow() {
            sendTmuxCommand("n")
        }

        /// Switch to the previous tmux window
        func tmuxPreviousWindow() {
            sendTmuxCommand("p")
        }

        /// Kill the current tmux window
        func tmuxKillWindow() {
            sendTmuxCommand("&")
        }

        /// Rename the current tmux window
        func tmuxRenameWindow() {
            sendTmuxCommand(",")
        }

        /// Split the current pane horizontally
        func tmuxSplitHorizontal() {
            sendTmuxCommand("%")
        }

        /// Split the current pane vertically
        func tmuxSplitVertical() {
            sendTmuxCommand("\"")
        }

        /// List all tmux sessions
        func tmuxListSessions() {
            sendTmuxCommand("s")
        }

        /// Enter tmux command mode
        func tmuxCommandMode() {
            sendTmuxCommand(":")
        }

        /// Stream output for real-time analysis
        func streamOutputForSkill(duration: TimeInterval, handler: @escaping (String) -> Void) async {
            return await withCheckedContinuation { continuation in
                var observerId: UUID?
                
                // Set up observer
                observerId = self.addOutputObserver { content in
                    handler(content)
                }
                
                // Set up timer to end stream
                DispatchQueue.global().asyncAfter(deadline: .now() + duration) {
                    if let id = observerId {
                        self.removeOutputObserver(id)
                    }
                    continuation.resume()
                }
            }
        }
    }
}

extension String {
    /// Strip ANSI escape codes from terminal output
    func stripANSIEscapeCodes() -> String {
        var result = self

        // Remove OSC sequences (Operating System Command) like ]2;title<BEL> or ]1;title<BEL>
        // ESC] is \u{1B}\], BEL is \u{07}
        result = result.replacingOccurrences(of: "\u{1B}\\][^\u{07}]*\u{07}", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\u{1B}\\][^\u{1B}]*\u{1B}\\\\", with: "", options: .regularExpression)

        // Remove CSI sequences (Control Sequence Introducer) like [1m, [31;1m, [?2004h, [K, [A
        // Handles:
        // - \u{1B}[ ... [a-zA-Z]
        // - \u{1B}[ ... [0-9]
        // - \u{1B}[ ... [?] ... [a-zA-Z]
        // Matches ESC [ followed by any number of parameter bytes (0x30-0x3F) and intermediate bytes (0x20-0x2F), then a final byte (0x40-0x7E)
        result = result.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)
        
        // Remove simple ESC sequences
        result = result.replacingOccurrences(of: "\u{1B}[=0-9]+[a-zA-Z]", with: "", options: .regularExpression)

        // Remove bracket sequences without ESC (sometimes captured separately)
        result = result.replacingOccurrences(of: "\\[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)

        // Remove character set designation sequences like (B or (0
        result = result.replacingOccurrences(of: "\u{1B}\\([0-9A-Za-z]", with: "", options: .regularExpression)

        // Remove backspace characters (used for character-by-character input rendering)
        result = result.replacingOccurrences(of: "\u{08}", with: "")

        // Clean up carriage returns - keep only linefeeds
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "")

        return result
    }
}
