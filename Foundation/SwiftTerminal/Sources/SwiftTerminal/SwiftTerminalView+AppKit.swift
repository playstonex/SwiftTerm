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
    private var lastLaidOutBounds: CGRect = .null
    private var notificationObservers: [NSObjectProtocol] = []

    // Cursor blinking state
    private var cursorBlinkTimer: Timer?
    private var cursorVisible = true
    private var isCursorBlinkingEnabled = true

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
        stopCursorBlinkTimer()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // Create Metal terminal view
        metalView = MacMetalTerminalView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
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
        // Mouse reporting is handled dynamically by MacMetalTerminalView:
        // - When terminal.mouseMode != .off (htop, vim, tmux), clicks are forwarded to the app.
        // - When terminal.mouseMode == .off (normal shell), clicks perform text selection.

        // Apply default font
        applyFont()
    }

    private func setupDelegates() {
        viewDelegate = MetalViewDelegateHandler(adapter: adapter)
        metalView.terminalDelegate = viewDelegate
        // Start cursor blinking after terminal is set up
        Task { @MainActor [weak self] in
            self?.startCursorBlinkTimerIfNeeded()
        }
    }

    private func setupLifecycleObservers() {
        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleRefreshDisplay()
                self?.startCursorBlinkTimerIfNeeded()
            }
        )
        notificationObservers.append(
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self, notification.object as? NSWindow === self.window else { return }
                self.scheduleRefreshDisplay()
                self.startCursorBlinkTimerIfNeeded()
            }
        )
        notificationObservers.append(
            center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.stopCursorBlinkTimer()
            }
        )
    }

    // MARK: - Cursor Blinking

    private func startCursorBlinkTimerIfNeeded() {
        guard isCursorBlinkingEnabled else { return }
        stopCursorBlinkTimer()

        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.toggleCursorBlink()
        }
        RunLoop.current.add(cursorBlinkTimer!, forMode: .common)
    }

    private func stopCursorBlinkTimer() {
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = nil
    }

    private func toggleCursorBlink() {
        guard let terminal = metalView.terminal else { return }
        // Only blink for blink cursor styles
        let style = terminal.options.cursorStyle
        switch style {
        case .blinkBlock, .blinkUnderline, .blinkBar:
            cursorVisible.toggle()
            metalView.renderer?.setCursorVisible(cursorVisible)
            metalView.setTerminalNeedsDisplay()
        case .steadyBlock, .steadyUnderline, .steadyBar:
            // Steady cursor doesn't blink
            cursorVisible = true
        }
    }

    /// Reset cursor visibility (call this when user types or cursor moves)
    public func resetCursorBlink() {
        cursorVisible = true
        metalView.renderer?.setCursorVisible(true)
        metalView.setTerminalNeedsDisplay()
        // Restart timer to sync blink cycle
        startCursorBlinkTimerIfNeeded()
    }

    /// Enable or disable cursor blinking
    public func setCursorBlinkingEnabled(_ enabled: Bool) {
        isCursorBlinkingEnabled = enabled
        if enabled {
            startCursorBlinkTimerIfNeeded()
        } else {
            stopCursorBlinkTimer()
            cursorVisible = true
            metalView.renderer?.setCursorVisible(true)
            metalView.setTerminalNeedsDisplay()
        }
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
        metalView.clearColor = MTLClearColor(theme.background)

        // Compute a theme-aware selection color: bright on dark, muted on light
        metalView.selectionColor = SwiftTerminalView.contrastingSelectionColor(
            bgRed: colors.background.red,
            bgGreen: colors.background.green,
            bgBlue: colors.background.blue
        )

        // MTKView is paused and renders on demand, so force an immediate redraw here.
        metalView.setTerminalNeedsDisplay()
        metalView.draw()
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
        // MTKView is paused and renders on demand, so force an immediate redraw here.
        metalView.draw()
    }

    // MARK: - Public API

    public func getAdapter() -> SwiftTerminalAdapter {
        return adapter
    }

    public func setOnTextSelected(_ handler: @escaping (String) -> Void) {
        metalView.onTextSelected = handler
    }

    public func feed(data: Data) {
        let bytes = Array(data)
        func process() {
            let snapshot = self.metalView.captureVisibleBufferSnapshot()
            self.metalView.terminal?.feed(buffer: bytes[...])
            self.metalView.normalizeViewportAfterExternalFeed()
            self.metalView.applyExternalFeedDiff(from: snapshot)
            // Ensure the Metal view re-renders with updated content.
            // Force an immediate draw, then schedule a deferred refresh to handle
            // cases where the drawable isn't available on the first attempt.
            self.metalView.refreshDisplay(immediately: true)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.metalView.refreshDisplay(immediately: true)
            }
        }
        if Thread.isMainThread {
            process()
        } else {
            Task { @MainActor in process() }
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
        // Ensure the terminal buffer matches the view bounds before reporting size.
        // This is critical for alternate buffer mode (e.g., vim) where the buffer
        // may not have been resized since the last layout pass.
        metalView.syncTerminalSizeToView()
        return metalView.fittingTerminalSize()
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
        // Window focus and view reattachment do not always line up with the first drawable update.
        // Retry once on the next short tick to avoid stale content after the app becomes active.
        Task { @MainActor [weak self] in
            self?.refreshDisplay()
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            self?.refreshDisplay()
        }
    }

    public override func layout() {
        super.layout()
        guard bounds != lastLaidOutBounds else { return }
        lastLaidOutBounds = bounds
        metalView.frame = bounds
        metalView.setTerminalNeedsDisplay()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, bounds.width > 1, bounds.height > 1 {
            refreshDisplay()
            startCursorBlinkTimerIfNeeded()
        } else {
            stopCursorBlinkTimer()
        }
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil, bounds.width > 1, bounds.height > 1 {
            refreshDisplay()
        }
    }

    /// Make the internal terminal view the first responder
    public func makeTerminalFirstResponder() {
        if let window = window {
            _ = window.makeFirstResponder(metalView)
        }
    }

    /// Compute a selection highlight color that contrasts with the terminal background.
    /// Uses sourceAlpha blending (src * srcAlpha + dst * (1 - srcAlpha)),
    /// so we provide premultiplied RGBA values.
    private static func contrastingSelectionColor(bgRed: Double, bgGreen: Double, bgBlue: Double) -> SIMD4<Float> {
        // Perceived luminance (ITU-R BT.709)
        let luminance = 0.2126 * bgRed + 0.7152 * bgGreen + 0.0722 * bgBlue

        if luminance < 0.5 {
            // Dark background: use a bright blue-cyan selection with 0.45 alpha
            return SIMD4<Float>(0.26, 0.53, 0.96, 0.45)
        } else {
            // Light background: use a darker blue selection with 0.35 alpha
            return SIMD4<Float>(0.15, 0.30, 0.75, 0.35)
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

private extension MTLClearColor {
    init(_ hex: String) {
        let color = NSColor(hex: hex)
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        self.init(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent),
            alpha: Double(rgb.alphaComponent)
        )
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
