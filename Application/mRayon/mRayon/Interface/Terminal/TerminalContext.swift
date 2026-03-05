//
//  TerminalContext.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/3.
//

import NSRemoteShell
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
        defer { bufferAccessLock.unlock() }
        guard !closed else { return }

        // Add to data buffer (for SSH)
        _dataBuffer += str

        // Add to persistent history (for copy)
        historyLock.lock()
        outputHistory += str
        // Keep history at max size by removing old content
        if outputHistory.count > maxHistorySize {
            let removeCount = outputHistory.count - maxHistorySize
            outputHistory = String(outputHistory.dropFirst(removeCount))
        }
        historyLock.unlock()

        debugPrint("[TerminalContext] insertBuffer: \(str.prefix(50)), history size: \(outputHistory.count)")
        shell.explicitRequestStatusPickup()
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
            let sem = DispatchSemaphore(value: 0)
            mainActor {
                // Capture server output to history
                self?.addToHistory(output)
                // Display output
                self?.termInterface.write(output)
                sem.signal()
            }
            sem.wait()
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
        let shell = shell
        DispatchQueue.global().async { [weak shell] in
            shell?.requestDisconnectAndWait()
        }
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
