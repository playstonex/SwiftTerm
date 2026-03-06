//
//  TerminalView.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/10.
//

import AVFoundation
import AppKit
import RayonModule
import Speech
import SwiftUI
import SwiftTerminal

struct TerminalView: View {
    @StateObject var context: TerminalManager.Context
    @ObservedObject var assistantManager = AssistantManager.shared

    @StateObject var store = RayonStore.shared
    @State var interfaceToken = UUID()
    @State var backgroundColor: Color = .black
    @StateObject private var speechInputController = TerminalSpeechInputController()
    @State private var liveTranscriptPreview: String = ""

    var body: some View {
        Group {
            if context.interfaceToken == interfaceToken {
                ZStack {
                    backgroundColor
                        .ignoresSafeArea()

                    context.termInterface
                        .padding(4)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: store.terminalFontSize) { oldValue, newValue in
                    context.termInterface.setTerminalFontSize(with: newValue)
                }
                .onChange(of: store.terminalFontName) { oldValue, newValue in
                    applyFont()
                }
                .onChange(of: store.terminalThemeName) { oldValue, newValue in
                    // Schedule background update on next runloop cycle
                    DispatchQueue.main.async {
                        applyTheme()
                    }
                }
                .onAppear {
                    context.termInterface.setTerminalFontSize(with: store.terminalFontSize)
                    context.termInterface.setTerminalFontName(with: store.terminalFontName)
                    // Set initial background color
                    if let color = Color(hex: store.terminalTheme.background) {
                        backgroundColor = color
                    }
                    // Delay theme application to ensure WebView is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        applyTheme()
                        applyFont()
                    }
                }
            } else {
                Text("Terminal Transfer To Another Window")
            }
        }
        .id(context.id) // Force view refresh for different contexts
        .onAppear {
            DispatchQueue.main.async {
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
                .help(speechInputController.isRecording ? "Stop Voice Input" : "Start Voice Input")
                .disabled(context.closed)
            }
            ToolbarItem {
                Button {
                    assistantManager.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
            }
            ToolbarItem {
                Button {
                    if context.closed {
                        DispatchQueue.global().async {
                            self.context.putInformation("[i] Reconnect will use the information you provide previously,")
                            self.context.putInformation("    if the machine was edited, create a new terminal.")
                            self.context.processBootstrap()
                        }
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
