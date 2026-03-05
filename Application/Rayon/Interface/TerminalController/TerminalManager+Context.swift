//
//  TerminalManager+Context.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/10.
//

import Foundation
import NSRemoteShell
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

        // MARK: - SHELL CONTEXT

        var closed: Bool { !continueDecision }

        @Published var interfaceToken: UUID = .init()
        @Published var interfaceDisabled: Bool = false

        static let defaultTerminalSize = CGSize(width: 80, height: 40)

        var terminalSize: CGSize = defaultTerminalSize {
            didSet {
                shell.explicitRequestStatusPickup()
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

        func getBuffer() -> String {
            bufferAccessLock.lock()
            defer { bufferAccessLock.unlock() }
            let copy = _dataBuffer
            _dataBuffer = ""
            return copy
        }

        func insertBuffer(_ str: String) {
            bufferAccessLock.lock()
            // Add to data buffer (for SSH/UI/Shell Input)
            _dataBuffer += str
            bufferAccessLock.unlock()
            
            Context.queue.async { [weak self] in
                self?.shell.explicitRequestStatusPickup()
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

        func processBootstrap() {
            defer {
                DispatchQueue.main.async { self.processShutdown(exitFromShell: true) }
            }

            setupShellData()

            putInformation("[*] Creating Connection")
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

            // Prepare tmux bootstrap command before entering the terminal loop.
            if RayonStore.shared.useTmux {
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
                // 1. Process for UI
                let sem = DispatchSemaphore(value: 0)
                mainActor {
                    self?.termInterface.write(output)
                    sem.signal()
                }
                sem.wait()

                // 2. Process for Logic (History, Observers)
                self?.handleShellOutput(output)
            } withContinuationHandler: { [weak self] in
                self?.continueDecision ?? false
            }

            processShutdown()
        }

        func processShutdown(exitFromShell: Bool = false) {
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
