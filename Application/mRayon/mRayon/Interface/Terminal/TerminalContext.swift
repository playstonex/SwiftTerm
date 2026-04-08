//
//  TerminalContext.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/3.
//

import NSRemoteShell
import NMMoshShell
import RayonModule
import SwiftUI
import UIKit
import SwiftTerminal

final class TerminalContext: ObservableObject, Identifiable, Equatable {
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

    private struct HistoryState {
        var outputHistory: String = ""
        var rawOutputHistory: String = ""
        var totalOutputLength: Int = 0
        var totalRawLength: Int = 0
        var pendingHistoryControlSequence: String = ""
    }

    var id: UUID = .init()

    var navigationTitle: String {
        switch remoteType {
        case .machine: return machine.shortDescription(withComment: false)
        case .command: return command?.command ?? "Unknown Command"
        }
    }

    var firstConnect = true
    @Published var destroyedSession = false {
        didSet {
            if destroyedSession {
                shell.destroyPermanently()
            }
        }
    }

    @Published var navigationSubtitle: String = ""

    // Track if we're in a tmux session
    @Published var isInTmuxSession: Bool = false
    @Published private(set) var currentWorkingDirectory: String = "" {
        didSet {
            publishNavigationSubtitle()
        }
    }

    private var title: String = "" {
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
    private(set) var historyRevision: Int = 0

    static let historyRevisionNotification = Notification.Name("terminal.historyRevision")

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
    // Persistent history for copy functionality (keeps last 50000 chars)
    private let historyState = LockedState(HistoryState())
    private let maxHistorySize = 50000
    private let commandMonitor = TerminalCommandMonitor()

    func getBuffer() -> String {
        dataBufferState.withValue { dataBuffer in
            let copy = dataBuffer
            dataBuffer = ""
            return copy
        }
    }

    func peekBuffer() -> String {
        dataBufferState.withValue { $0 }
    }

    func insertBuffer(_ str: String) {
        routeInput(str, trackAsUserInput: true, addToHistory: true)
    }

    private func insertInternalBuffer(_ str: String) {
        routeInput(str, trackAsUserInput: false, addToHistory: false)
    }

    private func routeInput(_ str: String, trackAsUserInput: Bool, addToHistory: Bool) {
        if trackAsUserInput {
            Task { [commandMonitor] in
                await commandMonitor.registerUserInput(str)
            }
        }

        let routingState = dataBufferState.withValue { dataBuffer in
            let isClosed = closed
            guard !isClosed else { return (isClosed: true, shouldRouteToMosh: false) }
            let shouldRoute = moshConnected && moshSession != nil
            if !shouldRoute {
                // Add to data buffer (for SSH)
                dataBuffer += str
            }
            return (isClosed: false, shouldRouteToMosh: shouldRoute)
        }
        guard !routingState.isClosed else { return }

        // In Mosh mode, the server will echo back output which gets added to history.
        // So we should NOT add user input to history here to avoid duplication.
        // For SSH mode, we still add to history here since SSH output callback adds display output.
        if addToHistory && !routingState.shouldRouteToMosh {
            appendToHistory(str)
        }

        // Route to Mosh if connected, otherwise use SSH
        if routingState.shouldRouteToMosh, let mosh = moshSession {
            mosh.sendString(str)
        } else {
            shell.explicitRequestStatusPickup()
        }
    }

    func getOutputHistory() -> String {
        historyState.withValue { $0.outputHistory }
    }

    func getRawOutputHistory() -> String {
        historyState.withValue { $0.rawOutputHistory }
    }

    func addToHistory(_ str: String) {
        historyState.withValue { history in
            appendToHistoryLocked(str, history: &history)
        }
        publishHistoryRevision()
    }

    func getOutputHistoryStrippedANSI() -> String {
        let history = getOutputHistory()
        return history.stripANSIEscapeCodes().normalizedTerminalTranscript()
    }

    private func appendToHistory(_ str: String) {
        historyState.withValue { history in
            appendToHistoryLocked(str, history: &history)
        }
        publishHistoryRevision()
    }

    private func appendToHistoryLocked(_ str: String, history: inout HistoryState) {
        history.rawOutputHistory += str
        history.totalRawLength += str.count
        let trimThreshold = maxHistorySize + 5000
        if history.totalRawLength > trimThreshold {
            let removeCount = history.totalRawLength - maxHistorySize
            history.rawOutputHistory = String(history.rawOutputHistory.dropFirst(removeCount))
            history.totalRawLength = history.rawOutputHistory.count
        }

        let combined = history.pendingHistoryControlSequence + str
        let split = combined.splittingTrailingIncompleteANSIEscapeSequence()
        history.pendingHistoryControlSequence = split.trailingFragment

        let visibleText = split.completeText
            .stripANSIEscapeCodes()

        guard !visibleText.isEmpty else { return }

        history.outputHistory += visibleText
        history.totalOutputLength += visibleText.count
        if history.totalOutputLength > trimThreshold {
            let removeCount = history.totalOutputLength - maxHistorySize
            history.outputHistory = String(history.outputHistory.dropFirst(removeCount))
            history.totalOutputLength = history.outputHistory.count
        }
    }

    /// Handle output received from Mosh UDP session
    /// - Parameter str: The output string from Mosh
    func handleMoshOutput(_ data: Data) {
        let preview = TerminalContext.decodeMoshText(data)
        debugPrint("[Mosh] handleMoshOutput received: \(preview.prefix(100).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r"))...")

        Task { @MainActor in
            self.termInterface.write(data: data)
        }

        addToHistory(preview)
        consumeCommandMonitorOutput(preview)
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

    static func == (lhs: TerminalContext, rhs: TerminalContext) -> Bool {
        lhs.id == rhs.id
    }

    func putInformation(_ str: String) {
        let message = str + "\r\n"
        addToHistory(message)
        termInterface.write(message)
    }

    func reconnectInBackground() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            self.putInformation(String(localized: "[i] Reconnect will use the information you provide previously,"))
            self.putInformation(String(localized: "    if the machine was edited, create a new terminal."))
            await self.processBootstrap()
        }
    }

    private func handleShellOutput(_ output: String) {
        addToHistory(output)
        consumeCommandMonitorOutput(output)
    }

    private func publishNavigationSubtitle() {
        let subtitle = currentWorkingDirectory.isEmpty ? title : currentWorkingDirectory
        Task { @MainActor [weak self, subtitle] in
            self?.navigationSubtitle = subtitle
        }
    }

    private func publishHistoryRevision() {
        historyRevision = historyRevision &+ 1
        NotificationCenter.default.post(
            name: Self.historyRevisionNotification,
            object: id
        )
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
            if RayonStore.shared.terminalCommandNotificationsOnlyWhenInactive,
               UIApplication.shared.applicationState == .active
            {
                continue
            }
            TerminalCommandNotificationCenter.notify(
                host: machine.name.isEmpty ? machine.remoteAddress : machine.name,
                completion: completion
            )
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
        let tmuxStatusSetup = [
            "\"$TMUX_BIN\" set-option -g status 1",
            "\"$TMUX_BIN\" set-option -g status-left-length 40",
            "\"$TMUX_BIN\" set-option -g status-right-length 40"
        ].joined(separator: "; ")
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
          "$TMUX_BIN" start-server >/dev/null 2>&1 || true; \
          "$TMUX_BIN" set-option -g mouse on >/dev/null 2>&1 || true; \
          \(tmuxStatusSetup); \
          \(tmuxAction); \
        fi
        """
        return buildPOSIXShellCommand(command)
    }

    // MARK: - Mosh Bootstrap

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

    private func executeCommand(_ command: String, timeout: Int = 5) async -> String? {
        var output = ""

        return await withCheckedContinuation { continuation in
            let continuationGate = LockedState(false)

            shell.beginExecute(
                withCommand: command,
                withTimeout: NSNumber(value: timeout),
                withOnCreate: {},
                withOutput: { chunk in
                    output.append(chunk)
                },
                withContinuationHandler: {
                    let shouldResume = continuationGate.withValue { resumed in
                        guard !resumed else { return false }
                        resumed = true
                        return true
                    }
                    guard shouldResume else { return true }

                    continuation.resume(returning: output)
                    return true
                }
            )
        }
    }

    private func buildShellIntegrationInstallCommand(script: String, path: String) -> String {
        let quotedPath = singleQuotedShellString(path)
        let command = """
        cat > \(quotedPath) <<'__RAYON_OSC133_EOF__'
        \(script)
        __RAYON_OSC133_EOF__
        chmod 600 \(quotedPath) && printf '__RAYON_OSC133_READY__\n'
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

        if let output = await executeCommand(buildShellIntegrationInstallCommand(script: bootstrapScript, path: scriptPath), timeout: 5),
           output.contains("__RAYON_OSC133_READY__")
        {
            return sourceCommand + "\n"
        }

        return nil
    }

    private func detectInteractiveShellKind(tmuxSessionName: String? = nil) async -> TerminalShellKind {
        if let tmuxSessionName,
           let tmuxPaneShell = await executeCommand("tmux display-message -p -t \(singleQuotedShellString(tmuxSessionName)) '#{pane_current_command}' 2>/dev/null"),
           let detectedPath = trimmedCommandOutput(from: tmuxPaneShell)
        {
            let shellKind = TerminalCommandMonitor.shellKind(from: detectedPath)
            if shellKind != .unknown {
                return shellKind
            }
        }

        if tmuxSessionName != nil,
           let tmuxDefaultShell = await executeCommand(#"tmux show -gv default-shell 2>/dev/null"#),
           let detectedPath = trimmedCommandOutput(from: tmuxDefaultShell)
        {
            let shellKind = TerminalCommandMonitor.shellKind(from: detectedPath)
            if shellKind != .unknown {
                return shellKind
            }
        }

        if let shellPath = await executeCommand(#"printf '%s\n' "$SHELL""#),
           let detectedPath = trimmedCommandOutput(from: shellPath)
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

        termInterface.setTerminalFontSize(with: RayonStore.shared.terminalFontSize)

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.firstConnect else {
                return
            }
            self.firstConnect = false
            guard RayonStore.shared.openInterfaceAutomatically else { return }
            let host = UIHostingController(
                rootView: DefaultPresent(context: self)
            )
//            host.isModalInPresentation = true
            host.modalTransitionStyle = .coverVertical
            host.modalPresentationStyle = .formSheet
            host.preferredContentSize = preferredPopOverSize
            UIWindow.shutUpKeyWindow?
                .topMostViewController?
                .present(next: host)
        }

        setupShellData()

        putInformation("[*] Creating Connection")
        continueDecision = true

        termInterface
            .setupEventChain { [weak self] event in
                self?.handleTerminalEvent(event)
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
            let sessionName = tmuxSessionName ?? "default"
            let autoCreate = RayonStore.shared.tmuxAutoCreate

            let tmuxCmd = buildTmuxBootstrapCommand(sessionName: sessionName, autoCreate: autoCreate)

            if configuredSessionName.trimmingCharacters(in: .whitespacesAndNewlines) != sessionName {
                putInformation("[i] Normalized tmux session name to: \(sessionName)")
            }
            putInformation("[*] Attaching to tmux session: \(sessionName)")
            // Mark that we're in a tmux session
            Task { @MainActor [weak self] in
                self?.isInTmuxSession = true
            }
            insertInternalBuffer(tmuxCmd + "\n")
            if let shellIntegrationBootstrap {
                insertInternalBuffer(shellIntegrationBootstrap)
            }
        } else {
            if let shellIntegrationBootstrap {
                insertInternalBuffer(shellIntegrationBootstrap)
            }
        }

        shell.begin(
            withTerminalType: "xterm"
        ) {
            // Channel opened
        } withTerminalSize: { [weak self] in
            var size = self?.terminalSize ?? TerminalContext.defaultTerminalSize
            if size.width < 8 || size.height < 8 {
                // something went wrong
                size = TerminalContext.defaultTerminalSize
            }
            return size
        } withWriteDataBuffer: { [weak self] in
            self?.getBuffer() ?? ""
        } withOutputDataBuffer: { [weak self] output in
            Task { @MainActor in
                self?.termInterface.write(output)
            }
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

        // Disconnect Mosh session if active
        if let mosh = moshSession {
            mosh.disconnect()
            moshSession = nil
        }

        let shell = shell
        Task.detached(priority: .userInitiated) { [weak shell] in
            shell?.requestDisconnectAndWait()
        }
    }

    // MARK: - Tmux Commands

    /// Send tmux command using prefix key (Ctrl+B by default)
    func sendTmuxCommand(_ command: String) {
        guard isInTmuxSession else {
            putInformation("[!] " + String(localized: "Not in a tmux session"))
            return
        }
        // Send Ctrl+B followed by the command
        insertBuffer("\u{0002}" + command)
    }

    /// Send tmux command key sequence directly
    func sendTmuxKeySequence(_ sequence: String) {
        guard isInTmuxSession else {
            putInformation("[!] Not in a tmux session")
            return
        }
        insertBuffer(sequence)
    }

    /// Detach from tmux session
    func tmuxDetach() {
        sendTmuxCommand("d")
        // Update state after detach
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.isInTmuxSession = false
        }
    }

    /// Create new tmux window
    func tmuxNewWindow() {
        sendTmuxCommand("c")
    }

    /// List tmux windows
    func tmuxListWindows() {
        sendTmuxCommand("w")
    }

    /// Switch to next tmux window
    func tmuxNextWindow() {
        sendTmuxCommand("n")
    }

    /// Switch to previous tmux window
    func tmuxPreviousWindow() {
        sendTmuxCommand("p")
    }

    /// Kill current tmux window
    func tmuxKillWindow() {
        sendTmuxCommand("&")
    }

    /// Rename current tmux window
    func tmuxRenameWindow() {
        sendTmuxCommand(",")
    }

    /// Split pane horizontally
    func tmuxSplitHorizontal() {
        sendTmuxCommand("%")
    }

    /// Split pane vertically
    func tmuxSplitVertical() {
        sendTmuxCommand("\"")
    }

    /// List tmux sessions
    func tmuxListSessions() {
        sendTmuxCommand("s")
    }

    /// Switch to tmux command mode
    func tmuxCommandMode() {
        sendTmuxCommand(":")
    }
}

