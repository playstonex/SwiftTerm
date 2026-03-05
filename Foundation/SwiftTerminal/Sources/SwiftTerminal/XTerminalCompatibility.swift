//
//  XTerminalCompatibility.swift
//  SwiftTerminal
//
//  Provides XTerminal protocol conformance for SwiftTerminal
//  This allows drop-in replacement for XTerminalUI
//

import Foundation
import SwiftTerm

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// XTerminal-compatible wrapper for SwiftTerminal
/// This provides full compatibility with the existing XTerminal protocol
public protocol XTerminal: AnyObject {
    @discardableResult func setupBufferChain(callback: ((String) -> Void)?) -> Self
    @discardableResult func setupTitleChain(callback: ((String) -> Void)?) -> Self
    @discardableResult func setupBellChain(callback: (() -> Void)?) -> Self
    @discardableResult func setupSizeChain(callback: ((CGSize) -> Void)?) -> Self
    @discardableResult func setupCopyChain(callback: ((String) -> Void)?) -> Self
    @discardableResult func setupNavigationChain(callback: (() -> Void)?) -> Self
    func write(_ str: String)
    func requestTerminalSize() -> CGSize
    func setTerminalFontSize(with size: Int)
    func setTerminalFontName(with name: String)
    func getSelection(completion: @escaping (String?) -> Void)
    func setTerminalTheme(
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
    )
}

#if canImport(AppKit)
/// Native terminal view for macOS that conforms to XTerminal protocol
public class NativeTerminalView: NSView, XTerminal {
    private var terminalView: TerminalView!
    private let adapter: SwiftTerminalAdapter
    private var viewDelegate: ViewDelegateHandler?

    public required init() {
        let adapter = SwiftTerminalAdapter()
        self.adapter = adapter
        super.init(frame: CGRect.zero)

        setupView()
        setupDelegates()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        terminalView = TerminalView(frame: CGRect.zero)

        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        terminalView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        terminalView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        terminalView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
    }

    private func setupDelegates() {
        viewDelegate = ViewDelegateHandler(adapter: adapter)
        terminalView.terminalDelegate = viewDelegate
    }

