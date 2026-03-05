//
//  SwiftTerminalView+SwiftUI.swift
//  SwiftTerminal
//
//  Cross-platform SwiftUI wrapper for SwiftTerminal
//

import SwiftUI
import SwiftTerm

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// SwiftUI wrapper for the native SwiftTerminal view
/// This provides the same interface as XTerminal's STerminalView
public struct STerminalView: NativeTerminalProtocol {

    #if canImport(AppKit)
    private let terminalView: SwiftTerminalView
    #else
    private let terminalView: SwiftTerminalView
    #endif

    private let adapter: SwiftTerminalAdapter

    // MARK: - Initialization

    public init() {
        let adapter = SwiftTerminalAdapter()
        self.adapter = adapter
        self.terminalView = SwiftTerminalView(adapter: adapter)
    }

    // MARK: - NativeTerminalProtocol Implementation

    @discardableResult
    public func setupBufferChain(callback: ((String) -> Void)?) -> Self {
        adapter.setupBufferChain(callback: callback)
        return self
    }

    @discardableResult
    public func setupTitleChain(callback: ((String) -> Void)?) -> Self {
        adapter.setupTitleChain(callback: callback)
        return self
    }

    @discardableResult
    public func setupBellChain(callback: (() -> Void)?) -> Self {
        adapter.setupBellChain(callback: callback)
        return self
    }

    @discardableResult
    public func setupSizeChain(callback: ((CGSize) -> Void)?) -> Self {
        adapter.setupSizeChain(callback: callback)
        return self
    }

    @discardableResult
    public func setupCopyChain(callback: ((String) -> Void)?) -> Self {
        adapter.setupCopyChain(callback: callback)
        return self
    }

    @discardableResult
    public func setupNavigationChain(callback: (() -> Void)?) -> Self {
        adapter.setupNavigationChain(callback: callback)
        return self
    }

    public func write(_ str: String) {
        terminalView.feed(text: str)
    }

    public func requestTerminalSize() -> CGSize {
        let terminal = terminalView.getTerminal()
        return CGSize(width: terminal.cols, height: terminal.rows)
    }

    public func setTerminalFontSize(with size: Int) {
        adapter.setTerminalFontSize(with: size)
        terminalView.updateFont()
    }

    public func setTerminalFontName(with name: String) {
        adapter.setTerminalFontName(with: name)
        terminalView.updateFont()
    }

    public func setTerminalTheme(
        foreground: String,
        background: String,
        cursor: String,
        black: String,
        red: String,
        green: String,
        yellow: String,
        blue: String,
        magenta: String,
        cyan: String,
        white: String,
        brightBlack: String,
        brightRed: String,
        brightGreen: String,
        brightYellow: String,
        brightBlue: String,
        brightMagenta: String,
        brightCyan: String,
        brightWhite: String
    ) {
        adapter.setTerminalTheme(
            foreground: foreground,
            background: background,
            cursor: cursor,
            black: black,
            red: red,
            green: green,
            yellow: yellow,
            blue: blue,
            magenta: magenta,
            cyan: cyan,
            white: white,
            brightBlack: brightBlack,
            brightRed: brightRed,
            brightGreen: brightGreen,
            brightYellow: brightYellow,
            brightBlue: brightBlue,
            brightMagenta: brightMagenta,
            brightCyan: brightCyan,
            brightWhite: brightWhite
        )
        terminalView.updateTheme()
    }

    public func getSelection(completion: @escaping (String?) -> Void) {
        let text = terminalView.getSelectedText()
        completion(text.isEmpty ? nil : text)
    }
}

// MARK: - SwiftUI View Representable

#if canImport(AppKit)
extension STerminalView: NSViewRepresentable {
    public func makeNSView(context: Context) -> SwiftTerminalView {
        return terminalView
    }

    public func updateNSView(_ nsView: SwiftTerminalView, context: Context) {
        // Updates are handled through the adapter
    }
}
#endif

#if canImport(UIKit)
extension STerminalView: UIViewRepresentable {
    public func makeUIView(context: Context) -> SwiftTerminalView {
        return terminalView
    }

    public func updateUIView(_ uiView: SwiftTerminalView, context: Context) {
        // Updates are handled through the adapter
    }
}
#endif