extension TerminalContext {
    struct DefaultPresent: View {
        let context: TerminalContext
        @Environment(\.presentationMode) var presentationMode

        var body: some View {
            NavigationView {
                TerminalView(context: context)
                    .toolbar {
                        ToolbarItem {
                            Button {
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                Image(systemName: "arrow.down.right.and.arrow.up.left")
                            }
                        }
                    }
            }
            .navigationViewStyle(StackNavigationViewStyle())
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

        // Remove CSI sequences (Control Sequence Introducer) with final bytes in 0x40...0x7E.
        result = result.replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)

        // Remove bracket sequences without ESC (sometimes captured separately)
        result = result.replacingOccurrences(of: "\\[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)

        // Remove character set designation sequences like (B or (0
        result = result.replacingOccurrences(of: "\u{1B}\\([0-9A-Za-z]", with: "", options: .regularExpression)

        // Remove backspace characters (used for character-by-character input rendering)
        result = result.replacingOccurrences(of: "\u{08}", with: "")

        // Clean up carriage returns - keep only linefeeds
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "")

        // Clean up multiple consecutive empty lines
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result
    }

    func splittingTrailingIncompleteANSIEscapeSequence() -> (completeText: String, trailingFragment: String) {
        guard let escapeIndex = lastIndex(of: "\u{1B}") else {
            return (self, "")
        }

        let tail = String(self[escapeIndex...])
        guard !tail.isCompleteANSIEscapeSequence else {
            return (self, "")
        }

        return (String(self[..<escapeIndex]), tail)
    }

