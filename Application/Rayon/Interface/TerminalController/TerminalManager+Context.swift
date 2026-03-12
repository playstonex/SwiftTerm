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
#if canImport(AppKit)
import AppKit
#endif

extension TerminalManager {
    final class Context: ObservableObject, Identifiable, Equatable {
        private final class LockedState<Value> {
            private let lock = NSLock()
            private var value: Value

            init(_ value: Value) {
                self.value = value
            }

            func withValue<T>(_ operation: (inout Value) -> T) -> T {
                lock.lock()
                defer { lock.unlock() }
                return operation(&value)
            }
        }

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
                publishNavigationSubtitle()
            }
        }
        @Published private(set) var currentWorkingDirectory: String = "" {
            didSet {
                publishNavigationSubtitle()
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
        @Published private(set) var historyRevision: Int = 0

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

        private let dataBufferState = LockedState("")

        // Persistent history for copy and AI analysis (keeps last 50000 chars)
        private let outputHistoryState = LockedState("")
        private let maxHistorySize = 50000

        // Output Observers (for Skills and other non-destructive consumers)
        private let outputObserverState = LockedState([UUID: (String) -> Void]())
        private let commandMonitor = TerminalCommandMonitor()

        func addOutputObserver(_ observer: @escaping (String) -> Void) -> UUID {
            let id = UUID()
            outputObserverState.withValue { observers in
                observers[id] = observer
            }
            return id
        }

        func removeOutputObserver(_ id: UUID) {
            outputObserverState.withValue { observers in
                _ = observers.removeValue(forKey: id)
            }
        }

        private func appendToOutputHistory(_ str: String) {
            outputHistoryState.withValue { outputHistory in
                outputHistory += str
                if outputHistory.count > maxHistorySize {
                    let removeCount = outputHistory.count - maxHistorySize
                    outputHistory = String(outputHistory.dropFirst(removeCount))
                }
            }
        }

        // MARK: Output Handling

        /// Handle output received from the shell
        /// - Parameter str: The output string from the shell
        func handleShellOutput(_ str: String) {
            // Notify observers (Skills, etc.)
            let observers = outputObserverState.withValue { Array($0.values) }

            for observer in observers {
                observer(str)
            }

            // Add to persistent history (for copy and AI analysis)
            appendToOutputHistory(str)

            publishHistoryRevision()
            consumeCommandMonitorOutput(str)
        }

        /// Handle output received from Mosh UDP session
        /// - Parameter str: The output string from Mosh
        func handleMoshOutput(_ data: Data) {
            let output = Context.decodeMoshText(data)
            Task { @MainActor in
                self.termInterface.write(data: data)
            }
            
            // Notify observers (Skills, etc.)
            let observers = outputObserverState.withValue { Array($0.values) }

            for observer in observers {
                observer(output)
            }

            // Add to persistent history (for copy and AI analysis)
            appendToOutputHistory(output)

            publishHistoryRevision()
            consumeCommandMonitorOutput(output)
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
            dataBufferState.withValue { dataBuffer in
                let copy = dataBuffer
                dataBuffer = ""
                return copy
            }
        }

        func insertBuffer(_ str: String) {
            routeInput(str, trackAsUserInput: true)
        }

        private func insertInternalBuffer(_ str: String) {
            routeInput(str, trackAsUserInput: false)
        }

        private func routeInput(_ str: String, trackAsUserInput: Bool) {
            if trackAsUserInput {
                Task {
                    await commandMonitor.registerUserInput(str)
                }
            }

            let shouldRouteToMosh = dataBufferState.withValue { dataBuffer in
                let shouldRoute = moshConnected && moshSession != nil
                if !shouldRoute {
                    // Add to data buffer (for SSH/UI/Shell Input)
                    dataBuffer += str
                }
                return shouldRoute
            }

            // Route to Mosh if connected, otherwise use SSH
            if shouldRouteToMosh, let mosh = moshSession {
                mosh.sendString(str)
            } else {
                Task.detached(priority: .userInitiated) { [weak self] in
                    self?.shell.explicitRequestStatusPickup()
                }
            }
        }

        func getOutputHistory() -> String {
            outputHistoryState.withValue { $0 }
        }

        func getOutputHistoryStrippedANSI() -> String {
            let history = getOutputHistory()
            return history.stripANSIEscapeCodes()
        }

        private func publishNavigationSubtitle() {
            let subtitle = currentWorkingDirectory.isEmpty ? title : currentWorkingDirectory
            Task { @MainActor [weak self, subtitle] in
                self?.navigationSubtitle = subtitle
            }
        }

        private func publishHistoryRevision() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.historyRevision = self.historyRevision &+ 1
            }
        }

        private func consumeCommandMonitorOutput(_ output: String) {
            Task { [weak self] in
                guard let self else { return }
                let update = await self.commandMonitor.consumeOutput(output)
                await MainActor.run {
                    if let workingDirectory = update.workingDirectory {
                        self.currentWorkingDirectory = workingDirectory
                    }
                    if !update.commandCompletions.isEmpty {
                        self.handleCommandCompletions(update.commandCompletions)
                    }
                }
            }
        }

        @MainActor
        private func handleCommandCompletions(_ completions: [TerminalCommandCompletion]) {
            guard RayonStore.shared.terminalCommandNotificationsEnabled else { return }

            let minimumDuration = TimeInterval(RayonStore.shared.terminalCommandNotificationMinimumDuration)
            for completion in completions where completion.duration >= minimumDuration {
                if RayonStore.shared.terminalCommandNotificationsOnlyWhenInactive, isApplicationActiveForTerminalNotifications() {
                    continue
                }
                TerminalCommandNotificationCenter.notify(
                    host: machine.name.isEmpty ? machine.remoteAddress : machine.name,
                    completion: completion
                )
            }
        }

        @MainActor
        private func isApplicationActiveForTerminalNotifications() -> Bool {
            #if canImport(AppKit)
            return NSApp.isActive
            #else
            return false
            #endif
        }

        var continueDecision: Bool = true {
            didSet {
                let disabled = !continueDecision
                Task { @MainActor [weak self, disabled] in
                    self?.interfaceDisabled = disabled
                }
            }
        }

        // MARK: SHELL CONTEXT -

        let termInterface: STerminalView = .init()

        init(machine: RDMachine) {
            self.machine = machine
            command = nil
            remoteType = .machine
            title = machine.name
            Task.detached(priority: .userInitiated) {
                await self.processBootstrap()
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
            Task.detached(priority: .userInitiated) {
                await self.processBootstrap()
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

        func reconnectInBackground() {
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                self.putInformation("[i] Reconnect will use the information you provide previously,")
                self.putInformation("    if the machine was edited, create a new terminal.")
                await self.processBootstrap()
            }
        }

        private func handleTerminalEvent(_ event: TerminalEvent) {
            switch event {
            case .input(let buffer):
                insertBuffer(buffer)
            case .title(let str):
                title = str
            case .bell:
                break
            case .size(let size):
                terminalSize = size
            case .copy(let payload):
                payload.writeToPasteboard()
            }
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

        private func buildPOSIXShellCommand(_ command: String) -> String {
            "sh -lc \(singleQuotedShellString(command))"
        }

        private func buildTmuxBootstrapCommand(sessionName: String, autoCreate: Bool) -> String {
            let quotedSession = singleQuotedShellString(sessionName)
            let tmuxAction = autoCreate
                ? "\"$TMUX_BIN\" new-session -A -s \(quotedSession)"
                : "\"$TMUX_BIN\" attach-session -t \(quotedSession)"
            let command = """
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
            return buildPOSIXShellCommand(command)
        }

        private struct MoshServerParams {
            let ip: String
            let port: String
            let key: String
        }

        private func startMoshServer() async -> MoshServerParams? {
            let serverCmd = [
                "mosh-server", "new", "-s",
                "-c", "256",
                "-l", "LC_ALL=en_US.UTF-8"
            ].joined(separator: " ")

            var capturedOutput = ""
            let timeout = NSNumber(value: 10)

            putInformation("[*] Executing: \(serverCmd)")

            await withCheckedContinuation { continuation in
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
                        continuation.resume()
                        return true
                    }
                )
            }

            print("[Mosh Debug] Command output length: \(capturedOutput.count)")

            let params = parseMoshServerOutput(capturedOutput)
            if params == nil {
                putInformation("[!] No mosh-server response received")
                putInformation("[i] Output: \(capturedOutput.prefix(200))")
            }
            return params
        }

        private func connectMoshSession(with moshParams: MoshServerParams) async -> Bool {
            let session = NMSession()
            moshSession = session

            let stateStream = AsyncStream<NMSession.State> { continuation in
                let stateHandler: NMSession.StateHandler = { [weak self] state in
                    Task { @MainActor [weak self] in
                        switch state {
                        case .connecting:
                            self?.putInformation("[i] UDP connecting...")
                        case .connected:
                            self?.moshConnected = true
                            self?.putInformation("[+] UDP socket ready")
                        case .disconnected:
                            self?.putInformation("[!] UDP disconnected")
                        case .failed(let error):
                            self?.putInformation("[!] UDP connection failed: \(error)")
                        }
                    }

                    continuation.yield(state)
                    switch state {
                    case .connected, .disconnected, .failed:
                        continuation.finish()
                    case .connecting:
                        break
                    }
                }
                let receiveHandler: NMSession.ReceiveHandler = { [weak self] output in
                    Task { @MainActor [weak self] in
                        self?.handleMoshOutput(output)
                    }
                }

                session.connect(
                    host: moshParams.ip,
                    port: UInt16(moshParams.port) ?? 60001,
                    key: moshParams.key,
                    initialRows: UInt16(self.terminalSize.height),
                    initialCols: UInt16(self.terminalSize.width),
                    stateHandler: stateHandler,
                    receiveHandler: receiveHandler
                )
            }

            let connected = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
                group.addTask {
                    for await state in stateStream {
                        switch state {
                        case .connected:
                            return true
                        case .disconnected, .failed:
                            return false
                        case .connecting:
                            continue
                        }
                    }
                    return false
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    return false
                }

                let result = await group.next() ?? false
                group.cancelAll()
                return result
            }

            if !connected {
                session.disconnect()
                moshSession = nil
                moshConnected = false
            }
            return connected
        }

        private func waitForTerminalClosure() async {
            while continueDecision {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        private func buildShellIntegrationInstallCommand(script: String, path: String) -> String {
            let quotedPath = singleQuotedShellString(path)
            let command = """
            cat > \(quotedPath) <<'__RAYON_OSC133_EOF__'
            \(script)
            __RAYON_OSC133_EOF__
            chmod 600 \(quotedPath)
            """
            return buildPOSIXShellCommand(command)
        }

        private func prepareShellIntegrationCommand(tmuxSessionName: String? = nil) async -> String? {
            let shellKind = await detectInteractiveShellKind(tmuxSessionName: tmuxSessionName)
            guard let bootstrapScript = TerminalCommandMonitor.shellIntegrationBootstrap(for: shellKind),
                  let scriptPath = TerminalCommandMonitor.shellIntegrationScriptPath(for: shellKind),
                  let sourceCommand = TerminalCommandMonitor.shellIntegrationSourceCommand(for: shellKind)
            else {
                return nil
            }

            let installCommand = buildShellIntegrationInstallCommand(script: bootstrapScript, path: scriptPath)
            if let result = try? await executeCommandForSkill(installCommand, timeout: 5),
               result.exitCode == 0
            {
                return sourceCommand + "\n"
            }

            return nil
        }

        private func detectInteractiveShellKind(tmuxSessionName: String? = nil) async -> TerminalShellKind {
            if let tmuxSessionName {
                let paneCommand = "tmux display-message -p -t \(singleQuotedShellString(tmuxSessionName)) '#{pane_current_command}' 2>/dev/null"
                if let result = try? await executeCommandForSkill(paneCommand, timeout: 5),
                   let detectedPath = trimmedCommandOutput(from: result.output)
                {
                    let shellKind = TerminalCommandMonitor.shellKind(from: detectedPath)
                    if shellKind != .unknown {
                        return shellKind
                    }
                }

                if let result = try? await executeCommandForSkill(#"tmux show -gv default-shell 2>/dev/null"#, timeout: 5),
                   let detectedPath = trimmedCommandOutput(from: result.output)
                {
                    let shellKind = TerminalCommandMonitor.shellKind(from: detectedPath)
                    if shellKind != .unknown {
                        return shellKind
                    }
                }
            }

            if let result = try? await executeCommandForSkill(#"printf '%s\n' "$SHELL""#, timeout: 5),
               let detectedPath = trimmedCommandOutput(from: result.output)
            {
                return TerminalCommandMonitor.shellKind(from: detectedPath)
            }

            return .unknown
        }

        private func trimmedCommandOutput(from output: String) -> String? {
            output
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .last { !$0.isEmpty }
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

        func processBootstrap() async {
            defer {
                Task { @MainActor [weak self] in
                    self?.processShutdown(exitFromShell: true)
                }
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
                .setupEventChain { [weak self] event in
                    self?.handleTerminalEvent(event)
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

            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.remoteType == .machine else {
                    return
                }
                var read = RayonStore.shared.machineGroup[self.machine.id]
                if read.isNotPlaceholder() {
                    read.lastBanner = self.shell.remoteBanner ?? "No Banner"
                    RayonStore.shared.machineGroup[self.machine.id] = read
                }
            }

            let configuredSessionName = RayonStore.shared.tmuxSessionName
            let tmuxSessionName = RayonStore.shared.useTmux
                ? normalizedTmuxSessionName(configuredSessionName)
                : nil
            let shellIntegrationBootstrap = await prepareShellIntegrationCommand(tmuxSessionName: tmuxSessionName)

            if RayonStore.shared.terminalCommandNotificationsEnabled {
                TerminalCommandNotificationCenter.requestAuthorizationIfNeeded()
            }

            // Mosh bootstrap: start mosh-server via SSH
            putInformation("[*] Connection type: \(machine.connectionType.rawValue.uppercased())")
            if moshModeActive {
                putInformation("[*] Starting Mosh session")
                if let moshParams = await self.startMoshServer() {
                    putInformation("[i] Mosh server available at \(moshParams.ip):\(moshParams.port)")
                    putInformation("[*] Connecting via UDP...")

                    if await connectMoshSession(with: moshParams) {
                        if let shellIntegrationBootstrap {
                            insertInternalBuffer(shellIntegrationBootstrap)
                        }
                        putInformation("[+] Mosh session active (SSH bootstrap detached)")
                        shell.requestDisconnectAndWait()
                        await waitForTerminalClosure()
                        return
                    }

                    putInformation("[i] UDP session was not established, falling back to SSH")
                } else {
                    putInformation("[i] mosh-server not available, using SSH")
                    moshConnected = false
                }
            }

            // Prepare tmux bootstrap command before entering the terminal loop.
            if RayonStore.shared.useTmux {
                Task { @MainActor [weak self] in
                    self?.isInTmuxSession = true
                }
                let sessionName = tmuxSessionName ?? "default"
                let autoCreate = RayonStore.shared.tmuxAutoCreate

                let tmuxCmd = buildTmuxBootstrapCommand(sessionName: sessionName, autoCreate: autoCreate)

                if configuredSessionName.trimmingCharacters(in: .whitespacesAndNewlines) != sessionName {
                    putInformation("[i] Normalized tmux session name to: \(sessionName)")
                }
                putInformation("[*] Attaching to tmux session: \(sessionName)")
                insertInternalBuffer(tmuxCmd + "\n")
                if let shellIntegrationBootstrap {
                    insertInternalBuffer(shellIntegrationBootstrap)
                }
            } else {
                if let shellIntegrationBootstrap {
                    insertInternalBuffer(shellIntegrationBootstrap)
                }
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

            Task.detached(priority: .userInitiated) {
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
                let continuationGate = LockedState(false)

                self.shell.beginExecute(
                    withCommand: wrappedCommand,
                    withTimeout: NSNumber(value: timeout),
                    withOnCreate: {},
                    withOutput: { chunk in
                        output.append(chunk)
                    },
                    withContinuationHandler: { [capturedContinuation = continuation] in
                        let shouldResume = continuationGate.withValue { resumed in
                            guard !resumed else { return false }
                            resumed = true
                            return true
                        }
                        guard shouldResume else { return true }

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
            Task { @MainActor [weak self] in
                self?.isInTmuxSession = false
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
                Task.detached(priority: .utility) {
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
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
