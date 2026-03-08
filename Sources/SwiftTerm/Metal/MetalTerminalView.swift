//
//  MetalTerminalView.swift
//  SwiftTerm
//
//  Shared Metal-based terminal view for Apple platforms.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import Metal
import MetalKit
import CoreText

#if os(iOS) || os(visionOS)
import UIKit
public typealias MTView = MTKView
#endif

#if os(macOS)
import AppKit
public typealias MTView = MTKView
#endif

/// Delegate used by MetalTerminalView to notify the user of events
public protocol MetalTerminalViewDelegate: AnyObject {
    /// The client code has requested a new terminal size
    func sizeChanged(source: MetalTerminalView, newCols: Int, newRows: Int)

    /// Request to change the terminal title
    func setTerminalTitle(source: MetalTerminalView, title: String)

    /// Invoked when the current directory has changed
    func hostCurrentDirectoryUpdate(source: MetalTerminalView, directory: String?)

    /// Request that data be sent to the application
    func send(source: MetalTerminalView, data: ArraySlice<UInt8>)

    /// Invoked when the terminal has been scrolled
    func scrolled(source: MetalTerminalView, position: Double)

    /// Invoked when a link is activated
    func requestOpenLink(source: MetalTerminalView, link: String, params: [String: String])

    /// Invoked when the host beeps
    func bell(source: MetalTerminalView)

    /// Invoked when clipboard data should be copied
    func clipboardCopy(source: MetalTerminalView, content: Data)

    /// Get clipboard content
    func clipboardGet(source: MetalTerminalView) -> String

    /// Invoked when buffer has changed
    func rangeChanged(source: MetalTerminalView, startY: Int, endY: Int)

    /// Invoked when the buffer is activated
    func bufferActivated(source: MetalTerminalView)

    /// Invoked when iTerm content is received
    func iTermContent(source: MetalTerminalView, content: ArraySlice<UInt8>)

    /// Invoked when icon title changes
    func iconTitleChanged(source: MetalTerminalView, title: String)

    /// Invoked when window title changes
    func windowTitleChanged(source: MetalTerminalView, title: String)
}

/// Default implementations for MetalTerminalViewDelegate
public extension MetalTerminalViewDelegate {
    func setTerminalTitle(source: MetalTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: MetalTerminalView, directory: String?) {}
    func scrolled(source: MetalTerminalView, position: Double) {}
    func requestOpenLink(source: MetalTerminalView, link: String, params: [String: String]) {}
    func bell(source: MetalTerminalView) {}
    func clipboardCopy(source: MetalTerminalView, content: Data) {}
    func clipboardGet(source: MetalTerminalView) -> String { return "" }
    func rangeChanged(source: MetalTerminalView, startY: Int, endY: Int) {}
    func bufferActivated(source: MetalTerminalView) {}
    func iTermContent(source: MetalTerminalView, content: ArraySlice<UInt8>) {}
    func iconTitleChanged(source: MetalTerminalView, title: String) {}
    func windowTitleChanged(source: MetalTerminalView, title: String) {}
}

/// A font set for rendering terminal content
struct FontSet {
    let normal: CTFont
    let bold: CTFont
    let italic: CTFont
    let boldItalic: CTFont

    init(normal: CTFont, bold: CTFont, italic: CTFont, boldItalic: CTFont) {
        self.normal = normal
        self.bold = bold
        self.italic = italic
        self.boldItalic = boldItalic
    }

    /// Create a font set from a base font
    init(baseFont: CTFont) {
        self.normal = baseFont

        // Create bold variant
        let traits: [String: Any] = [
            kCTFontWeightTrait as String: 0.4
        ]
        let boldDescriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(baseFont),
            traits as CFDictionary
        )
        self.bold = CTFontCreateWithFontDescriptor(boldDescriptor, CTFontGetSize(baseFont), nil)