    var isCompleteANSIEscapeSequence: Bool {
        guard first == "\u{1B}" else { return true }
        guard count >= 2 else { return false }

        let chars = Array(self)
        switch chars[1] {
        case "[":
            return chars.dropFirst(2).contains { character in
                guard let scalar = character.unicodeScalars.first?.value else { return false }
                return (0x40...0x7E).contains(scalar)
            }
        case "]":
            if contains("\u{07}") { return true }
            return contains("\u{1B}\\")
        case "(":
            return count >= 3
        default:
            return count >= 2
        }
    }

    func normalizedTerminalTranscript() -> String {
        var lines: [[Character]] = [[]]
        var currentLineIndex = 0
        var cursor = 0

        func currentLine() -> [Character] {
            lines[currentLineIndex]
        }

        func setCurrentLine(_ value: [Character]) {
            lines[currentLineIndex] = value
        }

        for character in self {
            switch character {
            case "\n":
                lines.append([])
                currentLineIndex += 1
                cursor = 0
            case "\r":
                cursor = 0
            case "\u{08}", "\u{7F}":
                guard cursor > 0 else { continue }
                var line = currentLine()
                line.remove(at: cursor - 1)
                setCurrentLine(line)
                cursor -= 1
            default:
                guard !character.isTerminalHistoryIgnoredControl else { continue }
                var line = currentLine()
                if cursor < line.count {
                    line[cursor] = character
                } else {
                    line.append(character)
                }
                setCurrentLine(line)
                cursor += 1
            }
        }

        return lines.map { String($0) }.joined(separator: "\n")
    }
}

private extension Character {
    var isTerminalHistoryIgnoredControl: Bool {
        unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x00...0x07, 0x0B, 0x0C, 0x0E...0x1F:
                return true
            default:
                return false
            }
        }
    }
}
