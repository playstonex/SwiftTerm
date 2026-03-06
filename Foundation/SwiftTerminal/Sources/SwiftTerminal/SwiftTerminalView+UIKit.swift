//
//  SwiftTerminalView+UIKit.swift
//  SwiftTerminal
//
//  iOS UIView wrapper for SwiftTerm
//

#if canImport(UIKit)
import UIKit
import SwiftTerm

/// iOS terminal view using SwiftTerm with native rendering
public class SwiftTerminalView: UIView {

    // MARK: - Properties

    private var terminalView: TerminalView!
    private let adapter: SwiftTerminalAdapter
    private var viewDelegate: ViewDelegateHandler?

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
        backgroundColor = .black

        terminalView = TerminalView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))

        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        terminalView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        terminalView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        terminalView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true

        // Apply default theme
        applyFont()
    }

    private func setupDelegates() {
        viewDelegate = ViewDelegateHandler(adapter: adapter)
        terminalView.terminalDelegate = viewDelegate
    }

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

        // Install the 16 ANSI colors
        terminalView.installColors(colors.ansiColors)

        // Set foreground and background colors
        let terminal = terminalView.getTerminal()
        terminal.foregroundColor = colors.foreground.toTerminalColor()
        terminal.backgroundColor = colors.background.toTerminalColor()

        // Set view background color
        backgroundColor = UIColor(hex: theme.background)

        // Trigger a refresh
        terminalView.setNeedsDisplay()
    }

    private func applyFont() {
        let fontName = adapter.getCurrentFontName()
        let fontSize = CGFloat(adapter.getCurrentFontSize())

        if let font = UIFont(name: fontName, size: fontSize) {
            terminalView.font = font
        } else {
            // Fallback to Menlo if custom font not found
            terminalView.font = UIFont(name: "Menlo", size: fontSize) ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

    // MARK: - Public API

    public func getAdapter() -> SwiftTerminalAdapter {
        return adapter
    }

    public func feed(data: Data) {
        let array = Array(data)
        terminalView.feed(byteArray: Array(data)[...])
    }

    public func feed(text: String) {
        terminalView.feed(text: text)
    }

    public func getTerminal() -> Terminal {
        return terminalView.getTerminal()
    }

    /// Get the currently selected text
    /// Uses clipboard copy internally as SwiftTerm doesn't expose selection publicly
    public func getSelectedText() -> String {
        // Get selection using UIPasteboard
        let pasteboard = UIPasteboard.general
        let oldContents = pasteboard.string

        // Trigger copy on terminal view
        terminalView.copy(UIApplication.shared)

        // Read the selected text
        let selectedText = pasteboard.string ?? ""

        // Restore old contents if there was any
        if let old = oldContents {
            pasteboard.string = old
        }

        return selectedText
    }

    public func updateTheme() {
        applyTheme()
    }

    public func updateFont() {
        applyFont()
    }
}

// MARK: - View Delegate Handler

private class ViewDelegateHandler: NSObject, TerminalViewDelegate {
    private weak var adapter: SwiftTerminalAdapter?
    private weak var terminalView: TerminalView?

    init(adapter: SwiftTerminalAdapter, terminalView: TerminalView? = nil) {
        self.adapter = adapter
        self.terminalView = terminalView
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        adapter?.notifySize(CGSize(width: newCols, height: newRows))
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        adapter?.notifyTitle(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Not used for SSH terminals
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        // User input from terminal - notify adapter
        let dataArray = Array(data)
        if let str = String(bytes: dataArray, encoding: .utf8) {
            adapter?.notifyBuffer(str)
        }
    }

    func scrolled(source: TerminalView, position: Double) {
        // Terminal scrolled
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        // Open link in default browser
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

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        // iTerm2 specific OSC 1337 sequences - not used
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        // Visual changes in buffer - not used
    }
}

// MARK: - UIColor Extension

extension UIColor {
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