        // Create italic variant
        let italicDescriptor = CTFontDescriptorCreateCopyWithSymbolicTraits(
            CTFontCopyFontDescriptor(baseFont),
            .traitItalic,
            .traitItalic
        )
        self.italic = CTFontCreateWithFontDescriptor(italicDescriptor ?? CTFontCopyFontDescriptor(baseFont), CTFontGetSize(baseFont), nil)

        // Create bold-italic variant
        let boldItalicDescriptor = CTFontDescriptorCreateCopyWithSymbolicTraits(
            CTFontCopyFontDescriptor(baseFont),
            [.traitBold, .traitItalic],
            [.traitBold, .traitItalic]
        )
        self.boldItalic = CTFontCreateWithFontDescriptor(boldItalicDescriptor ?? CTFontCopyFontDescriptor(baseFont), CTFontGetSize(baseFont), nil)
    }

    /// Get underline position for the font
    func underlinePosition() -> CGFloat {
        return CTFontGetUnderlinePosition(normal)
    }

    /// Get underline thickness for the font
    func underlineThickness() -> CGFloat {
        return CTFontGetUnderlineThickness(normal)
    }
}

/// Metal-based terminal view for Apple platforms
open class MetalTerminalView: MTView, TerminalDelegate {
    private var suppressLargeCursorRangeChanges = false

    private func pinViewportToBottomIfNeeded(for source: Terminal) {
        guard !source.userScrolling else { return }
        let displayBuffer = source.displayBuffer
        guard displayBuffer.yDisp != displayBuffer.yBase else { return }
        source.setViewYDisp(displayBuffer.yBase)
    }

    public func normalizeViewportAfterExternalFeed() {
        guard let terminal else { return }
        pinViewportToBottomIfNeeded(for: terminal)
    }

    public struct VisibleBufferSnapshot {
        let rowSignatures: [Int]
        let cursorCol: Int
        let cursorRow: Int
        let topVisibleRow: Int
        let cols: Int
        let rows: Int
    }
    /// The terminal emulator
    public var terminal: Terminal!

    /// The font set for rendering
    var fontSet: FontSet!

    /// The Metal renderer
    public var renderer: TerminalRenderer?

    /// Cell dimensions
    public var cellDimension: CGSize = .zero

    /// The selection service
    internal var selection: SelectionService?

    /// The search service
    internal var search: SearchService?

    /// The terminal delegate (for external events)
    public weak var terminalDelegate: MetalTerminalViewDelegate?

    /// The accessibility service
    internal var accessibility: AccessibilityService = AccessibilityService()

    /// Native foreground color
    internal var nativeForegroundColor: TTColor = TTColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

