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

class TerminalContext: ObservableObject, Identifiable, Equatable {
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
    // Persistent history for copy functionality (keeps last 50000 chars)
    private var outputHistory: String = ""
    private let maxHistorySize = 50000
    private let historyLock = NSLock()

    func getBuffer() -> String {
        bufferAccessLock.lock()
        defer { bufferAccessLock.unlock() }
        let copy = _dataBuffer
        _dataBuffer = ""
        return copy
    }

    func peekBuffer() -> String {
        bufferAccessLock.lock()
        defer { bufferAccessLock.unlock() }
        return _dataBuffer
    }

    func insertBuffer(_ str: String) {
        bufferAccessLock.lock()
        if closed {
            bufferAccessLock.unlock()
            return
        }

        let shouldRouteToMosh = moshConnected && moshSession != nil
        if !shouldRouteToMosh {
            // Add to data buffer (for SSH)
            _dataBuffer += str
        }
        bufferAccessLock.unlock()

        // In Mosh mode, the server will echo back output which gets added to history.
        // So we should NOT add user input to history here to avoid duplication.
        // For SSH mode, we still add to history here since SSH output callback adds display output.
        if !shouldRouteToMosh {
            historyLock.lock()
            outputHistory += str
            // Keep history at max size by removing old content
            if outputHistory.count > maxHistorySize {
                let removeCount = outputHistory.count - maxHistorySize
                outputHistory = String(outputHistory.dropFirst(removeCount))
            }
            historyLock.unlock()

            debugPrint("[TerminalContext] insertBuffer: \(str.prefix(50)), history size: \(outputHistory.count)")
        }

        // Route to Mosh if connected, otherwise use SSH
        if shouldRouteToMosh, let mosh = moshSession {
            mosh.sendString(str)
        } else {
            shell.explicitRequestStatusPickup()
        }
    }

    func getOutputHistory() -> String {
        historyLock.lock()
        defer { historyLock.unlock() }
        return outputHistory
    }

    func addToHistory(_ str: String) {
        historyLock.lock()
        outputHistory += str
        // Keep history at max size by removing old content
        if outputHistory.count > maxHistorySize {
            let removeCount = outputHistory.count - maxHistorySize
            outputHistory = String(outputHistory.dropFirst(removeCount))
        }
        historyLock.unlock()

        debugPrint("[TerminalContext] addToHistory: \(str.prefix(50)), history size: \(outputHistory.count)")
    }

    func getOutputHistoryStrippedANSI() -> String {
        let history = getOutputHistory()
        return history.stripANSIEscapeCodes()
    }

    /// Handle output received from Mosh UDP session
    /// - Parameter str: The output string from Mosh
    func handleMoshOutput(_ str: String) {
        debugPrint("[Mosh] handleMoshOutput received: \(str.prefix(100).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r"))...")
        
        Task { @MainActor in
            self.termInterface.write(str)
        }
        
        addToHistory(str)
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

    init(machine: RDMachine) {
        self.machine = machine
        command = nil
        remoteType = .machine
        title = machine.name
        DispatchQueue.global(qos: .userInitiated).async {
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
        DispatchQueue.global(qos: .userInitiated).async {
            self.processBootstrap()
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

    // MARK: - Mosh Bootstrap

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

        termInterface.setTerminalFontSize(with: RayonStore.shared.terminalFontSize)

        DispatchQueue.main.async {
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
            .setupBellChain {
                // Terminal bell
            }
            .setupBufferChain { [weak self] buffer in
                debugPrint("[TerminalContext] setupBufferChain received: \(buffer.prefix(50).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r"))")
                self?.insertBuffer(buffer)
            }
            .setupTitleChain { [weak self] str in
                self?.title = str
            }
            .setupSizeChain { [weak self] size in
                self?.terminalSize = size
            }
            .setupCopyChain { [weak self] text in
                // Handle copy operation from terminal
                UIPasteboard.general.string = text
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
                            self?.moshConnected = true
                            self?.putInformation("[+] UDP socket ready")
                        case .disconnected:
                            self?.putInformation("[!] UDP disconnected")
                        case .failed(let error):
                            self?.putInformation("[!] UDP connection failed: \(error)")
                        }
                    },
                    receiveHandler: { @MainActor [weak self] output in
                        self?.handleMoshOutput(output)
                    }
                )
            } else {
                putInformation("[i] mosh-server not available, using SSH")
                moshConnected = false
            }
        }

        if moshModeActive, moshConnected {
            putInformation("[+] Mosh session active (SSH bootstrap detached)")
            while continueDecision {
                Thread.sleep(forTimeInterval: 0.05)
            }
            return
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
            // Mark that we're in a tmux session
            DispatchQueue.main.async {
                self.isInTmuxSession = true
            }
            insertBuffer(tmuxCmd + "\n")
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
                self?.addToHistory(output)
                self?.termInterface.write(output)
            }
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
        DispatchQueue.global().async { [weak shell] in
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isInTmuxSession = false
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

        // Remove CSI sequences (Control Sequence Introducer) like [1m, [31;1m, [?2004h, [K, [A
        result = result.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)

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
}
