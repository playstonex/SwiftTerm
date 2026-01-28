//
//  TerminalView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import RayonModule
import SwiftUI
import UIKit
import XTerminalUI

struct TerminalView: View {
    @StateObject var context: TerminalContext

    @State var interfaceToken = UUID()

    @State var terminalSize: CGSize = TerminalContext.defaultTerminalSize

    @StateObject var store = RayonStore.shared
    @ObservedObject var assistantManager = AssistantManager.shared

    @Environment(\.presentationMode) var presentationMode

    @State private var isShowingToolbarSettings = false

    // Helper function to create Color from hex string
    private func ColorFromHex(_ hex: String) -> Color {
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

        return Color(red: r, green: g, blue: b, opacity: a)
    }

    var body: some View {
        Group {
            if context.interfaceToken == interfaceToken {
                GeometryReader { r in
                    ZStack {
                        // Background
                        ColorFromHex(store.terminalTheme.background)
                            .ignoresSafeArea()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Terminal view
                        context.termInterface
                            .onChange(of: r.size) { _, _ in
                                guard context.interfaceToken == interfaceToken else { return }
                                updateTerminalSize()
                            }
                            .onAppear {
                                context.termInterface.setTerminalFontSize(with: store.terminalFontSize)
                                context.termInterface.setTerminalFontName(with: store.terminalFontName)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    self.applyTheme()
                                    self.applyFont()
                                }
                            }
                            .onChange(of: store.terminalFontSize) { _, newValue in
                                context.termInterface.setTerminalFontSize(with: newValue)
                            }
                            .onChange(of: store.terminalFontName) { _, _ in
                                applyFont()
                            }
                            .onChange(of: store.terminalThemeName) { _, _ in
                                DispatchQueue.main.async {
                                    applyTheme()
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !context.destroyedSession {
                            AccessoryBar(
                                isReconnecting: context.closed,
                                controlKey: .constant(""),
                                isShowingControlPopover: .constant(false),
                                isShowingToolbarSettings: $isShowingToolbarSettings,
                                keyStore: ToolbarKeyStore.shared,
                                onReconnect: {
                                    DispatchQueue.global().async {
                                        context.putInformation("[i] Reconnect will use the information you provide previously,")
                                        context.putInformation("    if the machine was edited, create a new terminal.")
                                        context.processBootstrap()
                                    }
                                },
                                onClose: {
                                    if context.closed {
                                        presentationMode.wrappedValue.dismiss()
                                        TerminalManager.shared.end(for: context.id)
                                    } else {
                                        UIBridge.requiresConfirmation(
                                            message: "Are you sure you want to close this session?"
                                        ) { yes in
                                            if yes { context.processShutdown() }
                                        }
                                    }
                                },
                                onPaste: {
                                    guard let str = UIPasteboard.general.string else {
                                        UIBridge.presentError(with: "Empty Pasteboard")
                                        return
                                    }
                                    UIBridge.requiresConfirmation(
                                        message: "Are you sure you want to paste following string?\n\n\(str)"
                                    ) { yes in
                                        if yes { self.safeWrite(str) }
                                    }
                                },
                                onCopy: {
                                    let cleanHistory = context.getOutputHistoryStrippedANSI()
                                    if !cleanHistory.isEmpty {
                                        UIPasteboard.general.string = cleanHistory
                                        UIBridge.presentSuccess(with: "已复制")
                                    } else {
                                        UIBridge.presentError(with: "终端内容为空")
                                    }
                                },
                                onSendKey: { key in
                                    self.safeWrite(key)
                                }
                            )
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
            DispatchQueue.main.async {
                context.interfaceToken = interfaceToken
            }
        }
        .navigationTitle(context.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(context.navigationTitle)
                    .font(.headline)
                    .foregroundStyle(ColorFromHex(store.terminalTheme.foreground))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    assistantManager.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
            }
        }
        .onChange(of: store.terminalThemeName) { _, _ in
            // Force toolbar update when theme changes
        }
        .sheet(isPresented: $isShowingToolbarSettings) {
            ToolbarSettingsView(keyStore: ToolbarKeyStore.shared)
        }
    }

    func updateTerminalSize() {
        let core = context.termInterface
        let origSize = terminalSize
        DispatchQueue.global().async {
            let newSize = core.requestTerminalSize()
            guard newSize.width > 5, newSize.height > 5 else {
                return
            }
            if newSize != origSize {
                mainActor {
                    guard context.interfaceToken == interfaceToken else {
                        return
                    }
                    terminalSize = newSize
                    context.shell.explicitRequestStatusPickup()
                }
            }
        }
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

    func safeWrite(_ str: String) {
        guard !context.closed else { return }
        guard context.interfaceToken == interfaceToken else { return }
        context.insertBuffer(str)
    }
}

// MARK: - Modern Accessory Bar

private struct AccessoryBar: View {
    let isReconnecting: Bool
    @Binding var controlKey: String
    @Binding var isShowingControlPopover: Bool
    @Binding var isShowingToolbarSettings: Bool
    @ObservedObject var keyStore: ToolbarKeyStore
    let onReconnect: () -> Void
    let onClose: () -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onSendKey: (String) -> Void

    @State private var isShowingEscapeHint = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // Session management group
                Group {
                    if isReconnecting {
                        AccessoryBarButton(
                            icon: "arrow.clockwise",
                            label: "Reconnect",
                            action: onReconnect
                        )
                    }

                    AccessoryBarButton(
                        icon: isReconnecting ? "xmark" : "power",
                        label: isReconnecting ? "Cancel" : "Close",
                        action: onClose
                    )
                }

                Separator()

                // Clipboard group
                Group {
                    AccessoryBarButton(
                        icon: "doc.on.clipboard",
                        label: "Paste",
                        action: onPaste
                    )

                    AccessoryBarButton(
                        icon: "doc.on.doc",
                        label: "Copy",
                        action: onCopy
                    )
                }

                Separator()

                // Arrow keys group
                Group {
                    AccessoryBarButton(
                        icon: "arrow.left",
                        label: "Left",
                        action: { onSendKey("\u{001B}[D") }
                    )

                    AccessoryBarButton(
                        icon: "arrow.right",
                        label: "Right",
                        action: { onSendKey("\u{001B}[C") }
                    )

                    AccessoryBarButton(
                        icon: "arrow.up",
                        label: "Up",
                        action: { onSendKey("\u{001B}[A") }
                    )

                    AccessoryBarButton(
                        icon: "arrow.down",
                        label: "Down",
                        action: { onSendKey("\u{001B}[B") }
                    )
                }

                Separator()

                // Control keys group
                Group {
                    AccessoryBarButton(
                        icon: "keyboard",
                        label: "Ctrl",
                        action: { isShowingControlPopover = true }
                    )
                    .popover(isPresented: $isShowingControlPopover) {
                        ControlKeyPopover(
                            controlKey: $controlKey,
                            isPresented: $isShowingControlPopover,
                            onSend: { onSendKey($0) }
                        )
                    }

                    AccessoryBarButton(
                        icon: "escape",
                        label: "Esc",
                        action: { onSendKey("\u{001B}") }
                    )
                }

                Separator()

                // Custom keys from user selection
                ForEach(keyStore.enabledKeys()) { key in
                    AccessoryBarButton(
                        icon: key.icon,
                        label: key.label,
                        action: { onSendKey(key.keySequence) }
                    )
                }

                Separator()

                // Settings button
                AccessoryBarButton(
                    icon: "ellipsis.circle",
                    label: "Customize",
                    action: { isShowingToolbarSettings = true }
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 56)  // Fixed height: 44pt button + 12pt padding
        .padding(.horizontal, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
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
            Text("Ctrl Key")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Ctrl +")
                    .foregroundStyle(.secondary)

                TextField("Key", text: $controlKey, prompt: Text("A-Z"))
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
                    Text("Send")
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

    static func == (lhs: ToolbarKey, rhs: ToolbarKey) -> Bool {
        lhs.id == rhs.id && lhs.isEnabled == rhs.isEnabled
    }
}

class ToolbarKeyStore: ObservableObject {
    static let shared = ToolbarKeyStore()

    @AppStorage("terminalToolbarKeys") private var keysData: Data = Data()

    @Published var availableKeys: [ToolbarKey] = [
        ToolbarKey(id: "tab", icon: "arrow.right", label: "Tab", keySequence: "\u{0009}", isEnabled: true),
        ToolbarKey(id: "home", icon: "arrow.left.to.line", label: "Home", keySequence: "\u{0001}", isEnabled: false),
        ToolbarKey(id: "end", icon: "arrow.right.to.line", label: "End", keySequence: "\u{0005}", isEnabled: true),
        ToolbarKey(id: "pgup", icon: "arrow.up.to.line", label: "PgUp", keySequence: "\u{001B}[5~", isEnabled: false),
        ToolbarKey(id: "pgdn", icon: "arrow.down.to.line", label: "PgDn", keySequence: "\u{001B}[6~", isEnabled: false),
        ToolbarKey(id: "del", icon: "delete.right", label: "Del", keySequence: "\u{007F}", isEnabled: false),
        ToolbarKey(id: "ins", icon: "text.append", label: "Ins", keySequence: "\u{001B}[2~", isEnabled: false),
        ToolbarKey(id: "ctrl_c", icon: "xmark.circle", label: "Ctrl+C", keySequence: "\u{0003}", isEnabled: false),
        ToolbarKey(id: "ctrl_d", icon: "power", label: "Ctrl+D", keySequence: "\u{0004}", isEnabled: false),
        ToolbarKey(id: "ctrl_z", icon: "arrow.uturn.backward", label: "Ctrl+Z", keySequence: "\u{001A}", isEnabled: false),
        ToolbarKey(id: "ctrl_a", icon: "text.alignleft", label: "Ctrl+A", keySequence: "\u{0001}", isEnabled: false),
        ToolbarKey(id: "ctrl_e", icon: "text.alignright", label: "Ctrl+E", keySequence: "\u{0005}", isEnabled: false),
        ToolbarKey(id: "ctrl_l", icon: "arrow.clockwise", label: "Ctrl+L", keySequence: "\u{000C}", isEnabled: false),
        ToolbarKey(id: "ctrl_u", icon: "arrow.up.doc", label: "Ctrl+U", keySequence: "\u{0015}", isEnabled: false),
        ToolbarKey(id: "ctrl_w", icon: "textformat.alt", label: "Ctrl+W", keySequence: "\u{0017}", isEnabled: false),
        ToolbarKey(id: "f1", icon: "one.arrow.trianglehead.clockwise", label: "F1", keySequence: "\u{001B}OP", isEnabled: false),
        ToolbarKey(id: "f2", icon: "two.arrow.trianglehead.clockwise", label: "F2", keySequence: "\u{001B}OQ", isEnabled: false),
        ToolbarKey(id: "f3", icon: "three.arrow.trianglehead.clockwise", label: "F3", keySequence: "\u{001B}OR", isEnabled: false),
        ToolbarKey(id: "f4", icon: "four.arrow.trianglehead.clockwise", label: "F4", keySequence: "\u{001B}OS", isEnabled: false),
        ToolbarKey(id: "f5", icon: "five.arrow.trianglehead.clockwise", label: "F5", keySequence: "\u{001B}[15~", isEnabled: false),
    ]

    private init() {
        loadKeys()
    }

    private func loadKeys() {
        guard !keysData.isEmpty else { return }
        do {
            let decoded = try JSONDecoder().decode([ToolbarKey].self, from: keysData)
            // Merge with default keys to handle new keys added in future versions
            for index in availableKeys.indices {
                if let savedKey = decoded.first(where: { $0.id == availableKeys[index].id }) {
                    availableKeys[index].isEnabled = savedKey.isEnabled
                }
            }
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

    func enabledKeys() -> [ToolbarKey] {
        return availableKeys.filter { $0.isEnabled }
    }
}

struct ToolbarSettingsView: View {
    @ObservedObject var keyStore: ToolbarKeyStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("选择要显示在工具栏中的快捷键")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("工具栏设置")
                }

                Section {
                    ForEach(keyStore.availableKeys) { key in
                        HStack {
                            Image(systemName: key.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                                .frame(width: 32)

                            Text(key.label)
                                .font(.body)

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
                } header: {
                    Text("可用快捷键")
                } footer: {
                    Text("启用后的快捷键将显示在终端工具栏中")
                        .font(.caption)
                }
            }
            .navigationTitle("自定义工具栏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

