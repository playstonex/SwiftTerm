//
//  TerminalView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import RayonModule
import SwiftUI
import AVFoundation
import Speech
import UIKit
import SwiftTerminal

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let length = hexSanitized.count
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

struct TerminalView: View {
    @StateObject var context: TerminalContext

    @State var interfaceToken = UUID()

    @State var terminalSize: CGSize = TerminalContext.defaultTerminalSize

    @StateObject var store = RayonStore.shared
    @ObservedObject var assistantManager = AssistantManager.shared

    @Environment(\.dismiss) var dismiss

    @State private var isShowingToolbarSettings = false
    @State private var isShowingKillWindowConfirm = false
    @State private var isShowingWebBrowserSheet = false
    @State private var webBrowserPort: String = ""
    @StateObject private var speechInputController = TerminalSpeechInputController()
    @State private var liveTranscriptPreview: String = ""
    @State private var isKeyboardVisible = false
    @State private var isShowingSearch = false
    @StateObject private var searchSession = TerminalSearchSession()
    @State private var refreshSearchTask: Task<Void, Never>?
    @State private var resizeTask: Task<Void, Never>?
    private let terminalContentPadding = EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)

    var body: some View {
        Group {
            if context.interfaceToken == interfaceToken {
                GeometryReader { r in
                    ZStack {
                        // Background
                        Color(hex: store.terminalTheme.background)
                            .ignoresSafeArea()

                        // Terminal view
                        context.termInterface
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(terminalContentPadding)
                            .onChange(of: r.size) { _, _ in
                                guard context.interfaceToken == interfaceToken else { return }
                                resizeTask?.cancel()
                                resizeTask = Task {
                                    try? await Task.sleep(nanoseconds: 250_000_000)
                                    guard !Task.isCancelled else { return }
                                    guard context.interfaceToken == interfaceToken else { return }
                                    await updateTerminalSize()
                                }
                            }
                            .onAppear {
                                context.termInterface.setTerminalFontSize(with: store.terminalFontSize)
                                context.termInterface.setTerminalFontName(with: store.terminalFontName)
                                context.termInterface.setReturnKeySendsLineFeed(store.terminalReturnKeySendsLineFeed)
                                // Apply theme immediately without delay
                                applyTheme()
                                context.termInterface.refreshDisplay()
                                refreshSearchTranscript()
                                Task { @MainActor in
                                    await updateTerminalSize()
                                }
                            }
                            .onChange(of: store.terminalFontSize) { _, newValue in
                                context.termInterface.setTerminalFontSize(with: newValue)
                            }
                            .onChange(of: store.terminalFontName) { _, _ in
                                applyFont()
                            }
                            .onChange(of: store.terminalThemeName) { _, _ in
                                applyTheme()
                            }
                            .onChange(of: store.terminalReturnKeySendsLineFeed) { _, newValue in
                                context.termInterface.setReturnKeySendsLineFeed(newValue)
                            }
                            .onChange(of: context.historyRevision) { _, _ in
                                refreshSearchTask?.cancel()
                                refreshSearchTask = Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    guard !Task.isCancelled else { return }
                                    refreshSearchTranscript()
                                }
                            }
                            .onChange(of: isShowingSearch) { _, isPresented in
                                if isPresented {
                                    refreshSearchTranscript()
                                }
                            }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if isShowingSearch {
                            TerminalSearchPanel(session: searchSession, isPresented: $isShowingSearch)
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !context.destroyedSession {
                            VStack(spacing: 6) {
                                if speechInputController.isRecording || !liveTranscriptPreview.isEmpty {
                                    LiveTranscriptBar(
                                        text: liveTranscriptPreview,
                                        onSendWithReturn: {
                                            let payload = liveTranscriptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !payload.isEmpty else { return }
                                            self.safeWrite(payload + "\n")
                                            liveTranscriptPreview = ""
                                            speechInputController.clearCurrentBuffer()
                                            UIBridge.presentSuccess(with: String(localized: "Sent+Enter"))
                                        },
                                        onSendWithoutReturn: {
                                            let payload = liveTranscriptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !payload.isEmpty else { return }
                                            self.safeWrite(payload)
                                            liveTranscriptPreview = ""
                                            speechInputController.clearCurrentBuffer()
                                            UIBridge.presentSuccess(with: String(localized: "Sent"))
                                        },
                                        onClear: {
                                            liveTranscriptPreview = ""
                                            speechInputController.clearCurrentBuffer()
                                        }
                                    )
                                }
                                AccessoryBar(
                                    isReconnecting: context.closed,
                                    isVoiceRecording: speechInputController.isRecording,
                                    isKeyboardVisible: isKeyboardVisible,
                                    controlKey: .constant(""),
                                    isShowingControlPopover: .constant(false),
                                    isShowingToolbarSettings: $isShowingToolbarSettings,
                                    keyStore: ToolbarKeyStore.shared,
                                    onReconnect: {
                                        context.reconnectInBackground()
                                    },
                                    onClose: {
                                        if context.closed {
                                            dismiss()
                                            TerminalManager.shared.end(for: context.id)
                                        } else {
                                            UIBridge.requiresConfirmation(
                                                message: String(localized: "Are you sure you want to close this session?")
                                            ) { yes in
                                                if yes { context.processShutdown() }
                                            }
                                        }
                                    },
                                    onPaste: {
                                        guard let str = UIPasteboard.general.string else {
                                            UIBridge.presentError(with: String(localized: "Empty Pasteboard"))
                                            return
                                        }
                                        UIBridge.requiresConfirmation(
                                            message: String(localized: "Are you sure you want to paste following string?\n\n\(str)")
                                        ) { yes in
                                            if yes { self.safeWrite(str) }
                                        }
                                    },
                                    onCopy: {
                                        let transcript = context.getOutputHistoryStrippedANSI()
                                        if !transcript.isEmpty {
                                            TerminalClipboardPayload(plainText: transcript).writeToPasteboard()
                                            UIBridge.presentSuccess(with: String(localized: "Copied"))
                                        } else {
                                            UIBridge.presentError(with: String(localized: "Terminal content is empty"))
                                        }
                                    },
                                    onSendKey: { key in
                                        self.safeWrite(key)
                                    },
                                    onKeyboardToggle: {
                                        if isKeyboardVisible {
                                            context.termInterface.dismissKeyboard()
                                        } else {
                                            context.termInterface.activateKeyboard()
                                        }
                                    },
                                    onVoiceInput: {
                                        if speechInputController.isRecording {
                                            speechInputController.stopAndCommit()
                                            return
                                        }
                                        speechInputController.startRecognition(
                                            onPartialTranscript: { partial in
                                                liveTranscriptPreview = partial
                                            },
                                            onFinalTranscript: { transcript in
                                                let payload = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                                                liveTranscriptPreview = payload
                                            }
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
            } else {
                PlaceholderView("Terminal Transfer To Another Window", img: .emptyWindow)
            }
        }
        .id(context.id) // Force view refresh for different contexts
        .disabled(context.destroyedSession)
        .onAppear {
            Task { @MainActor in
                context.interfaceToken = interfaceToken
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            handleKeyboardTransition(notification: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            handleKeyboardTransition(notification: notification)
        }
        .navigationTitle(context.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(context.navigationTitle)
                    .font(.headline)
                    .foregroundStyle(Color(hex: store.terminalTheme.foreground))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Tmux button - only show when in tmux session
                    if context.isInTmuxSession {
                        Menu {
                            // Session actions
                            Button {
                                context.tmuxDetach()
                            } label: {
                                Label(String(localized: "Detach Session"), systemImage: "rectangle.on.rectangle")
                            }

                            Divider()

                            // Window actions
                            Button {
                                context.tmuxNewWindow()
                            } label: {
                                Label(String(localized: "New Window"), systemImage: "square.and.pencil")
                            }

                            Button {
                                context.tmuxListWindows()
                            } label: {
                                Label(String(localized: "List Windows"), systemImage: "list.bullet.rectangle")
                            }

                            Button {
                                context.tmuxNextWindow()
                            } label: {
                                Label(String(localized: "Next Window"), systemImage: "arrow.right.square")
                            }

                            Button {
                                context.tmuxPreviousWindow()
                            } label: {
                                Label(String(localized: "Previous Window"), systemImage: "arrow.left.square")
                            }

                            Button {
                                isShowingKillWindowConfirm = true
                            } label: {
                                Label(String(localized: "Kill Current Window"), systemImage: "xmark.square")
                            }

                            Button {
                                context.tmuxRenameWindow()
                            } label: {
                                Label(String(localized: "Rename Window"), systemImage: "pencil.line")
                            }

                            Divider()

                            // Pane actions
                            Button {
                                context.tmuxSplitHorizontal()
                            } label: {
                                Label(String(localized: "Split Horizontal"), systemImage: "rectangle.split.2x1")
                            }

                            Button {
                                context.tmuxSplitVertical()
                            } label: {
                                Label(String(localized: "Split Vertical"), systemImage: "rectangle.split.1x2")
                            }

                            Divider()

                            // Session list and command mode
                            Button {
                                context.tmuxListSessions()
                            } label: {
                                Label(String(localized: "List Sessions"), systemImage: "list.bullet")
                            }

                            Button {
                                context.tmuxCommandMode()
                            } label: {
                                Label(String(localized: "Command Mode"), systemImage: "terminal")
                            }
                        } label: {
                            Image(systemName: "square.split.2x2")
                        }
                        .alert(String(localized: "Kill Current Window?"), isPresented: $isShowingKillWindowConfirm) {
                            Button(String(localized: "Cancel"), role: .cancel) {}
                            Button(String(localized: "Kill"), role: .destructive) {
                                context.tmuxKillWindow()
                            }
                        } message: {
                            Text(String(localized: "Are you sure you want to kill the current tmux window?"))
                        }
                    }

                    // Internal Web Browser button
                    Button {
                        webBrowserPort = ""
                        isShowingWebBrowserSheet = true
                    } label: {
                        Image(systemName: "globe")
                    }

                    Button {
                        isShowingSearch.toggle()
                        if isShowingSearch {
                            refreshSearchTranscript()
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }

                    Button {
                        assistantManager.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                }
            }
        }
        .onChange(of: store.terminalThemeName) { _, _ in
            // Force toolbar update when theme changes
        }
        .onChange(of: store.speechInputEngine) { _, _ in
            // Update voice key availability when speech input setting changes
            ToolbarKeyStore.shared.updateVoiceKeyAvailability()
        }
        .onChange(of: store.speechInputLocaleIdentifier) { _, _ in
            // Update voice key availability when locale setting changes
            ToolbarKeyStore.shared.updateVoiceKeyAvailability()
        }
        .sheet(isPresented: $isShowingToolbarSettings) {
            ToolbarSettingsView(keyStore: ToolbarKeyStore.shared)
        }
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

    @MainActor
    func updateTerminalSize() async {
        let newSize = context.termInterface.requestTerminalSize()

        guard newSize.width >= 8, newSize.height >= 8,
              newSize != terminalSize else { return }

        guard context.interfaceToken == interfaceToken else { return }
        terminalSize = newSize
        context.shell.explicitRequestStatusPickup()
    }

    func applyTheme() {
        let theme = store.terminalTheme
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
        searchSession.updateTranscript(context.getOutputHistoryStrippedANSI())
    }

    private func handleKeyboardTransition(notification: Notification) {
        #if canImport(UIKit)
        let userInfo = notification.userInfo ?? [:]
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        // Resize after the keyboard animation settles so the visible rows match the actual
        // unobscured terminal area. The terminal view preserves its current viewport on resize.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.05) * 1_000_000_000))
            context.termInterface.refreshDisplay()
            Task { await updateTerminalSize() }
        }
        #endif
    }

    func safeWrite(_ str: String) {
        guard !context.closed else { return }
        guard context.interfaceToken == interfaceToken else { return }
        context.insertBuffer(str)
    }
}

// MARK: - Modern Accessory Bar

private struct AccessoryBar: View {
    let isReconnecting: Bool
    let isVoiceRecording: Bool
    let isKeyboardVisible: Bool
    @Binding var controlKey: String
    @Binding var isShowingControlPopover: Bool
    @Binding var isShowingToolbarSettings: Bool
    @ObservedObject var keyStore: ToolbarKeyStore
    let onReconnect: () -> Void
    let onClose: () -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onSendKey: (String) -> Void
    let onKeyboardToggle: () -> Void
    let onVoiceInput: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(keyStore.enabledKeys().enumerated()), id: \.element.id) { index, key in
                    if key.keySequence.isEmpty {
                        // Special button (no key sequence)
                        specialButton(for: key)
                    } else {
                        // Regular key button
                        AccessoryBarButton(
                            icon: key.icon,
                            label: key.label,
                            action: { onSendKey(key.keySequence) }
                        )
                    }

                    // Add separator between different categories
                    if index < keyStore.enabledKeys().count - 1 {
                        let nextKey = keyStore.enabledKeys()[index + 1]
                        if key.category != nextKey.category {
                            Separator()
                        }
                    }
                }

                // Settings button (always shown)
                Separator()
                AccessoryBarButton(
                    icon: "ellipsis.circle",
                    label: String(localized: "Customize"),
                    action: { isShowingToolbarSettings = true }
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 56)
        .padding(.horizontal, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
    }

    @ViewBuilder
    private func specialButton(for key: ToolbarKey) -> some View {
        switch key.id {
        case "reconnect":
            if isReconnecting {
                AccessoryBarButton(
                    icon: key.icon,
                    label: key.label,
                    action: onReconnect
                )
            }
        case "close":
            AccessoryBarButton(
                icon: isReconnecting ? "xmark" : key.icon,
                label: isReconnecting ? String(localized: "Cancel") : key.label,
                action: onClose
            )
        case "paste":
            AccessoryBarButton(
                icon: key.icon,
                label: key.label,
                action: onPaste
            )
        case "copy":
            AccessoryBarButton(
                icon: key.icon,
                label: key.label,
                action: onCopy
            )
        case "keyboard_toggle":
            AccessoryBarButton(
                icon: isKeyboardVisible ? "keyboard.chevron.compact.down" : key.icon,
                label: isKeyboardVisible ? String(localized: "Hide Keyboard") : key.label,
                action: onKeyboardToggle
            )
        case "ctrl":
            AccessoryBarButton(
                icon: key.icon,
                label: key.label,
                action: { isShowingControlPopover = true }
            )
            .popover(isPresented: $isShowingControlPopover) {
                ControlKeyPopover(
                    controlKey: $controlKey,
                    isPresented: $isShowingControlPopover,
                    onSend: { onSendKey($0) }
                )
            }
        case "voice":
            AccessoryBarButton(
                icon: isVoiceRecording ? "mic.fill" : key.icon,
                label: isVoiceRecording ? String(localized: "Listening") : key.label,
                action: onVoiceInput
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - Accessory Bar Button

private struct AccessoryBarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .buttonStyle(.borderless)
    }
}

// MARK: - Separator

private struct Separator: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
    }
}

private struct LiveTranscriptBar: View {
    let text: String
    let onSendWithReturn: () -> Void
    let onSendWithoutReturn: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onSendWithReturn) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(text.isEmpty ? String(localized: "Listening...") : text)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer(minLength: 0)
            Button(action: onClear) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(action: onSendWithoutReturn) {
                Image(systemName: "arrow.turn.up.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
    }
}

// MARK: - Control Key Popover

private struct ControlKeyPopover: View {
    @Binding var controlKey: String
    @Binding var isPresented: Bool
    let onSend: (String) -> Void

    private func sendCtrl() {
        guard controlKey.count == 1 else { return }

        let char = Character(controlKey)
        guard let asciiValue = char.asciiValue,
              let asciiInt = Int(exactly: asciiValue)
        else {
            return
        }

        let ctrlInt = asciiInt - 64
        guard ctrlInt > 0, ctrlInt < 65 else { return }
        guard let us = UnicodeScalar(ctrlInt) else { return }

        let result = String(Character(us))
        onSend(result)
        controlKey = ""
        isPresented = false
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(String(localized: "Ctrl Key"))
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(String(localized: "Ctrl +"))
                    .foregroundStyle(.secondary)

                TextField(String(localized: "Key"), text: $controlKey, prompt: Text("A-Z"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .onChange(of: controlKey) { _, newValue in
                        // Keep only last uppercase character
                        guard let lastChar = newValue.uppercased().last else {
                            if !newValue.isEmpty { controlKey = "" }
                            return
                        }
                        if newValue != String(lastChar) {
                            controlKey = String(lastChar)
                        }
                    }
                    .onSubmit {
                        sendCtrl()
                    }

                Button {
                    sendCtrl()
                } label: {
                    Text(String(localized: "Send"))
                        .frame(minWidth: 60)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .presentationDetents([.height(120)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Toolbar Customization

struct ToolbarKey: Identifiable, Equatable, Codable {
    let id: String
    let icon: String
    let label: String
    let keySequence: String
    var isEnabled: Bool
    var category: KeyCategory

    enum KeyCategory: String, Codable {
        case session = "Session"
        case clipboard = "Clipboard"
        case navigation = "Navigation"
        case control = "Control"
        case custom = "Custom"
    }

    static func == (lhs: ToolbarKey, rhs: ToolbarKey) -> Bool {
        lhs.id == rhs.id && lhs.isEnabled == rhs.isEnabled
    }
}

class ToolbarKeyStore: ObservableObject {
    static let shared = ToolbarKeyStore()
    private static let voiceKeyId = "voice"
    private static let enterKeyId = "enter"
    private static let newlineKeyId = "newline"

    @AppStorage("terminalToolbarKeys") private var keysData: Data = Data()

    @Published var availableKeys: [ToolbarKey] = [
        // Session management
        ToolbarKey(id: "reconnect", icon: "arrow.clockwise", label: "Reconnect", keySequence: "", isEnabled: true, category: .session),
        ToolbarKey(id: "close", icon: "power", label: "Close", keySequence: "", isEnabled: true, category: .session),

        // Clipboard
        ToolbarKey(id: "paste", icon: "doc.on.clipboard", label: "Paste", keySequence: "", isEnabled: true, category: .clipboard),
        ToolbarKey(id: "copy", icon: "doc.on.doc", label: "Copy", keySequence: "", isEnabled: true, category: .clipboard),

        // Navigation
        ToolbarKey(id: "left", icon: "arrow.left", label: "Left", keySequence: "\u{001B}[D", isEnabled: true, category: .navigation),
        ToolbarKey(id: "right", icon: "arrow.right", label: "Right", keySequence: "\u{001B}[C", isEnabled: true, category: .navigation),
        ToolbarKey(id: "up", icon: "arrow.up", label: "Up", keySequence: "\u{001B}[A", isEnabled: true, category: .navigation),
        ToolbarKey(id: "down", icon: "arrow.down", label: "Down", keySequence: "\u{001B}[B", isEnabled: true, category: .navigation),

        // Control keys
        ToolbarKey(id: "keyboard_toggle", icon: "keyboard", label: String(localized: "Keyboard"), keySequence: "", isEnabled: true, category: .control),
        ToolbarKey(id: "ctrl", icon: "control", label: "Ctrl", keySequence: "", isEnabled: true, category: .control),
        ToolbarKey(id: "esc", icon: "escape", label: "Esc", keySequence: "\u{001B}", isEnabled: true, category: .control),
        ToolbarKey(id: ToolbarKeyStore.voiceKeyId, icon: "mic", label: String(localized: "Voice"), keySequence: "", isEnabled: ToolbarKeyStore.isSpeechRecognitionAvailable(), category: .control),

        // Custom keys
        ToolbarKey(id: ToolbarKeyStore.enterKeyId, icon: "arrow.turn.down.left", label: String(localized: "Enter"), keySequence: "\r", isEnabled: true, category: .custom),
        ToolbarKey(id: ToolbarKeyStore.newlineKeyId, icon: "return", label: String(localized: "Newline"), keySequence: "\n", isEnabled: true, category: .custom),
        ToolbarKey(id: "tab", icon: "arrow.right", label: "Tab", keySequence: "\u{0009}", isEnabled: true, category: .custom),
        ToolbarKey(id: "home", icon: "arrow.left.to.line", label: "Home", keySequence: "\u{0001}", isEnabled: false, category: .custom),
        ToolbarKey(id: "end", icon: "arrow.right.to.line", label: "End", keySequence: "\u{0005}", isEnabled: true, category: .custom),
        ToolbarKey(id: "pgup", icon: "arrow.up.to.line", label: "PgUp", keySequence: "\u{001B}[5~", isEnabled: false, category: .custom),
        ToolbarKey(id: "pgdn", icon: "arrow.down.to.line", label: "PgDn", keySequence: "\u{001B}[6~", isEnabled: false, category: .custom),
        ToolbarKey(id: "del", icon: "delete.right", label: "Del", keySequence: "\u{007F}", isEnabled: false, category: .custom),
        ToolbarKey(id: "ins", icon: "text.append", label: "Ins", keySequence: "\u{001B}[2~", isEnabled: false, category: .custom),
        ToolbarKey(id: "ctrl_c", icon: "xmark.circle", label: "Ctrl+C", keySequence: "\u{0003}", isEnabled: false, category: .custom),
        ToolbarKey(id: "ctrl_d", icon: "power", label: "Ctrl+D", keySequence: "\u{0004}", isEnabled: false, category: .custom),
        ToolbarKey(id: "ctrl_z", icon: "arrow.uturn.backward", label: "Ctrl+Z", keySequence: "\u{001A}", isEnabled: false, category: .custom),
        ToolbarKey(id: "ctrl_a", icon: "text.alignleft", label: "Ctrl+A", keySequence: "\u{0001}", isEnabled: false, category: .custom),
        ToolbarKey(id: "ctrl_e", icon: "text.alignright", label: "Ctrl+E", keySequence: "\u{0005}", isEnabled: false, category: .custom),
        ToolbarKey(id: "ctrl_l", icon: "arrow.clockwise", label: "Ctrl+L", keySequence: "\u{000C}", isEnabled: false, category: .custom),
        ToolbarKey(id: "ctrl_u", icon: "arrow.up.doc", label: "Ctrl+U", keySequence: "\u{0015}", isEnabled: false, category: .custom),
        ToolbarKey(id: "ctrl_w", icon: "textformat.alt", label: "Ctrl+W", keySequence: "\u{0017}", isEnabled: false, category: .custom),
        ToolbarKey(id: "f1", icon: "one.arrow.trianglehead.clockwise", label: "F1", keySequence: "\u{001B}OP", isEnabled: false, category: .custom),
        ToolbarKey(id: "f2", icon: "two.arrow.trianglehead.clockwise", label: "F2", keySequence: "\u{001B}OQ", isEnabled: false, category: .custom),
        ToolbarKey(id: "f3", icon: "three.arrow.trianglehead.clockwise", label: "F3", keySequence: "\u{001B}OR", isEnabled: false, category: .custom),
        ToolbarKey(id: "f4", icon: "four.arrow.trianglehead.clockwise", label: "F4", keySequence: "\u{001B}OS", isEnabled: false, category: .custom),
        ToolbarKey(id: "f5", icon: "five.arrow.trianglehead.clockwise", label: "F5", keySequence: "\u{001B}[15~", isEnabled: false, category: .custom),
    ]

    private init() {
        loadKeys()
        // Ensure required keys exist in the list for users upgrading from older versions.
        ensureRequiredKeysExist()
        // Update voice key availability after loading to respect current settings
        updateVoiceKeyAvailability()
    }

    private func ensureRequiredKeysExist() {
        if !availableKeys.contains(where: { $0.id == "keyboard_toggle" }) {
            let keyboardKey = ToolbarKey(
                id: "keyboard_toggle",
                icon: "keyboard",
                label: String(localized: "Keyboard"),
                keySequence: "",
                isEnabled: true,
                category: .control
            )
            if let ctrlIndex = availableKeys.firstIndex(where: { $0.id == "ctrl" }) {
                availableKeys.insert(keyboardKey, at: ctrlIndex)
            } else {
                availableKeys.insert(keyboardKey, at: min(availableKeys.count, 4))
            }
        }

        if !availableKeys.contains(where: { $0.id == Self.voiceKeyId }) {
            if let escIndex = availableKeys.firstIndex(where: { $0.id == "esc" }) {
                let voiceKey = ToolbarKey(
                    id: Self.voiceKeyId,
                    icon: "mic",
                    label: String(localized: "Voice"),
                    keySequence: "",
                    isEnabled: true,
                    category: .control
                )
                availableKeys.insert(voiceKey, at: escIndex + 1)
            } else {
                // Fallback: add to the end of control keys or just append
                let voiceKey = ToolbarKey(
                    id: Self.voiceKeyId,
                    icon: "mic",
                    label: String(localized: "Voice"),
                    keySequence: "",
                    isEnabled: true,
                    category: .control
                )
                availableKeys.append(voiceKey)
            }
        }

        if !availableKeys.contains(where: { $0.id == Self.enterKeyId }) {
            let enterKey = ToolbarKey(
                id: Self.enterKeyId,
                icon: "arrow.turn.down.left",
                label: String(localized: "Enter"),
                keySequence: "\r",
                isEnabled: true,
                category: .custom
            )
            if let tabIndex = availableKeys.firstIndex(where: { $0.id == "tab" }) {
                availableKeys.insert(enterKey, at: tabIndex)
            } else {
                availableKeys.append(enterKey)
            }
        }

        if !availableKeys.contains(where: { $0.id == Self.newlineKeyId }) {
            let newlineKey = ToolbarKey(
                id: Self.newlineKeyId,
                icon: "return",
                label: String(localized: "Newline"),
                keySequence: "\n",
                isEnabled: true,
                category: .custom
            )
            if let enterIndex = availableKeys.firstIndex(where: { $0.id == Self.enterKeyId }) {
                availableKeys.insert(newlineKey, at: enterIndex + 1)
            } else if let tabIndex = availableKeys.firstIndex(where: { $0.id == "tab" }) {
                availableKeys.insert(newlineKey, at: tabIndex)
            } else {
                availableKeys.append(newlineKey)
            }
        }

        saveKeys()
    }

    private static func isSpeechRecognitionAvailable() -> Bool {
        // First check if user has enabled voice input in settings
        guard RayonStore.shared.speechInputEngine != "disabled" else {
            return false
        }
        // Check if speech recognition is supported for the configured locale
        let localeIdentifier = RayonStore.shared.speechInputLocaleIdentifier
        let targetLocale = localeIdentifier == "system" ? Locale.current : Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: targetLocale) else {
            // Fallback to current locale if configured locale is not supported
            guard let fallbackRecognizer = SFSpeechRecognizer(locale: .current) else {
                return false
            }
            return fallbackRecognizer.isAvailable
        }
        return recognizer.isAvailable
    }

    /// Update voice key enabled state when settings change
    func updateVoiceKeyAvailability() {
        let isAvailable = Self.isSpeechRecognitionAvailable()
        if let index = availableKeys.firstIndex(where: { $0.id == Self.voiceKeyId }) {
            // Only update and save if the state actually changed
            if availableKeys[index].isEnabled != isAvailable {
                availableKeys[index].isEnabled = isAvailable
                saveKeys()
            }
        }
    }

    private func loadKeys() {
        guard !keysData.isEmpty else { return }
        do {
            let decoded = try JSONDecoder().decode([ToolbarKey].self, from: keysData)
            // Restore saved keys including order
            availableKeys = decoded
        } catch {
            print("Failed to load toolbar keys: \(error)")
        }
    }

    func saveKeys() {
        do {
            let encoded = try JSONEncoder().encode(availableKeys)
            keysData = encoded
        } catch {
            print("Failed to save toolbar keys: \(error)")
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        availableKeys.move(fromOffsets: source, toOffset: destination)
        saveKeys()
    }

    func enabledKeys() -> [ToolbarKey] {
        return availableKeys.filter { $0.isEnabled }
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
            UIBridge.presentError(with: String(localized: "Voice disabled"))
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
                UIBridge.presentError(with: String(localized: "Mic/Speech denied"))
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
        guard isRecording else {
            liveTranscript = ""
            onPartialTranscript?("")
            return
        }
        committedPrefix = fullTranscript
        liveTranscript = ""
        onPartialTranscript?("")
    }

    private func stop(commit: Bool) {
        guard isRecording || !liveTranscript.isEmpty else { return }
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
        let recordPermission = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        guard recordPermission else { throw SpeechError.permissionDenied }

        let speechPermission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechPermission == .authorized else { throw SpeechError.permissionDenied }
    }

    private func configureAndStart() throws {
        let localeIdentifier = RayonStore.shared.speechInputLocaleIdentifier
        let targetLocale: Locale
        if localeIdentifier == "system" {
            targetLocale = .current
        } else {
            targetLocale = Locale(identifier: localeIdentifier)
        }
        speechRecognizer = SFSpeechRecognizer(locale: targetLocale)
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: .current)
        }
        guard let speechRecognizer else { throw SpeechError.unavailable }
        guard speechRecognizer.isAvailable else { throw SpeechError.unavailable }

        fullTranscript = ""
        committedPrefix = ""
        liveTranscript = ""
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        UIBridge.presentSuccess(with: String(localized: "Voice started"))

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
        case permissionDenied
        case unavailable
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

struct ToolbarSettingsView: View {
    @ObservedObject var keyStore: ToolbarKeyStore
    @Environment(\.dismiss) var dismiss
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(String(localized: "Drag to reorder, toggle to show/hide"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(String(localized: "Toolbar Settings"))
                }

                Section {
                    ForEach(keyStore.availableKeys) { key in
                        HStack {
                            Image(systemName: key.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(key.label)
                                    .font(.body)

                                Text(categoryLabel(key.category))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { key.isEnabled },
                                set: { newValue in
                                    if let index = keyStore.availableKeys.firstIndex(where: { $0.id == key.id }) {
                                        keyStore.availableKeys[index].isEnabled = newValue
                                        keyStore.saveKeys()
                                    }
                                }
                            ))
                        }
                    }
                    .onMove(perform: editMode == .active ? keyStore.move : nil)
                } header: {
                    Text(String(localized: "All Buttons"))
                } footer: {
                    Text(String(localized: "Drag to reorder buttons in edit mode"))
                        .font(.caption)
                }
            }
            .navigationTitle(String(localized: "Customize Toolbar"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(editMode == .active ? String(localized: "Done") : String(localized: "Edit")) {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func categoryLabel(_ category: ToolbarKey.KeyCategory) -> String {
        switch category {
        case .session: return String(localized: "Session")
        case .clipboard: return String(localized: "Clipboard")
        case .navigation: return String(localized: "Navigation")
        case .control: return String(localized: "Control")
        case .custom: return String(localized: "Custom")
        }
    }
}

// MARK: - Web Browser Port Input Sheet

private struct WebBrowserPortInputSheet: View {
    @Binding var port: String
    let machine: RDMachine
    @Binding var isPresented: Bool

    @StateObject private var browserManager = WebBrowserManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Port Number"), text: $port)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                } header: {
                    Text(String(localized: "Remote Port"))
                } footer: {
                    Text(String(localized: "Enter the port number on the remote server to forward"))
                }

                Section {
                    HStack {
                        Text(String(localized: "Server"))
                        Spacer()
                        Text(machine.name)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(String(localized: "Address"))
                        Spacer()
                        Text(machine.remoteAddress)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "Connection"))
                }
            }
            .navigationTitle(String(localized: "Open Web Browser"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Open")) {
                        openBrowser()
                    }
                    .disabled(port.isEmpty)
                }
            }
        }
    }

    private func openBrowser() {
        guard let portNumber = Int(port), portNumber > 0, portNumber <= 65535 else {
            UIBridge.presentError(with: String(localized: "Invalid port number"))
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
            // Navigate to the browser view
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                let browserView = WebBrowserView(context: context)
                let hostingController = UIHostingController(rootView: browserView)
                hostingController.modalPresentationStyle = .fullScreen
                UIWindow.shutUpKeyWindow?
                    .topMostViewController?
                    .present(hostingController, animated: true)
            }
        }
    }
}