    /// Native background color
    internal var nativeBackgroundColor: TTColor = TTColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)

    /// Caret color
    internal var caretColor: TTColor = TTColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

    /// Caret text color
    internal var caretTextColor: TTColor = TTColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)

    /// Use bright colors for bold
    public var useBrightColors: Bool = true

    // MARK: - Initialization

    /// Configure MTKView for on-demand terminal rendering.
    private func configureMetalView() {
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        enableSetNeedsDisplay = true
        isPaused = true
        // Set content scale factor for retina display
        #if os(macOS)
        wantsLayer = true
        layer?.contentsScale = scale
        autoresizingMask = [.width, .height]
        #else
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #endif
    }

    /// Keep drawable size and projection matrix aligned with the view's point-based layout.
    internal func updateDrawableMetrics() {
        let drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        self.drawableSize = drawableSize
        renderer?.updateProjectionMatrix(size: bounds.size)
    }

    /// Initialize the terminal view with options
    public func setupTerminal(options: TerminalOptions? = nil) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        self.device = device
        configureMetalView()

        // Set up the terminal
        let terminalOptions = options ?? TerminalOptions(cols: 80, rows: 24)
        terminal = Terminal(delegate: self, options: terminalOptions)

        // Set up colors
        terminal.backgroundColor = Color.defaultBackground
        terminal.foregroundColor = Color.defaultForeground

        // Set up selection
        selection = SelectionService(terminal: terminal)
        search = SearchService(terminal: terminal)

        // Set up the renderer
        setupRenderer()
    }

    /// Set up the Metal renderer
    func setupRenderer() {
        guard let device = device,
              let fontSet = fontSet,
              cellDimension != .zero else {
            return
        }

        let scale = self.scale

        if renderer == nil {
            renderer = TerminalRenderer(
                device: device,
                terminal: terminal,
                fontSet: fontSet,
                cellDimension: cellDimension,
                scale: scale
            )
        } else {
            renderer?.update(terminal: terminal, fontSet: fontSet, cellDimension: cellDimension, scale: scale)
        }

        self.delegate = renderer
        renderer?.selection = selection
        updateDrawableMetrics()

        // Resize terminal to fit current view bounds if bounds are valid
        if bounds.width > 0 && bounds.height > 0 {
            handleResize(newSize: bounds.size)
        }
    }

    /// Set up fonts
    public func setupFont(font: TTFont) {
        let ctFont = font as CTFont
        self.fontSet = FontSet(baseFont: ctFont)
        computeCellDimension()

        // Always setup renderer when font is set, even if it's the first time
        if renderer == nil {
            setupRenderer()
        } else if let renderer = renderer, let fontSet = fontSet {
            renderer.update(terminal: terminal, fontSet: fontSet, cellDimension: cellDimension, scale: scale)
            updateDrawableMetrics()
        }

        // Trigger resize after font setup to ensure proper dimensions
        if bounds.width > 0 && bounds.height > 0 {
            handleResize(newSize: bounds.size)
        }
    }

    /// Compute cell dimensions from the font
    public func computeCellDimension() {
        guard let fontSet = fontSet else { return }

        let lineAscent = CTFontGetAscent(fontSet.normal)
        let lineDescent = CTFontGetDescent(fontSet.normal)
        let lineLeading = CTFontGetLeading(fontSet.normal)
        let cellHeight = ceil(lineAscent + lineDescent + lineLeading)

        var glyph = fontSet.normal.glyph(withName: "M")
        if glyph == 0 {
            glyph = fontSet.normal.glyph(withName: "W")
        }

        var advancement = CGSize()
        CTFontGetAdvancesForGlyphs(fontSet.normal, .horizontal, &glyph, &advancement, 1)

        let measuredCellWidth: CGFloat
        if advancement.width > 0 {
            measuredCellWidth = advancement.width
        } else {
            var boundingRect = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(fontSet.normal, .horizontal, &glyph, &boundingRect, 1)
            measuredCellWidth = boundingRect.width
        }

        let scale = self.scale
        let snappedWidth = ceil(measuredCellWidth * scale) / scale
        let snappedHeight = ceil(cellHeight * scale) / scale

        self.cellDimension = CGSize(width: max(1, snappedWidth), height: max(min(snappedHeight, 8192), 1))
    }

    /// Get the backing scale factor
    public var scale: CGFloat {
        #if os(macOS)
        if let window = self.window {
            return window.backingScaleFactor
        }
        // Fallback to main screen scale when window is not available
        return NSScreen.main?.backingScaleFactor ?? 2.0
        #else
        return self.window?.windowScene?.screen.scale ?? UIScreen.main.scale
        #endif
    }

    // MARK: - Renderer Info

    /// Information about the Metal renderer configuration
    public struct RendererInfo {
        public let renderer: String
        public let gpuName: String
        public let glyphAtlasSize: String
        public let atlasCount: Int
        public let maxAtlases: Int
        public let displayScale: CGFloat
        public let cellDimension: CGSize

        public var description: String {
            """
            Terminal Renderer: \(renderer)
            GPU: \(gpuName)
            Glyph atlas: \(glyphAtlasSize)
            Display scale: \(displayScale)x
            Cell size: \(Int(cellDimension.width))x\(Int(cellDimension.height))
            """
        }
    }

    /// Get information about the current Metal renderer configuration
    public var rendererInfo: RendererInfo? {
        guard let device = device,
              let renderer = renderer else {
            return nil
        }

        let atlasSize = renderer.cellRenderer.glyphCache.atlasSize
        let atlasCount = renderer.cellRenderer.glyphCache.atlasCount
        let maxAtlases = renderer.cellRenderer.glyphCache.maxAtlases

        return RendererInfo(
            renderer: "Metal",
            gpuName: device.name,
            glyphAtlasSize: "\(atlasSize)x\(atlasSize)",
            atlasCount: atlasCount,
            maxAtlases: maxAtlases,
            displayScale: scale,
            cellDimension: cellDimension
        )
    }

    // MARK: - TerminalDelegate

    public func showCursor(source: Terminal) {
        suppressLargeCursorRangeChanges = true
        renderer?.markCursorDirty()
        setTerminalNeedsDisplay()
    }

    public func hideCursor(source: Terminal) {
        suppressLargeCursorRangeChanges = true
        renderer?.markCursorDirty()
        setTerminalNeedsDisplay()
    }

    public func scrollChanged(source: Terminal) {
        suppressLargeCursorRangeChanges = false
        pinViewportToBottomIfNeeded(for: source)
        renderer?.markAllDirty(reason: "scrollChanged")
        setTerminalNeedsDisplay()
        let displayBuffer = source.displayBuffer
        terminalDelegate?.scrolled(source: self, position: Double(displayBuffer.yDisp) / Double(max(1, displayBuffer.lines.count - source.rows)))
    }

    public func rangeChanged(source: Terminal, startY: Int, endY: Int) {
        if suppressLargeCursorRangeChanges {
            setTerminalNeedsDisplay()
            return
        }
        renderer?.markDirtyViewportRows(startY: startY, endY: endY, terminal: source)
        setTerminalNeedsDisplay()
        terminalDelegate?.rangeChanged(source: self, startY: startY, endY: endY)
    }

    public func screenChanged(source: Terminal) {
        suppressLargeCursorRangeChanges = false
        pinViewportToBottomIfNeeded(for: source)
        renderer?.markAllDirty(reason: "screenChanged")
        setTerminalNeedsDisplay()
    }

    public func lineBufferChanged(source: Terminal, startY: Int, endY: Int) {
        pinViewportToBottomIfNeeded(for: source)
        renderer?.markAllDirty(reason: "lineBufferChanged")
        renderer?.markCursorDirty()
        setTerminalNeedsDisplay()
    }

    public func bell(source: Terminal) {
        terminalDelegate?.bell(source: self)
    }

    public func bufferActivated(source: Terminal) {
        pinViewportToBottomIfNeeded(for: source)
        renderer?.clearCache()
        renderer?.markAllDirty(reason: "bufferActivated")
        setTerminalNeedsDisplay()
        terminalDelegate?.bufferActivated(source: self)
    }

    public func windowTitleChanged(source: Terminal) {
        terminalDelegate?.windowTitleChanged(source: self, title: source.terminalTitle)
    }

    public func iconTitleChanged(source: Terminal) {
        terminalDelegate?.iconTitleChanged(source: self, title: source.iconTitle)
    }

    public func colorsChanged(source: Terminal) {
        suppressLargeCursorRangeChanges = false
        renderer?.clearCache()
        setTerminalNeedsDisplay()
    }

    public func mouseModeChanged(source: Terminal) {
        // Handled by platform-specific implementations
    }

    public func isProcessTrusted(source: Terminal) -> Bool {
        return true // Platform-specific implementations should override
    }

    public func clipboardCopy(source: Terminal, content: Data) {
        terminalDelegate?.clipboardCopy(source: self, content: content)
    }

    public func sizeChanged(source: Terminal) {
        suppressLargeCursorRangeChanges = false
        renderer?.markAllDirty(reason: "sizeChanged")
        terminalDelegate?.sizeChanged(source: self, newCols: source.cols, newRows: source.rows)
        setTerminalNeedsDisplay()
    }

    public func send(source: Terminal, data: ArraySlice<UInt8>) {
        terminalDelegate?.send(source: self, data: data)
    }

    public func hostCurrentDirectoryUpdated(source: Terminal) {
        terminalDelegate?.hostCurrentDirectoryUpdate(source: self, directory: source.hostCurrentDirectory)
    }

    public func setBackgroundColor(source: Terminal, color: Color) {
        nativeBackgroundColor = TTColor.make(color: color)
        colorsChanged(source: source)
    }

    public func setForegroundColor(source: Terminal, color: Color) {
        nativeForegroundColor = TTColor.make(color: color)
        colorsChanged(source: source)
    }

    public func setCursorColor(source: Terminal, color: Color?) {
        if let setColor = color {
            caretColor = TTColor.make(color: setColor)
        }
    }

    public func colorChanged(source: Terminal, idx: Int?) {
        colorsChanged(source: source)
    }

    public func synchronizedOutputChanged(source: Terminal, active: Bool) {
        pinViewportToBottomIfNeeded(for: source)
        renderer?.clearCache()
        renderer?.markAllDirty(reason: active ? "synchronizedOutputBegin" : "synchronizedOutputEnd")
        setTerminalNeedsDisplay()
    }

    public func setTerminalTitle(source: Terminal, title: String) {
        terminalDelegate?.setTerminalTitle(source: self, title: title)
    }

    public func setTerminalIconTitle(source: Terminal, title: String) {
        terminalDelegate?.setTerminalTitle(source: self, title: title)
    }

    public func windowCommand(source: Terminal, command: Terminal.WindowManipulationCommand) -> [UInt8]? {
        return nil
    }

    public func scrolled(source: Terminal, yDisp: Int) {
        renderer?.markAllDirty(reason: "viewportScrolled")
        renderer?.markCursorDirty()
        setTerminalNeedsDisplay()
        let displayBuffer = source.displayBuffer
        terminalDelegate?.scrolled(source: self, position: Double(displayBuffer.yDisp) / Double(max(1, displayBuffer.lines.count - source.rows)))
    }

    public func linefeed(source: Terminal) {
        // Handled internally
    }

    public func selectionChanged(source: Terminal) {
        renderer?.markSelectionDirty()
        setTerminalNeedsDisplay()
    }

    public func cellSizeInPixels(source: Terminal) -> (width: Int, height: Int)? {
        return (Int(cellDimension.width), Int(cellDimension.height))
    }

    public func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {
        renderer?.markCursorDirty()
        setTerminalNeedsDisplay()
    }

    public func hostCurrentDocumentUpdated(source: Terminal) {
        // Handled by platform-specific implementations
    }

    public func getColors(source: Terminal) -> (foreground: Color, background: Color) {
        return (source.foregroundColor, source.backgroundColor)
    }

    public func iTermContent(source: Terminal, content: ArraySlice<UInt8>) {
        // Handled by platform-specific implementations
    }

    public func notify(source: Terminal, title: String, body: String) {
        // Handled by platform-specific implementations
    }

    public func progressReport(source: Terminal, report: Terminal.ProgressReport) {
        // Handled by platform-specific implementations
    }

    public func createImageFromBitmap(source: Terminal, bytes: inout [UInt8], width: Int, height: Int) {
        // Metal terminal rendering does not support terminal images yet.
        // Keep the renderer in a clear unsupported state rather than using a partial GPU path.
        setTerminalNeedsDisplay()
    }

    public func createImage(source: Terminal, data: Data, width: ImageSizeRequest, height: ImageSizeRequest, preserveAspectRatio: Bool) {
        // Metal terminal rendering does not support terminal images yet.
        // Keep the renderer in a clear unsupported state rather than using a partial GPU path.
        setTerminalNeedsDisplay()
    }

    /// Set the needs display flag
    public func setTerminalNeedsDisplay() {
        #if os(macOS)
        needsDisplay = true
        #else
        setNeedsDisplay(bounds)
        #endif
    }

    /// Queue a pending display update
    public func queuePendingDisplay() {
        setTerminalNeedsDisplay()
    }

    open override func draw() {
        if bounds.width > 1, bounds.height > 1 {
            _ = syncTerminalSizeToView()
        }
        super.draw()
    }

    public func fittingTerminalSize() -> CGSize {
        guard bounds.width > 1, bounds.height > 1 else {
            return CGSize(width: max(1, terminal?.cols ?? 80), height: max(1, terminal?.rows ?? 24))
        }
        guard cellDimension.width > 0, cellDimension.height > 0 else {
            return CGSize(width: max(1, terminal?.cols ?? 80), height: max(1, terminal?.rows ?? 24))
        }

        let cols = max(1, Int(bounds.width / cellDimension.width))
        let rows = max(1, Int(bounds.height / cellDimension.height))
        return CGSize(width: cols, height: rows)
    }

    @discardableResult
    public func syncTerminalSizeToView() -> Bool {
        guard let terminal else { return false }
        guard bounds.width > 1, bounds.height > 1 else { return false }
        guard cellDimension.width > 0, cellDimension.height > 0 else { return false }

        updateDrawableMetrics()

        let targetSize = fittingTerminalSize()
        let newCols = Int(targetSize.width)
        let newRows = Int(targetSize.height)
        guard newCols > 0, newRows > 0 else { return false }

        if newCols != terminal.cols || newRows != terminal.rows {
            selection?.active = false
            terminal.resize(cols: newCols, rows: newRows)
            renderer?.markAllDirty(reason: "syncTerminalSizeToView")
            setTerminalNeedsDisplay()
            return true
        }

        return false
    }

    /// Force a complete redraw when the view is reattached or visibility changes.
    public func refreshDisplay(clearCache: Bool = false, immediately: Bool = false) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        _ = syncTerminalSizeToView()
        if clearCache {
            renderer?.clearCache()
        } else {
            renderer?.markAllDirty(reason: "refreshDisplay")
        }
        renderer?.markSelectionDirty()
        renderer?.markCursorDirty()
        setTerminalNeedsDisplay()
        if immediately {
            draw()
        }
    }

    public func captureVisibleBufferSnapshot() -> VisibleBufferSnapshot? {
        guard let terminal else { return nil }
        let buffer = terminal.displayBuffer
        let rows = terminal.rows
        let cols = terminal.cols
        let yDisp = buffer.yDisp

        var rowSignatures: [Int] = []
        rowSignatures.reserveCapacity(rows)

        for row in 0..<rows {
            rowSignatures.append(Self.signature(for: buffer.lines[yDisp + row], cols: cols))
        }

        return VisibleBufferSnapshot(
            rowSignatures: rowSignatures,
            cursorCol: buffer.x,
            cursorRow: buffer.y,
            topVisibleRow: yDisp,
            cols: cols,
            rows: rows
        )
    }

    public func applyExternalFeedDiff(from snapshot: VisibleBufferSnapshot?) {
        guard let terminal, let renderer else {
            setTerminalNeedsDisplay()
            return
        }
        _ = snapshot
        renderer.markAllDirty(reason: "externalFeedFullRefresh")
        renderer.markSelectionDirty()
        renderer.markCursorDirty()
        setTerminalNeedsDisplay()
    }

    private static func signature(for line: BufferLine, cols: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(cols)
        hasher.combine(line.isWrapped)
        switch line.renderMode {
        case .single:
            hasher.combine(0)
        case .doubleWidth:
            hasher.combine(1)
        case .doubledTop:
            hasher.combine(2)
        case .doubledDown:
            hasher.combine(3)
        }
        hasher.combine(line.images?.count ?? 0)

        for idx in 0..<cols {
            let cell = line[idx]
            hasher.combine(cell.code)
            hasher.combine(cell.width)
            hasher.combine(cell.attribute)
            hasher.combine(cell.hasPayload)
        }

        return hasher.finalize()
    }

    #if os(macOS)
    /// Called when the view is added to or removed from a window
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Update scale factor when window changes (important for retina displays)
        if let _ = window {
            layer?.contentsScale = scale
            updateDrawableMetrics()
            // Reconfigure renderer with correct scale
            if let fontSet = fontSet, cellDimension != .zero {
                computeCellDimension()
                renderer?.update(terminal: terminal, fontSet: fontSet, cellDimension: cellDimension, scale: scale)
                renderer?.clearCache()
                // Resize terminal to fit view bounds
                if bounds.width > 1 && bounds.height > 1 {
                    handleResize(newSize: bounds.size)
                }
            }
            refreshDisplay(clearCache: false, immediately: true)
        }
    }

    /// Called when the view's layout changes (important for auto layout)
    open override func layout() {
        super.layout()
        // Handle resize for auto layout based views
        if bounds.width > 1 && bounds.height > 1 && cellDimension.width > 0 {
            handleResize(newSize: bounds.size)
        }
    }

    /// Called when the view's superview changes
    open override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // Resize when added to a superview with valid bounds
        if superview != nil && bounds.width > 1 && bounds.height > 1 && cellDimension.width > 0 {
            handleResize(newSize: bounds.size)
            refreshDisplay(immediately: true)
        }
    }

    /// Called when the view's frame changes
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Use bounds.size which is in points (not pixels)
        if bounds.width > 1 && bounds.height > 1 {
            handleResize(newSize: bounds.size)
        }
    }

    /// Handle view resize by updating terminal dimensions
    private func handleResize(newSize: NSSize) {
        guard cellDimension.width > 0 && cellDimension.height > 0 else { return }
        guard newSize.width > 1 && newSize.height > 1 else { return }

        updateDrawableMetrics()

        let newCols = max(1, Int(newSize.width / cellDimension.width))
        let newRows = max(1, Int(newSize.height / cellDimension.height))

        if newCols != terminal.cols || newRows != terminal.rows {
            terminal.resize(cols: newCols, rows: newRows)
        }
        setTerminalNeedsDisplay()
    }
    #else
    /// Called when the view's bounds change (iOS)
    open override func layoutSubviews() {
        super.layoutSubviews()
        handleResize(newSize: bounds.size)
        if window != nil {
            refreshDisplay()
        }
    }

    /// Handle view resize by updating terminal dimensions
    private func handleResize(newSize: CGSize) {
        guard cellDimension.width > 0 && cellDimension.height > 0 else { return }

        updateDrawableMetrics()

        let newCols = max(1, Int(newSize.width / cellDimension.width))
        let newRows = max(1, Int(newSize.height / cellDimension.height))

        if newCols != terminal.cols || newRows != terminal.rows {
            terminal.resize(cols: newCols, rows: newRows)
        }
        setTerminalNeedsDisplay()
    }
    #endif

    /// Resize the terminal
    public func resize(cols: Int, rows: Int) {
        terminal.resize(cols: cols, rows: rows)
    }

    // MARK: - Input

    /// Sends raw bytes to the terminal host.
    public func send(data: ArraySlice<UInt8>) {
        terminalDelegate?.send(source: self, data: data)
    }

    /// Sends an array of bytes to the terminal host.
    public func send(_ bytes: [UInt8]) {
        send(data: bytes[...])
    }

    /// Send text to the terminal
    public func send(text: String) {
        if let data = text.data(using: .utf8) {
            send([UInt8](data))
        }
    }
}

// MARK: - CTFont Extension for Glyph

extension CTFont {
    /// Get a glyph with a given name
    public func glyph(withName name: String) -> CGGlyph {
        var glyph: CGGlyph = 0
        let nameCF = name as CFString
        glyph = CTFontGetGlyphWithName(self, nameCF)
        return glyph
    }
}
#endif
