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

    @State var openControlKeyPopover: Bool = false
    @State var controlKey: String = ""

    @State var accessoryBarOffset: CGSize = .zero
    @State var isDraggingAccessoryBar: Bool = false
    @State var lastDragOffset: CGSize = .zero

    @StateObject var store = RayonStore.shared
    @ObservedObject var assistantManager = AssistantManager.shared

    @Environment(\.presentationMode) var presentationMode

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
                ZStack(alignment: .bottom) {
                    // Background fills entire view including safe area (chin)
                    ColorFromHex(store.terminalTheme.background)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Terminal fills the entire view
                    context.termInterface
                        .onChange(of: r.size) { _, _ in
                            guard context.interfaceToken == interfaceToken else {
                                return
                            }
                            updateTerminalSize()
                        }
                        .onAppear {
                            context.termInterface.setTerminalFontSize(with: store.terminalFontSize)
                            context.termInterface.setTerminalFontName(with: store.terminalFontName)
                            // Delay theme application to ensure WebView is ready
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
                            // Schedule background update on next runloop cycle
                            DispatchQueue.main.async {
                                applyTheme()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Modern accessory bar at the bottom
                    if !context.destroyedSession {
                        VStack {
                            Spacer()
                            AccessoryBar(
                                context: context,
                                isReconnecting: context.closed,
                controlKey: $controlKey,
                isShowingControlPopover: $openControlKeyPopover,
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
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .offset(accessoryBarOffset)
                                .animation(isDraggingAccessoryBar ? .interactiveSpring() : .spring(response: 0.3, dampingFraction: 0.7), value: accessoryBarOffset)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            isDraggingAccessoryBar = true
                                            // Calculate cumulative offset from last position
                                            let newOffset = CGSize(
                                                width: lastDragOffset.width + value.translation.width,
                                                height: lastDragOffset.height + value.translation.height
                                            )
                                            accessoryBarOffset = newOffset
                                        }
                                        .onEnded { value in
                                            isDraggingAccessoryBar = false

                                            // Get screen size and safe area
                                            let screenSize = UIScreen.main.bounds.size
                                            let window = UIApplication.shared.connectedScenes
                                                .compactMap { $0 as? UIWindowScene }
                                                .first?.windows.first
                                            let safeAreaInsets = window?.safeAreaInsets ?? .zero

                                            // Safe area already includes navbar and status bar
                                            let topSafeArea = safeAreaInsets.top
                                            let bottomSafeArea = safeAreaInsets.bottom
                                            let sidePadding: CGFloat = 8 // Match the .padding(.horizontal, 8)

                                            // Approximate accessory bar size
                                            let barWidth: CGFloat = screenSize.width - (sidePadding * 2)
                                            let barHeight: CGFloat = 50 // Approximate with padding

                                            let snapThreshold: CGFloat = 80
                                            var targetOffset = CGSize.zero

                                            // Get current position
                                            let currentX = lastDragOffset.width + value.translation.width
                                            let currentY = lastDragOffset.height + value.translation.height

                                            // Determine horizontal snap
                                            if abs(currentX) < snapThreshold {
                                                // Keep near center
                                                targetOffset.width = 0
                                            } else if currentX < 0 {
                                                // Snap to left edge (account for padding)
                                                let maxLeftOffset = -(screenSize.width / 2) + sidePadding + (barWidth / 2)
                                                targetOffset.width = maxLeftOffset
                                            } else {
                                                // Snap to right edge (account for padding)
                                                let maxRightOffset = (screenSize.width / 2) - sidePadding - (barWidth / 2)
                                                targetOffset.width = maxRightOffset
                                            }

                                            // Determine vertical snap
                                            let availableHeight = screenSize.height - topSafeArea - bottomSafeArea
                                            let maxY = availableHeight / 2 - barHeight - 8 // 8 is bottom padding

                                            if abs(currentY) < snapThreshold {
                                                // Keep near bottom (default position)
                                                targetOffset.height = 0
                                            } else if currentY < 0 {
                                                // Snap to top (below navbar)
                                                let minY = -(availableHeight / 2) + (barHeight / 2) + 8
                                                targetOffset.height = minY
                                            } else {
                                                // Snap to bottom
                                                targetOffset.height = maxY
                                            }

                                            // Update last offset and animate to snap position
                                            lastDragOffset = targetOffset
                                            accessoryBarOffset = targetOffset
                                        }
                                )
                                .padding(.bottom, 8)
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
    let context: TerminalContext
    let isReconnecting: Bool
    @Binding var controlKey: String
    @Binding var isShowingControlPopover: Bool
    let onReconnect: () -> Void
    let onClose: () -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onSendKey: (String) -> Void

    @State private var isShowingEscapeHint = false

    var body: some View {
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

            // Control keys group
            Group {
                AccessoryBarButton(
                    icon: "arrow.right.to.line",
                    label: "End",
                    action: { onSendKey("\u{0005}") } // C-E
                )

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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
