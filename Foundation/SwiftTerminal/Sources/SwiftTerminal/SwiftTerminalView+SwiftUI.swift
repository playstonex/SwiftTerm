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
        // Must be called on main thread for UI updates
        DispatchQueue.main.async {
            self.terminalView.feed(text: str)
        }
    }

    public func requestTerminalSize() -> CGSize {
        terminalView.requestTerminalSize()
    }

    public func setTerminalFontSize(with size: Int) {
        adapter.setTerminalFontSize(with: size)
        DispatchQueue.main.async {
            self.terminalView.updateFont()
        }
    }

    public func setTerminalFontName(with name: String) {
        adapter.setTerminalFontName(with: name)
        DispatchQueue.main.async {
            self.terminalView.updateFont()
        }
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
        DispatchQueue.main.async {
            self.terminalView.updateTheme()
        }
    }

    public func getSelection(completion: @escaping (String?) -> Void) {
        let text = terminalView.getSelectedText()
        completion(text.isEmpty ? nil : text)
    }

    public func refreshDisplay() {
        DispatchQueue.main.async {
            self.terminalView.refreshDisplay()
        }
    }

    public func activateKeyboard() {
        DispatchQueue.main.async {
            _ = self.terminalView.makeTerminalFirstResponder()
        }
    }

    public func dismissKeyboard() {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            _ = self.terminalView.resignTerminalFirstResponder()
        }
        #endif
    }
}

// MARK: - SwiftUI View Representable

#if canImport(AppKit)
extension STerminalView: NSViewRepresentable {
    public func makeNSView(context: Context) -> SwiftTerminalView {
        // Set up the view to become first responder when the window becomes key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.terminalView.makeTerminalFirstResponder()
        }
        return terminalView
    }

    public func updateNSView(_ nsView: SwiftTerminalView, context: Context) {
        DispatchQueue.main.async {
            nsView.refreshDisplay()
        }
    }

    public static func dismantleNSView(_ nsView: SwiftTerminalView, coordinator: ()) {
        // Clean up if needed
    }
}
#endif

#if canImport(UIKit)
extension STerminalView: UIViewRepresentable {
    public func makeUIView(context: Context) -> SwiftTerminalView {
        // Delay first responder activation slightly to allow the view to be in a window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.terminalView.makeTerminalFirstResponder()
        }
        return terminalView
    }

    public func updateUIView(_ uiView: SwiftTerminalView, context: Context) {
        DispatchQueue.main.async {
            uiView.refreshDisplay()
        }
    }

    public static func dismantleUIView(_ uiView: SwiftTerminalView, coordinator: ()) {
        // Clean up if needed
    }
}
#endif
