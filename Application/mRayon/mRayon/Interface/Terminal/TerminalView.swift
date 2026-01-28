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
                        .onChange(of: r.size) { _ in
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Floating accessory bar at the bottom
                    if !context.destroyedSession {
                        VStack {
                            Spacer()
                            buttonGroup
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(10)
                                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: -4)
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
                    .foregroundColor(ColorFromHex(store.terminalTheme.foreground))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    assistantManager.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
            }
        }
        .onChange(of: store.terminalThemeName) { _ in
            // Force toolbar update when theme changes
        }
    }
    var buttonGroup: some View {
        HStack(spacing: 1) {
            if context.closed {
                makeKeyButton("arrow.counterclockwise") {
                    DispatchQueue.global().async {
                        context.putInformation("[i] Reconnect will use the information you provide previously,")
                        context.putInformation("    if the machine was edited, create a new terminal.")
                        context.processBootstrap()
                    }
                }
            }
            makeKeyButton("trash") {
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
            }
            makeKeyButton("doc.on.clipboard") {
                guard let str = UIPasteboard.general.string else {
                    UIBridge.presentError(with: "Empty Pasteboard")
                    return
                }
                UIBridge.requiresConfirmation(
                    message: "Are you sure you want to paste following string?\n\n\(str)"
                ) { yes in
                    if yes { self.safeWrite(str) }
                }
            }
            makeKeyButton("doc.on.doc") {
                debugPrint("[Copy Button] Button clicked!")

                // Get the complete history with ANSI codes stripped for cleaner copying
                let cleanHistory = context.getOutputHistoryStrippedANSI()

                if !cleanHistory.isEmpty {
                    debugPrint("[Copy] Got \(cleanHistory.count) chars from stripped history")
                    UIPasteboard.general.string = cleanHistory
                    UIBridge.presentSuccess(with: "已复制")
                } else {
                    debugPrint("[Copy] History is empty")
                    UIBridge.presentError(with: "终端内容为空")
                }
            }

            Divider().frame(width: 1, height: 20).background(Color.gray.opacity(0.3))

            makeKeyButton("arrow.right.to.line.compact") {
                safeWriteBase64("CQ==")
            }
            makeKeyButton("control") {
                openControlKeyPopover = true
            }
            .popover(isPresented: $openControlKeyPopover) {
                HStack(spacing: 2) {
                    Text("Ctrl + ")
                    TextField("Key To Send", text: $controlKey)
                        .disableAutocorrection(true)
                        .onChange(of: controlKey) { newValue in
                            guard let f = newValue.uppercased().last else {
                                if !controlKey.isEmpty { controlKey = "" }
                                return
                            }
                            if controlKey != String(f) {
                                controlKey = String(f)
                            }
                        }
                        .onSubmit {
                            sendCtrl()
                        }
                    Button {
                        sendCtrl()
                    } label: {
                        Image(systemName: "return")
                    }
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .padding()
                .frame(width: 200, height: 40)
            }
            makeKeyButton("escape") {
                safeWriteBase64("Gw==")
            }

            Divider().frame(width: 1, height: 20).background(Color.gray.opacity(0.3))

            makeKeyButton("arrow.left.circle.fill") {
                safeWriteBase64("G1tE")
            }
            makeKeyButton("arrow.right.circle.fill") {
                safeWriteBase64("G1tD")
            }
            makeKeyButton("arrow.up.circle.fill") {
                safeWriteBase64("G1tB")
            }
            makeKeyButton("arrow.down.circle.fill") {
                safeWriteBase64("G1tC")
            }
        }
    }

    func sendCtrl() {
        let key = controlKey
        controlKey = ""
        openControlKeyPopover = false
        /*
         Note: The Ctrl-Key representation is simply associating the non-printable characters from ASCII code 1 with the printable (letter) characters from ASCII code 65 ("A"). ASCII code 1 would be ^A (Ctrl-A), while ASCII code 7 (BEL) would be ^G (Ctrl-G). This is a common representation (and input method) and historically comes from one of the VT series of terminals.

         https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
         */
        guard key.count == 1 else { return }
        let char = Character(key)
        guard let asciiValue = char.asciiValue,
              let asciiInt = Int(exactly: asciiValue) // 65 = "A" 1 = "CTRL+A"
        else {
            return
        }
        let ctrlInt = asciiInt - 64
        guard ctrlInt > 0, ctrlInt < 65 else {
            return
        }
        guard let us = UnicodeScalar(ctrlInt) else {
            return
        }
        let nc = Character(us)
        let st = String(nc)
        safeWrite(st)
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

    func makeKeyButton(_ imageName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: imageName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 28)
                .foregroundColor(.primary)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color(uiColor: .systemGray5))
        .cornerRadius(4)
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
}
