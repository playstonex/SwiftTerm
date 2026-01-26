//
//  TerminalView.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/10.
//

import RayonModule
import SwiftUI
import XTerminalUI

struct TerminalView: View {
    @StateObject var context: TerminalManager.Context

    @StateObject var store = RayonStore.shared
    @State var interfaceToken = UUID()
    @State var backgroundColor: Color = .black

    var body: some View {
        Group {
            if context.interfaceToken == interfaceToken {
                GeometryReader { geometry in
                    ZStack {
                        backgroundColor
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .offset(x: 0, y: 0)

                        context.termInterface
                            .padding(4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: store.terminalFontSize) { newValue in
                        context.termInterface.setTerminalFontSize(with: newValue)
                    }
                    .onChange(of: store.terminalFontName) { newValue in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.applyFont()
                        }
                    }
                    .onChange(of: store.terminalThemeName) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.applyTheme()
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.applyTheme()
                            self.applyFont()
                        }
                    }
            } else {
                Text("Terminal Transfer To Another Window")
            }
        }
        .onAppear {
            debugPrint("set interface token \(interfaceToken)")
            context.interfaceToken = interfaceToken
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
    }

    func safeWriteBase64(_ base64: String) {
        guard let data = Data(base64Encoded: base64),
              let str = String(data: data, encoding: .utf8)
        else {
            debugPrint("failed to decode \(base64)")
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
        debugPrint("Applying terminal theme: \(theme.name)")

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
        debugPrint("Applying terminal font: \(fontName)")

        context.termInterface.setTerminalFontName(with: fontName)
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