    private func applyTheme() {
        guard let theme = adapter.getCurrentTheme() else { return }

        let colors = ThemeAdapter.parseTheme(
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

        // Install the 16 ANSI colors
        terminalView.installColors(colors.ansiColors)

        // Set foreground and background colors
        let terminal = terminalView.getTerminal()
        terminal.foregroundColor = colors.foreground.toTerminalColor()
        terminal.backgroundColor = colors.background.toTerminalColor()

        // Set layer background color
        layer?.backgroundColor = NSColor(hex: theme.background).cgColor
        terminalView.needsDisplay = true
    }

    private func applyFont() {
        let fontName = adapter.getCurrentFontName()
        let fontSize = CGFloat(adapter.getCurrentFontSize())

        if let font = NSFont(name: fontName, size: fontSize) {
            terminalView.font = font
        } else {
            terminalView.font = NSFont(name: "Menlo", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

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
        terminalView.getTerminal().feed(text: str)
    }

    public func requestTerminalSize() -> CGSize {
        let terminal = terminalView.getTerminal()
        return CGSize(width: terminal.cols, height: terminal.rows)
    }

    public func setTerminalFontSize(with size: Int) {
        adapter.setTerminalFontSize(with: size)
        applyFont()
    }

    public func setTerminalFontName(with name: String) {
        adapter.setTerminalFontName(with: name)
        applyFont()
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
        applyTheme()
    }

    public func getSelection(completion: @escaping (String?) -> Void) {
        // Use pasteboard to get selection
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        terminalView.copy(self)

        let selectedText = pasteboard.string(forType: .string) ?? ""

        if let old = oldContents {
            pasteboard.clearContents()
            pasteboard.setString(old, forType: .string)
        }

        completion(selectedText.isEmpty ? nil : selectedText)
    }
}

// MARK: - View Delegate Handler for AppKit

private class ViewDelegateHandler: NSObject, TerminalViewDelegate {
    private weak var adapter: SwiftTerminalAdapter?

    init(adapter: SwiftTerminalAdapter) {
        self.adapter = adapter
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        adapter?.notifySize(CGSize(width: newCols, height: newRows))
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        adapter?.notifyTitle(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let dataArray = Array(data)
        if let str = String(bytes: dataArray, encoding: .utf8) {
            adapter?.notifyBuffer(str)
        }
    }

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    func bell(source: TerminalView) {
        adapter?.notifyBell()
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        if let str = String(data: content, encoding: .utf8) {
            adapter?.notifyCopy(str)
        }
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
#endif

#if canImport(UIKit)
/// Native terminal view for iOS that conforms to XTerminal protocol
public class NativeTerminalView: UIView, XTerminal {
    private var terminalView: TerminalView!
    private let adapter: SwiftTerminalAdapter
    private var viewDelegate: ViewDelegateHandler?
    public var onLongPress: ((String) -> Void)?

    public required init() {
        let adapter = SwiftTerminalAdapter()
        self.adapter = adapter
        super.init(frame: CGRect.zero)

        setupView()
        setupDelegates()

        // Add long press gesture for copying
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            getSelection { [weak self] selection in
                if let selection = selection, !selection.isEmpty {
                    self?.onLongPress?(selection)
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = .black

        terminalView = TerminalView(frame: CGRect.zero)

        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        terminalView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        terminalView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        terminalView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
    }

    private func setupDelegates() {
        viewDelegate = ViewDelegateHandler(adapter: adapter)
        terminalView.terminalDelegate = viewDelegate
    }

    private func applyTheme() {
        guard let theme = adapter.getCurrentTheme() else { return }

        let colors = ThemeAdapter.parseTheme(
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

        // Install the 16 ANSI colors
        terminalView.installColors(colors.ansiColors)

        // Set foreground and background colors
        let terminal = terminalView.getTerminal()
        terminal.foregroundColor = colors.foreground.toTerminalColor()
        terminal.backgroundColor = colors.background.toTerminalColor()

        // Set view background color
        backgroundColor = UIColor(hex: theme.background)
        terminalView.setNeedsDisplay()
    }

    private func applyFont() {
        let fontName = adapter.getCurrentFontName()
        let fontSize = CGFloat(adapter.getCurrentFontSize())

        if let font = UIFont(name: fontName, size: fontSize) {
            terminalView.font = font
        } else {
            terminalView.font = UIFont(name: "Menlo", size: fontSize) ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

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
        terminalView.getTerminal().feed(text: str)
    }

    public func requestTerminalSize() -> CGSize {
        let terminal = terminalView.getTerminal()
        return CGSize(width: terminal.cols, height: terminal.rows)
    }

    public func setTerminalFontSize(with size: Int) {
        adapter.setTerminalFontSize(with: size)
        applyFont()
    }

    public func setTerminalFontName(with name: String) {
        adapter.setTerminalFontName(with: name)
        applyFont()
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
        applyTheme()
    }

    public func getSelection(completion: @escaping (String?) -> Void) {
        // Use pasteboard to get selection
        let pasteboard = UIPasteboard.general
        let oldContents = pasteboard.string

        terminalView.copy(UIApplication.shared)

        let selectedText = pasteboard.string ?? ""

        if let old = oldContents {
            pasteboard.string = old
        }

        completion(selectedText.isEmpty ? nil : selectedText)
    }
}

// MARK: - View Delegate Handler for UIKit

private class ViewDelegateHandler: NSObject, TerminalViewDelegate {
    private weak var adapter: SwiftTerminalAdapter?

    init(adapter: SwiftTerminalAdapter) {
        self.adapter = adapter
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        adapter?.notifySize(CGSize(width: newCols, height: newRows))
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        adapter?.notifyTitle(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let dataArray = Array(data)
        if let str = String(bytes: dataArray, encoding: .utf8) {
            adapter?.notifyBuffer(str)
        }
    }

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            UIApplication.shared.open(url)
        }
    }

    func bell(source: TerminalView) {
        adapter?.notifyBell()
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        if let str = String(data: content, encoding: .utf8) {
            adapter?.notifyCopy(str)
        }
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
#endif
