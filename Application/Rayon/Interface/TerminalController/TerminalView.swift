//
//  TerminalView.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/10.
//

import AVFoundation
import AppKit
import NSRemoteShell
import RayonModule
import Speech
import SwiftUI
import SwiftTerminal
import WebKit

struct TerminalView: View {
    @StateObject var context: TerminalManager.Context
    @ObservedObject var assistantManager = AssistantManager.shared

    @StateObject var store = RayonStore.shared
    @State var interfaceToken = UUID()
    @State var backgroundColor: Color = .black
    @State private var terminalSize: CGSize = TerminalManager.Context.defaultTerminalSize
    @StateObject private var speechInputController = TerminalSpeechInputController()
    @State private var liveTranscriptPreview: String = ""
    @State private var isShowingWebBrowserSheet = false
    @State private var webBrowserPort: String = ""
    @State private var isShowingSearch = false
    @StateObject private var searchSession = TerminalSearchSession()
    @State private var resizeTask: Task<Void, Never>?
    @State private var showCopyToast = false
    private let terminalContentPadding = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    
    private var tmuxLogoImage: Image {
        if let img = NSImage(named: "tmux-logo") {
            let targetSize = NSSize(width: 16, height: 16)
            let resized = NSImage(size: targetSize)
            resized.lockFocus()
            img.draw(in: NSRect(origin: .zero, size: targetSize),
                     from: NSRect(origin: .zero, size: img.size),
                     operation: .sourceOver,
                     fraction: 1.0)
            resized.unlockFocus()
            resized.isTemplate = true
            return Image(nsImage: resized).renderingMode(.template)
        }
        return Image(systemName: "square.split.2x2")
    }

