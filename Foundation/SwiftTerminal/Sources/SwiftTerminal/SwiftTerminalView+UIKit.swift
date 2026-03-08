//
//  SwiftTerminalView+UIKit.swift
//  SwiftTerminal
//
//  iOS UIView wrapper for SwiftTerm with Metal rendering
//

#if canImport(UIKit)
import UIKit
import SwiftTerm
import Metal
import MetalKit

/// iOS terminal view using SwiftTerm with Metal rendering
public class SwiftTerminalView: UIView {

    // MARK: - Properties

    private(set) public var metalView: iOSMetalTerminalView!
    private let adapter: SwiftTerminalAdapter
    private var viewDelegate: MetalViewDelegateHandler?
    private var lastLaidOutBounds: CGRect = .null
    private var lastAppliedFontPixelSignature: Int = -1
    private var lastNotifiedTerminalSize: CGSize = .zero
    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Initialization

    public required init(adapter: SwiftTerminalAdapter) {
        self.adapter = adapter
        super.init(frame: CGRect.zero)

        setupView()
        setupDelegates()
        setupLifecycleObservers()
    }

    public convenience required init() {
        let adapter = SwiftTerminalAdapter()
        self.init(adapter: adapter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = .black

        // Create Metal terminal view
        metalView = iOSMetalTerminalView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 1)

        addSubview(metalView)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        metalView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        metalView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        metalView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true

        // Setup terminal with default options
        metalView.setupTerminal(options: TerminalOptions(cols: 80, rows: 24))

        // Note: allowMouseReporting defaults to true.
        // Mouse reporting is handled dynamically by iOSMetalTerminalView:
        // - When terminal.mouseMode != .off (htop, vim, tmux), taps are forwarded to the app.
        // - When terminal.mouseMode == .off (normal shell), taps perform text selection.

        // Apply default font
        applyFont()
    }

    private func setupDelegates() {
        viewDelegate = MetalViewDelegateHandler(adapter: adapter)
        metalView.terminalDelegate = viewDelegate
        DispatchQueue.main.async { [weak self] in
            self?.syncAndNotifyTerminalSizeIfNeeded()
        }
    }

    private func setupLifecycleObservers() {
        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleRefreshDisplay()
            }
        )
        notificationObservers.append(
            center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleRefreshDisplay()
            }
        )
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

        guard let terminal = metalView.terminal else { return }

        // Set foreground and background colors
        terminal.foregroundColor = colors.foreground.toTerminalColor()
        terminal.backgroundColor = colors.background.toTerminalColor()

        // Install ANSI colors palette (16 colors)
        terminal.installPalette(colors: colors.ansiColors)

        // Set view background color
        backgroundColor = UIColor(hex: theme.background)
        metalView.backgroundColor = UIColor(hex: theme.background)
        metalView.clearColor = MTLClearColor(theme.background)

        // MTKView is paused and renders on demand, so force an immediate redraw here.
        metalView.setTerminalNeedsDisplay()
        metalView.draw()
    }

    private func applyFont() {
        let fontName = adapter.getCurrentFontName()
        let requestedFontSize = CGFloat(adapter.getCurrentFontSize())

        let baseFont: UIFont
        if let customFont = UIFont(name: fontName, size: requestedFontSize) {
            baseFont = customFont
        } else {
            // Fallback to Menlo if custom font not found
            baseFont = UIFont(name: "Menlo", size: requestedFontSize) ?? UIFont.monospacedSystemFont(ofSize: requestedFontSize, weight: .regular)
        }

        let font = baseFont
        let fontSignature = Int((font.pointSize * UIScreen.main.scale).rounded())
        guard fontSignature != lastAppliedFontPixelSignature else { return }
        lastAppliedFontPixelSignature = fontSignature

        metalView.setupFont(font: font)
        // MTKView is paused and renders on demand, so force an immediate redraw here.
        metalView.draw()
    }

    // MARK: - Public API

    public func getAdapter() -> SwiftTerminalAdapter {
        return adapter
    }

    public func feed(data: Data) {
        let bytes = Array(data)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = self.metalView.captureVisibleBufferSnapshot()
            self.metalView.terminal?.feed(buffer: bytes[...])
            self.metalView.normalizeViewportAfterExternalFeed()
            self.metalView.applyExternalFeedDiff(from: snapshot)
        }
    }

    public func feed(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        feed(data: data)
    }

    public func getTerminal() -> Terminal {
        return metalView.terminal!
    }

    public func requestTerminalSize() -> CGSize {
        metalView.fittingTerminalSize()
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

    public func refreshDisplay() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        metalView.refreshDisplay(clearCache: true, immediately: true)
    }

    private func scheduleRefreshDisplay() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshDisplay()
            self?.syncAndNotifyTerminalSizeIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.refreshDisplay()
            self?.syncAndNotifyTerminalSizeIfNeeded()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds != lastLaidOutBounds else { return }
        lastLaidOutBounds = bounds
        metalView.frame = bounds
        applyFont()
        syncAndNotifyTerminalSizeIfNeeded()
        metalView.setTerminalNeedsDisplay()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, bounds.width > 1, bounds.height > 1 {
            refreshDisplay()
            syncAndNotifyTerminalSizeIfNeeded()
        }
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil, bounds.width > 1, bounds.height > 1 {
            refreshDisplay()
            syncAndNotifyTerminalSizeIfNeeded()
        }
    }

    private func syncAndNotifyTerminalSizeIfNeeded() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        _ = metalView.syncTerminalSizeToView()
        guard let terminal = metalView.terminal else { return }
        let size = CGSize(width: terminal.cols, height: terminal.rows)
        guard size != lastNotifiedTerminalSize else { return }
        lastNotifiedTerminalSize = size
        adapter.notifySize(size)
    }

    /// Make the terminal view the first responder to receive keyboard input
    @discardableResult
    public func makeTerminalFirstResponder() -> Bool {
        return metalView.becomeFirstResponder()
    }

    @discardableResult
    public func resignTerminalFirstResponder() -> Bool {
        return metalView.resignFirstResponder()
    }

    // MARK: - Touch Handling

    /// Forward touch events to the metalView so it can become first responder
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // Make the metalView the first responder to receive keyboard input
        // The metalView handles its own tap gesture for this, but we also do it here for safety
        if !metalView.isFirstResponder {
            _ = metalView.becomeFirstResponder()
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
            UIApplication.shared.open(url)
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
        return UIPasteboard.general.string ?? ""
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

private extension MTLClearColor {
    init(_ hex: String) {
        let color = UIColor(hex: hex)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }
}
#endif
