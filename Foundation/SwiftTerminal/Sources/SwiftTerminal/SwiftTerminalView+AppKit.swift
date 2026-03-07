//
//  SwiftTerminalView+AppKit.swift
//  SwiftTerminal
//
//  macOS NSView wrapper for SwiftTerm with Metal rendering
//

#if canImport(AppKit)
import AppKit
import SwiftTerm
import Metal
import MetalKit

/// macOS terminal view using SwiftTerm with Metal rendering
public class SwiftTerminalView: NSView {

    // MARK: - Properties

    private(set) public var metalView: MacMetalTerminalView!
    private let adapter: SwiftTerminalAdapter
    private var viewDelegate: MetalViewDelegateHandler?

    // MARK: - Initialization

    public required init(adapter: SwiftTerminalAdapter) {
        self.adapter = adapter
        super.init(frame: CGRect.zero)

        setupView()
        setupDelegates()
    }

    public convenience required init() {
        let adapter = SwiftTerminalAdapter()
        self.init(adapter: adapter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // Create Metal terminal view
        metalView = MacMetalTerminalView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))

        addSubview(metalView)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        metalView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        metalView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        metalView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true

        // Setup terminal with default options
        metalView.setupTerminal(options: TerminalOptions(cols: 80, rows: 24))

        // Note: allowMouseReporting defaults to true.
        // Mouse reporting is handled dynamically by MacMetalTerminalView:
        // - When terminal.mouseMode != .off (htop, vim, tmux), clicks are forwarded to the app.
        // - When terminal.mouseMode == .off (normal shell), clicks perform text selection.

        // Apply default font
        applyFont()
    }

    private func setupDelegates() {
        viewDelegate = MetalViewDelegateHandler(adapter: adapter)
        metalView.terminalDelegate = viewDelegate
    }

    // MARK: - First Responder Handling

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        // Forward first responder status to internal Metal view
        if let window = window {
            return window.makeFirstResponder(metalView)
        }
        return false
    }

    public override func resignFirstResponder() -> Bool {
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        // When clicked, make the terminal view first responder
        makeTerminalFirstResponder()
        super.mouseDown(with: event)
    }

    public override var canBecomeKeyView: Bool { true }

    public override var needsPanelToBecomeKey: Bool { true }

    // MARK: - Theme & Font

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

        guard let terminal = metalView.terminal else { return }

        // Set foreground and background colors
        terminal.foregroundColor = colors.foreground.toTerminalColor()
        terminal.backgroundColor = colors.background.toTerminalColor()

        // Install ANSI colors palette (16 colors)
        terminal.installPalette(colors: colors.ansiColors)

        // Set layer background color
        layer?.backgroundColor = NSColor(hex: theme.background).cgColor

        // Theme changes only affect colors; glyph cache remains valid.
        metalView.setTerminalNeedsDisplay()
    }

    private func applyFont() {
        let fontName = adapter.getCurrentFontName()
        let fontSize = CGFloat(adapter.getCurrentFontSize())

        let font: NSFont
        if let customFont = NSFont(name: fontName, size: fontSize) {
            font = customFont
        } else {
            // Fallback to Menlo if custom font not found
            font = NSFont(name: "Menlo", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        metalView.setupFont(font: font)
    }

    // MARK: - Public API

    public func getAdapter() -> SwiftTerminalAdapter {
        return adapter
    }

    public func feed(data: Data) {
        // Feed data to the terminal
        let bytes = Array(data)
        metalView.terminal?.feed(buffer: bytes[...])
        metalView.setTerminalNeedsDisplay()
    }

    public func feed(text: String) {
        // Feed host output into the terminal buffer.
        if let data = text.data(using: .utf8) {
            let bytes = Array(data)
            metalView.terminal?.feed(buffer: bytes[...])
            metalView.setTerminalNeedsDisplay()
        }
    }

    public func getTerminal() -> Terminal {
        return metalView.terminal!
    }

    /// Get the currently selected text
    public func getSelectedText() -> String {
        return metalView.getSelectedText()
    }

    public func updateTheme() {
        applyTheme()
    }

    public func updateFont() {
        applyFont()
    }

    /// Make the internal terminal view the first responder
    public func makeTerminalFirstResponder() {
        if let window = window {
            _ = window.makeFirstResponder(metalView)
        }
    }
}

// MARK: - Metal View Delegate Handler

private class MetalViewDelegateHandler: NSObject, MetalTerminalViewDelegate {
    private weak var adapter: SwiftTerminalAdapter?

    init(adapter: SwiftTerminalAdapter) {
        self.adapter = adapter
    }

    func sizeChanged(source: MetalTerminalView, newCols: Int, newRows: Int) {
        adapter?.notifySize(CGSize(width: newCols, height: newRows))
    }

    func setTerminalTitle(source: MetalTerminalView, title: String) {
        adapter?.notifyTitle(title)
    }

    func hostCurrentDirectoryUpdate(source: MetalTerminalView, directory: String?) {
        // Not used for SSH terminals
    }

    func send(source: MetalTerminalView, data: ArraySlice<UInt8>) {
        // User input from terminal - notify adapter
        let dataArray = Array(data)
        if let str = String(bytes: dataArray, encoding: .utf8) {
            adapter?.notifyBuffer(str)
        }
    }

    func scrolled(source: MetalTerminalView, position: Double) {
        // Terminal scrolled
    }

    func requestOpenLink(source: MetalTerminalView, link: String, params: [String: String]) {
        // Open link in default browser
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    func bell(source: MetalTerminalView) {
        adapter?.notifyBell()
    }

    func clipboardCopy(source: MetalTerminalView, content: Data) {
        if let str = String(data: content, encoding: .utf8) {
            adapter?.notifyCopy(str)
        }
    }

    func clipboardGet(source: MetalTerminalView) -> String {
        return NSPasteboard.general.string(forType: .string) ?? ""
    }

    func rangeChanged(source: MetalTerminalView, startY: Int, endY: Int) {
        // Visual changes in buffer - not used
    }

    func bufferActivated(source: MetalTerminalView) {
        // Buffer activated - not used
    }

    func iTermContent(source: MetalTerminalView, content: ArraySlice<UInt8>) {
        // iTerm2 specific OSC 1337 sequences - not used
    }

    func iconTitleChanged(source: MetalTerminalView, title: String) {
        // Icon title changed - not used
    }

    func windowTitleChanged(source: MetalTerminalView, title: String) {
        adapter?.notifyTitle(title)
    }
}

// MARK: - NSColor Extension

extension NSColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let length = hexSanitized.count
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            r = 0
            g = 0
            b = 0
            a = 1.0
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
#endif