    var body: some View {
        Group {
            if context.interfaceToken == interfaceToken {
                GeometryReader { proxy in
                    ZStack {
                        backgroundColor
                            .ignoresSafeArea()

                        context.termInterface
                            .padding(terminalContentPadding)
                            .focusable()
                            .onChange(of: proxy.size) { _, _ in
                                guard context.interfaceToken == interfaceToken else { return }
                                // Debounce resize to avoid rapid buffer resizes during
                                // window dragging that corrupt terminal display.
                                resizeTask?.cancel()
                                resizeTask = Task {
                                    try? await Task.sleep(nanoseconds: 150_000_000)
                                    guard !Task.isCancelled else { return }
                                    guard context.interfaceToken == interfaceToken else { return }
                                    await updateTerminalSize()
                                }
                            }

                        // Copy toast bubble
                        if showCopyToast {
                            VStack {
                                HStack {
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11))
                                        Text("Copied")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                    .padding(.trailing, 12)
                                    .padding(.top, 4)
                                }
                                Spacer()
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if speechInputController.isRecording || !liveTranscriptPreview.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: speechInputController.isRecording ? "waveform.circle.fill" : "waveform.circle")
                                .foregroundStyle(speechInputController.isRecording ? .red : .secondary)
                            Text(
                                liveTranscriptPreview.isEmpty
                                    ? (speechInputController.isRecording ? "Listening..." : "Ready")
                                    : liveTranscriptPreview
                            )
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Clear") {
                                liveTranscriptPreview = ""
                                speechInputController.clearCurrentBuffer()
                            }
                            .buttonStyle(.borderless)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isShowingSearch {
                        TerminalSearchPanel(session: searchSession, isPresented: $isShowingSearch)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: store.terminalFontSize) { oldValue, newValue in
                    context.termInterface.setTerminalFontSize(with: newValue)
                    Task { await updateTerminalSize() }
                }
                .onChange(of: store.terminalFontName) { oldValue, newValue in
                    applyFont()
                    Task { await updateTerminalSize() }
                }
                .onChange(of: store.terminalThemeName) { oldValue, newValue in
                    applyTheme()
                }
                .onAppear {
                    context.termInterface.setTerminalFontSize(with: store.terminalFontSize)
                    context.termInterface.setTerminalFontName(with: store.terminalFontName)
                    // Set initial background color
                    if let color = Color(hex: store.terminalTheme.background) {
                        backgroundColor = color
                    }
                    applyTheme()
                    applyFont()
                    context.termInterface.refreshDisplay()
                    refreshSearchTranscript()
                    Task { await updateTerminalSize() }

                    // Auto-copy selected text and show toast
                    context.termInterface.onTextSelected { _ in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showCopyToast = true
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            withAnimation(.easeOut(duration: 0.2)) {
                                showCopyToast = false
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: TerminalManager.Context.historyRevisionNotification)) { notification in
                    guard notification.object as? UUID == context.id else { return }
                    refreshSearchTranscript()
                }
                .onChange(of: isShowingSearch) { _, isPresented in
                    if isPresented {
                        refreshSearchTranscript()
                    }
                }
            } else {
                Text("Terminal Transfer To Another Window")
            }
        }
        .id(context.id) // Force view refresh for different contexts
        .onAppear {
            Task { @MainActor in
                context.interfaceToken = interfaceToken
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    store.terminalFontSize -= 1
                } label: {
                    Label("Decrease Font Size", systemImage: "text.badge.minus")
                }
                .disabled(store.terminalFontSize <= 4)
            }
            ToolbarItem {
                Button {
                    RayonStore.shared.terminalFontSize += 1
                } label: {
                    Label("Increase Font Size", systemImage: "text.badge.plus")
                }
                .disabled(store.terminalFontSize >= 30)
            }
            ToolbarItem { // divider
                Button {} label: { HStack { Divider().frame(height: 15) } }
                    .disabled(true)
            }
            ToolbarItem {
                Button {
                    isShowingSearch.toggle()
                    if isShowingSearch {
                        refreshSearchTranscript()
                    }
                } label: {
                    Label("Search Transcript", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(context.closed && context.getOutputHistoryStrippedANSI().isEmpty)
            }
            // Tmux button - only shown when in a tmux session
            if context.isInTmuxSession {
                ToolbarItem {
                    Menu {
                        // Session actions
                        Button {
                            context.tmuxDetach()
                        } label: {
                            Label("Detach Session", systemImage: "rectangle.on.rectangle")
                        }
                        .accessibilityLabel("Detach from tmux session")

                        Divider()

                        // Window actions
                        Button {
                            context.tmuxNewWindow()
                        } label: {
                            Label("New Window", systemImage: "square.and.pencil")
                        }
                        .accessibilityLabel("Create new tmux window")

                        Button {
                            context.tmuxListWindows()
                        } label: {
                            Label("List Windows", systemImage: "list.bullet.rectangle")
                        }
                        .accessibilityLabel("List all tmux windows")

                        Button {
                            context.tmuxNextWindow()
                        } label: {
                            Label("Next Window", systemImage: "arrow.right.square")
                        }
                        .accessibilityLabel("Switch to next tmux window")

                        Button {
                            context.tmuxPreviousWindow()
                        } label: {
                            Label("Previous Window", systemImage: "arrow.left.square")
                        }
                        .accessibilityLabel("Switch to previous tmux window")

                        Button {
                            context.tmuxKillWindow()
                        } label: {
                            Label("Kill Current Window", systemImage: "xmark.square")
                        }
                        .accessibilityLabel("Kill current tmux window")

                        Button {
                            context.tmuxRenameWindow()
                        } label: {
                            Label("Rename Window", systemImage: "pencil.line")
                        }
                        .accessibilityLabel("Rename current tmux window")

                        Divider()

                        // Pane actions
                        Button {
                            context.tmuxSplitHorizontal()
                        } label: {
                            Label("Split Horizontal", systemImage: "rectangle.split.2x1")
                        }
                        .accessibilityLabel("Split pane horizontally")

                        Button {
                            context.tmuxSplitVertical()
                        } label: {
                            Label("Split Vertical", systemImage: "rectangle.split.1x2")
                        }
                        .accessibilityLabel("Split pane vertically")

                        Divider()

                        // Other
                        Button {
                            context.tmuxListSessions()
                        } label: {
                            Label("List Sessions", systemImage: "list.bullet")
                        }
                        .accessibilityLabel("List all tmux sessions")

                        Button {
                            context.tmuxCommandMode()
                        } label: {
                            Label("Command Mode", systemImage: "terminal")
                        }
                        .accessibilityLabel("Enter tmux command mode")
                    } label: {
                        tmuxLogoImage
                    }
                    .accessibilityLabel("Tmux Session Menu")
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            // Web Browser button
            ToolbarItem {
                Button {
                    webBrowserPort = ""
                    isShowingWebBrowserSheet = true
                } label: {
                    Label("Open Web Browser", systemImage: "globe")
                }
                .accessibilityLabel("Open Web Browser")
                .help("Open internal web browser for this server")
                .disabled(context.closed)
            }
            ToolbarItem {
                Button {
                    guard !context.closed else { return }
                    if speechInputController.isRecording {
                        speechInputController.stopAndCommit()
                    } else {
                        speechInputController.startRecognition(
                            onPartialTranscript: { partial in
                                liveTranscriptPreview = partial
                            },
                            onFinalTranscript: { transcript in
                                let payload = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !payload.isEmpty else { return }
                                safeWrite(payload)
                                liveTranscriptPreview = ""
                            }
                        )
                    }
                } label: {
                    Label(
                        speechInputController.isRecording ? "Stop Voice Input" : "Start Voice Input",
                        systemImage: speechInputController.isRecording ? "mic.fill" : "mic"
                    )
                }
                .accessibilityLabel(speechInputController.isRecording ? "Stop Voice Input" : "Start Voice Input")
                .help(speechInputController.isRecording ? "Stop Voice Input" : "Start Voice Input")
                .disabled(context.closed)
            }
            ToolbarItem {
                Button {
                    assistantManager.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .accessibilityLabel("Toggle Assistant Panel")
            }
            ToolbarItem {
                Button {
                    if context.closed {
                        context.reconnectInBackground()
                    } else {
                        UIBridge.requiresConfirmation(
                            message: "Are you sure you want to close the terminal?"
                        ) { y in
                            if y { context.processShutdown() }
                        }
                    }
                } label: {
                    if context.closed {
                        Label("Reconnect", systemImage: "arrow.counterclockwise")
                    } else {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
        }
        .navigationTitle(context.navigationTitle)
        .navigationSubtitle(context.navigationSubtitle)
        .sheet(isPresented: $isShowingWebBrowserSheet) {
            WebBrowserPortInputSheet(
                port: $webBrowserPort,
                machine: context.machine,
                isPresented: $isShowingWebBrowserSheet
            )
        }
        .onDisappear {
            speechInputController.stopAndDiscard()
            liveTranscriptPreview = ""
        }
    }

    func safeWriteBase64(_ base64: String) {
        guard let data = Data(base64Encoded: base64),
              let str = String(data: data, encoding: .utf8)
        else {
            return
        }
        safeWrite(str)
    }

    func safeWrite(_ str: String) {
        guard !context.closed else {
            return
        }
        guard context.interfaceToken == interfaceToken else {
            return
        }
        context.insertBuffer(str)
    }

    func makeKeyboardFloatingButton(_ image: String, block: @escaping () -> Void) -> some View {
        Button {
            guard !context.closed else { return }
            block()
        } label: {
            Image(systemName: image)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .animation(.spring(), value: context.interfaceDisabled)
        .disabled(context.interfaceDisabled)
    }

    func applyTheme() {
        let theme = store.terminalTheme

        // Update background color state
        if let color = Color(hex: theme.background) {
            backgroundColor = color
        }

        context.termInterface.setTerminalTheme(
            foreground: theme.foreground,
            background: theme.background,
            cursor: theme.cursor,
            black: theme.black,
            red: theme.red,
            green: theme.green,
            yellow: theme.yellow,
            blue: theme.blue,
            magenta: theme.magenta,
            cyan: theme.cyan,
            white: theme.white,
            brightBlack: theme.brightBlack,
            brightRed: theme.brightRed,
            brightGreen: theme.brightGreen,
            brightYellow: theme.brightYellow,
            brightBlue: theme.brightBlue,
            brightMagenta: theme.brightMagenta,
            brightCyan: theme.brightCyan,
            brightWhite: theme.brightWhite
        )
    }

    func applyFont() {
        let fontName = store.terminalFontName
        context.termInterface.setTerminalFontName(with: fontName)
    }

    func refreshSearchTranscript() {
        let context = context
        Task.detached(priority: .utility) {
            let stripped = context.getOutputHistoryStrippedANSI()
            await MainActor.run {
                searchSession.updateTranscript(stripped)
            }
        }
    }

    @MainActor
    func updateTerminalSize() async {
        let newSize = context.termInterface.requestTerminalSize()

        guard newSize.width > 5, newSize.height > 5,
              newSize != terminalSize else { return }

        guard context.interfaceToken == interfaceToken else { return }
        terminalSize = newSize
        context.terminalSize = newSize
        context.shell.explicitRequestStatusPickup()
    }
}

@MainActor
final class TerminalSpeechInputController: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechRecognizer: SFSpeechRecognizer?
    private var fullTranscript = ""
    private var committedPrefix = ""
    private var liveTranscript = ""
    private var onPartialTranscript: ((String) -> Void)?
    private var onFinalTranscript: ((String) -> Void)?

    func startRecognition(
        onPartialTranscript: @escaping (String) -> Void,
        onFinalTranscript: @escaping (String) -> Void
    ) {
        guard !isRecording else { return }
        guard RayonStore.shared.speechInputEngine != "disabled" else {
            UIBridge.presentError(with: "Voice disabled in Settings")
            return
        }
        self.onPartialTranscript = onPartialTranscript
        self.onFinalTranscript = onFinalTranscript
        self.onPartialTranscript?("")

        Task {
            do {
                try await requestPermissions()
                try configureAndStart()
            } catch {
                handlePermissionError(error)
            }
        }
    }

    func stopAndCommit() {
        stop(commit: true)
    }

    func stopAndDiscard() {
        stop(commit: false)
    }

    func clearCurrentBuffer() {
        if !isRecording {
            liveTranscript = ""
            onPartialTranscript?("")
            return
        }
        committedPrefix = fullTranscript
        liveTranscript = ""
        onPartialTranscript?("")
    }

    private func stop(commit: Bool) {
        guard isRecording || !liveTranscript.isEmpty || !fullTranscript.isEmpty else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false

        if commit {
            let payload = currentDeltaTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
            if !payload.isEmpty {
                onFinalTranscript?(payload)
            }
        } else {
            onPartialTranscript?("")
        }
        fullTranscript = ""
        committedPrefix = ""
        liveTranscript = ""
    }

    private func requestPermissions() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { permission in
                    continuation.resume(returning: permission)
                }
            }
            guard granted else { throw SpeechError.micDeniedAfterPrompt }
        case .denied, .restricted:
            throw SpeechError.micDeniedNeedsSettings
        @unknown default:
            throw SpeechError.micDeniedNeedsSettings
        }

        switch await withCheckedContinuation({ continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }) {
        case .authorized:
            break
        case .notDetermined:
            throw SpeechError.speechDeniedAfterPrompt
        case .denied, .restricted:
            throw SpeechError.speechDeniedNeedsSettings
        @unknown default:
            throw SpeechError.speechDeniedNeedsSettings
        }
    }

    private func configureAndStart() throws {
        let localeIdentifier = RayonStore.shared.speechInputLocaleIdentifier
        let targetLocale = localeIdentifier == "system" ? Locale.current : Locale(identifier: localeIdentifier)
        speechRecognizer = SFSpeechRecognizer(locale: targetLocale) ?? SFSpeechRecognizer(locale: .current)
        guard let speechRecognizer else { throw SpeechError.unavailable }
        guard speechRecognizer.isAvailable else { throw SpeechError.unavailable }

        fullTranscript = ""
        committedPrefix = ""
        liveTranscript = ""
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputNode.outputFormat(forBus: 0)
        ) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.fullTranscript = result.bestTranscription.formattedString
                self.liveTranscript = self.currentDeltaTranscript()
                self.onPartialTranscript?(self.liveTranscript)
                if result.isFinal {
                    Task { @MainActor in
                        self.stop(commit: true)
                    }
                    return
                }
            }
            if error != nil {
                Task { @MainActor in
                    self.stop(commit: true)
                }
            }
        }
    }

    private enum SpeechError: Error {
        case micDeniedAfterPrompt
        case micDeniedNeedsSettings
        case speechDeniedAfterPrompt
        case speechDeniedNeedsSettings
        case unavailable
    }

    private func handlePermissionError(_ error: Error) {
        guard let speechError = error as? SpeechError else {
            UIBridge.presentError(with: "Voice input is unavailable")
            return
        }
        switch speechError {
        case .micDeniedAfterPrompt:
            UIBridge.presentError(with: "Microphone access is required for voice input.")
        case .speechDeniedAfterPrompt:
            UIBridge.presentError(with: "Speech recognition access is required for voice input.")
        case .micDeniedNeedsSettings:
            promptOpenPrivacySettings(
                message: "Microphone access is denied. Open System Settings to enable it?",
                privacyAnchor: "Privacy_Microphone"
            )
        case .speechDeniedNeedsSettings:
            promptOpenPrivacySettings(
                message: "Speech recognition access is denied. Open System Settings to enable it?",
                privacyAnchor: "Privacy_SpeechRecognition"
            )
        case .unavailable:
            UIBridge.presentError(with: "Speech recognizer is currently unavailable.")
        }
    }

    private func promptOpenPrivacySettings(message: String, privacyAnchor: String) {
        UIBridge.requiresConfirmation(message: message) { confirmed in
            guard confirmed else { return }
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(privacyAnchor)") else {
                return
            }
            UIBridge.open(url: url)
        }
    }

    private func currentDeltaTranscript() -> String {
        if committedPrefix.isEmpty { return fullTranscript }
        guard fullTranscript.hasPrefix(committedPrefix) else {
            committedPrefix = ""
            return fullTranscript
        }
        return String(fullTranscript.dropFirst(committedPrefix.count))
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Web Browser Port Input Sheet

private struct WebBrowserPortInputSheet: View {
    @Binding var port: String
    let machine: RDMachine
    @Binding var isPresented: Bool

    @StateObject private var browserManager = WebBrowserManagerMac.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Open Web Browser")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Remote Port")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Port Number", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .onSubmit {
                        openBrowser()
                    }

                Text("Enter the port number on the remote server to forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Server:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(machine.name)
                }
                HStack {
                    Text("Address:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(machine.remoteAddress)
                }
            }
            .font(.subheadline)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Open") {
                    openBrowser()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(port.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }

    private func openBrowser() {
        guard let portNumber = Int(port), portNumber > 0, portNumber <= 65535 else {
            UIBridge.presentError(with: "Invalid port number")
            return
        }

        // Create a browser session for this terminal's machine
        let session = RDBrowserSession(
            name: "\(machine.name):\(portNumber)",
            usingMachine: machine.id,
            remoteHost: "127.0.0.1",
            remotePort: portNumber
        )

        // Save the session
        RayonStore.shared.browserSessionGroup.insert(session)

        // Start the browser
        if let context = browserManager.begin(for: session) {
            dismiss()
            // Open browser in new window
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                let browserView = WebBrowserViewMac(context: context)
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                    styleMask: [.titled, .closable, .resizable, .miniaturizable],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.center()
                window.title = context.session.name.isEmpty ? "Web Browser" : context.session.name
                window.contentView = NSHostingView(rootView: browserView)
                let delegate = WebBrowserWindowDelegate(context: context)
                WebBrowserWindowDelegate.store(delegate, for: context.id)
                window.delegate = delegate
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - Web Browser Window Delegate

private class WebBrowserWindowDelegate: NSObject, NSWindowDelegate {
    private weak var context: WebBrowserContextMac?

    @MainActor
    private static var delegates: NSMapTable<NSUUID, WebBrowserWindowDelegate> = {
        let table = NSMapTable<NSUUID, WebBrowserWindowDelegate>(keyOptions: .strongMemory, valueOptions: .weakMemory)
        return table
    }()

    private let contextId: UUID

    init(context: WebBrowserContextMac) {
        self.context = context
        self.contextId = context.id
        super.init()
    }

    @MainActor
    static func store(_ delegate: WebBrowserWindowDelegate, for id: UUID) {
        delegates.setObject(delegate, forKey: id as NSUUID)
    }

    @MainActor
    static func remove(for id: UUID) {
        delegates.removeObject(forKey: id as NSUUID)
    }

    @MainActor
    static func get(for id: UUID) -> WebBrowserWindowDelegate? {
        let delegate = delegates.object(forKey: id as NSUUID)
        return delegate
    }

    func windowWillClose(_ notification: Notification) {
        let id = contextId
        // Defer delegate self-destruction until AppKit finishes its window closed event loop.
        // Doing this synchronously while AppKit is iterating delegates can crash inside libobjc!
        Task { @MainActor in
            WebBrowserWindowDelegate.remove(for: id)
            WebBrowserManagerMac.shared.end(for: id)
        }
    }
}

// MARK: - Web Browser Manager (macOS)

@MainActor
private class WebBrowserManagerMac: ObservableObject {
    static let shared = WebBrowserManagerMac()

    private init() {}

    @Published var browsers: [WebBrowserContextMac] = []

    var usedLocalPorts: Set<Int> {
        Set(browsers.map { $0.localPort }.filter { $0 > 0 })
    }

    func begin(for session: RDBrowserSession) -> WebBrowserContextMac? {
        // Check if session already has a running browser
        if let existing = browsers.first(where: { $0.id == session.id }) {
            return existing
        }

        guard session.isValid() else {
            UIBridge.presentError(with: "Invalid browser session configuration")
            return nil
        }

        let context = WebBrowserContextMac(session: session)
        browsers.append(context)

        // Start connection in background
        context.connectAndForward()

        return context
    }

    func end(for sessionId: UUID) {
        guard let index = browsers.firstIndex(where: { $0.id == sessionId }) else {
            return
        }

        let context = browsers.remove(at: index)
        context.disconnect()
    }

    func endAll() {
        for context in browsers {
            context.disconnect()
        }
        browsers.removeAll()
    }

    func browser(for sessionId: UUID) -> WebBrowserContextMac? {
        browsers.first(where: { $0.id == sessionId })
    }

    func isRunning(sessionId: UUID) -> Bool {
        browsers.contains(where: { $0.id == sessionId })
    }
}

// MARK: - Web Browser Context (macOS)

private class WebBrowserContextMac: ObservableObject, Identifiable {
    let id: UUID
    let session: RDBrowserSession
    let machine: RDMachine
    let shell: NSRemoteShell

    @Published var connectionState: ConnectionState = .disconnected
    @Published var localPort: Int = 0
    @Published var errorMessage: String?

    private var webView: WKWebView?
    private var isClosed: Bool = false

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case authenticating
        case creatingTunnel
        case connected
        case error(String)

        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.authenticating, .authenticating),
                 (.creatingTunnel, .creatingTunnel),
                 (.connected, .connected):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    var localUrl: URL? {
        guard localPort > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(localPort)")
    }

    init(session: RDBrowserSession) {
        self.id = session.id
        self.session = session
        self.shell = .init()

        guard let machineId = session.usingMachine,
              let machine = RayonStore.shared.machineGroup[machineId].isNotPlaceholder() ? RayonStore.shared.machineGroup[machineId] : nil
        else {
            self.machine = RDMachine()
            self.connectionState = .error("Invalid machine configuration")
            return
        }
        self.machine = machine
    }

    private func updateConnectionState(_ state: ConnectionState, errorMessage: String? = nil) {
        Task { @MainActor [weak self, state, errorMessage] in
            self?.connectionState = state
            self?.errorMessage = errorMessage
        }
    }

    private func updateConnectionSetup(localPort: Int, state: ConnectionState) {
        Task { @MainActor [weak self, localPort, state] in
            self?.localPort = localPort
            self?.connectionState = state
        }
    }

    @MainActor
    func allocateLocalPort() -> Int {
        let usedPorts = WebBrowserManagerMac.shared.usedLocalPorts
        let preferredPorts = [3000, 3001, 3002, 4000, 5000, 5001, 8000, 8080, 8081, 8888, 9000]
        for port in preferredPorts {
            if !usedPorts.contains(port) {
                return port
            }
        }

        for port in 10000...65535 {
            if !usedPorts.contains(port) {
                return port
            }
        }
        return 0
    }

    @MainActor
    func connectAndForward() {
        guard session.isValid() else {
            updateConnectionState(.error("Invalid session configuration"), errorMessage: "Invalid session configuration")
            return
        }

        let port = allocateLocalPort()
        guard port > 0 else {
            updateConnectionState(.error("Failed to allocate local port"), errorMessage: "Failed to allocate local port")
            return
        }

        updateConnectionSetup(localPort: port, state: .connecting)

        Task.detached(priority: .userInitiated) { [weak self] in
            self?.performConnection(localPort: port)
        }
    }

    private func performConnection(localPort: Int) {
        shell
            .setupConnectionHost(machine.remoteAddress)
            .setupConnectionPort(NSNumber(value: Int(machine.remotePort) ?? 22))
            .setupConnectionTimeout(RayonStore.shared.timeoutNumber)
            .requestConnectAndWait()

        let remoteAddress = machine.remoteAddress
        let remotePort = machine.remotePort

        guard shell.isConnected else {
            let message = "Failed to connect to \(remoteAddress):\(remotePort)"
            updateConnectionState(.error(message), errorMessage: message)
            return
        }

        updateConnectionState(.authenticating)

        if let identityId = machine.associatedIdentity,
           let uuid = UUID(uuidString: identityId) {
            let identity = RayonStore.shared.identityGroup[uuid]
            guard !identity.username.isEmpty else {
                updateConnectionState(.error("Invalid identity configuration"), errorMessage: "Invalid identity configuration")
                return
            }
            identity.callAuthenticationWith(remote: shell)
        } else {
            for identity in RayonStore.shared.identityGroupForAutoAuth {
                identity.callAuthenticationWith(remote: shell)
                if shell.isAuthenticated {
                    break
                }
            }
        }

        guard shell.isAuthenticated else {
            updateConnectionState(.error("Authentication failed"), errorMessage: "Authentication failed")
            return
        }

        updateConnectionState(.creatingTunnel)

        shell.createPortForward(
            withLocalPort: NSNumber(value: localPort),
            withForwardTargetHost: session.remoteHost,
            withForwardTargetPort: NSNumber(value: session.remotePort)
        ) { [weak self] in
            self?.updateConnectionState(.connected, errorMessage: nil)
        } withContinuationHandler: { [weak self] in
            guard let self = self else { return false }
            return !self.isClosed
        }
    }

    func disconnect() {
        self.isClosed = true
        let cleanup = { [weak self] in
            guard let self else { return }
            self.webView?.stopLoading()
            self.webView?.loadHTMLString("", baseURL: nil)
            self.webView = nil
            self.connectionState = .disconnected
            self.localPort = 0
        }

        Task { @MainActor in
            cleanup()
        }

        Task.detached(priority: .userInitiated) { [self] in
            // Keep self securely alive to safely destruct NSRemoteShell
            self.shell.requestDisconnectAndWait()
            self.shell.destroyPermanently()
            await MainActor.run { _ = self }
        }
    }

    func getWebView() -> WKWebView {
        if let existing = webView {
            return existing
        }

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        // Don't set navigationDelegate here - let WebViewRepresentableMac's coordinator handle it
        self.webView = webView

        return webView
    }

    func load(url: URL) {
        let webView = getWebView()
        webView.load(URLRequest(url: url))
    }

    func loadInitialPage() {
        guard let url = localUrl else { return }

        if let lastUrl = session.lastUrl,
           let lastUrlObj = URL(string: lastUrl),
           lastUrl.hasPrefix("http://127.0.0.1:\(localPort)") || lastUrl.hasPrefix("http://localhost:\(localPort)") {
            load(url: lastUrlObj)
        } else {
            load(url: url)
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func refresh() { webView?.reload() }

    var currentUrl: String? { webView?.url?.absoluteString }
    var canGoBack: Bool { webView?.canGoBack ?? false }
    var canGoForward: Bool { webView?.canGoForward ?? false }
    var isLoading: Bool { webView?.isLoading ?? false }

    func updateSessionLastUrl() {
        guard let url = currentUrl else { return }
        var updatedSession = session
        updatedSession.lastUrl = url
        RayonStore.shared.browserSessionGroup.insert(updatedSession)
    }
}

// MARK: - Web Browser View (macOS)

private struct WebBrowserViewMac: View {
    @ObservedObject var context: WebBrowserContextMac
    @Environment(\.dismiss) var dismiss

    @State private var urlText: String = ""
    @State private var isLoading: Bool = false
    @State private var estimatedProgress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            urlBar
            webViewContainer
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    context.disconnect()
                    dismiss()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            }
        }
        .onAppear {
            setupWebView()
        }
        .onDisappear {
            context.updateSessionLastUrl()
        }
    }

    private var navigationTitle: String {
        let portInfo = context.localPort > 0 ? "localhost:\(context.localPort)" : "connecting..."
        if context.session.name.isEmpty {
            return portInfo
        }
        return "\(context.session.name) - \(portInfo)"
    }

    var statusBar: some View {
        Group {
            switch context.connectionState {
            case .disconnected:
                HStack {
                    Image(systemName: "circle.dashed")
                    Text("Disconnected")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.2))
            case .connecting:
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Connecting to \(context.machine.remoteAddress)...")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.2))
            case .authenticating:
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Authenticating...")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.2))
            case .creatingTunnel:
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Creating tunnel to \(context.session.remoteHost):\(context.session.remotePort)...")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.2))
            case .connected:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connected: localhost:\(context.localPort) → \(context.session.remoteHost):\(context.session.remotePort)")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15))
            case .error(let message):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .foregroundColor(.red)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.15))
            }
        }
        .font(.caption)
    }

    var urlBar: some View {
        HStack(spacing: 8) {
            Button { context.goBack() } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(context.canGoBack ? .accentColor : .gray)
            }
            .disabled(!context.canGoBack)

            Button { context.goForward() } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(context.canGoForward ? .accentColor : .gray)
            }
            .disabled(!context.canGoForward)

            Button { context.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.accentColor)
            }

            TextField("URL", text: $urlText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit { loadUrl() }

            Button { loadUrl() } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    var webViewContainer: some View {
        ZStack {
            if context.connectionState == .connected {
                WebViewRepresentableMac(
                    webView: context.getWebView(),
                    isLoading: $isLoading,
                    estimatedProgress: $estimatedProgress,
                    urlText: $urlText
                )

                if isLoading {
                    VStack {
                        ProgressView(value: estimatedProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 20) {
                    if case .error(let message) = context.connectionState {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        Text("Connection Failed")
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            context.connectAndForward()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Connecting...")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    private func setupWebView() {
        if context.connectionState == .disconnected ||
           context.connectionState == .error("") {
            context.connectAndForward()
        }
    }

    private func loadUrl() {
        guard !urlText.isEmpty else { return }

        var urlString = urlText
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://\(urlString)"
        }

        guard let url = URL(string: urlString) else {
            UIBridge.presentError(with: "Invalid URL")
            return
        }

        context.load(url: url)
    }
}

// MARK: - WebView Representable (macOS)

private struct WebViewRepresentableMac: NSViewRepresentable {
    let webView: WKWebView
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var urlText: String

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.navigationDelegate !== context.coordinator {
            webView.navigationDelegate = context.coordinator
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentableMac

        init(_ parent: WebViewRepresentableMac) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            Task { @MainActor in
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            Task { @MainActor in
                self.parent.isLoading = false
                self.parent.estimatedProgress = 1.0
                if let url = webView.url {
                    self.parent.urlText = url.absoluteString
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            Task { @MainActor in
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            Task { @MainActor in
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}
