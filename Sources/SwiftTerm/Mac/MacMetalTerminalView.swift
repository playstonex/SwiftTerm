//
//  MacMetalTerminalView.swift
//  SwiftTerm
//
//  macOS-specific Metal terminal view.
//

#if os(macOS)
import Foundation
import AppKit
import Metal
import MetalKit
import Carbon.HIToolbox

/// macOS Metal-based terminal view
open class MacMetalTerminalView: MetalTerminalView, NSTextInputClient {
    // MARK: - First Responder

    open override var acceptsFirstResponder: Bool { true }
    open override var canBecomeKeyView: Bool { true }

    // MARK: - Input handling

    /// Whether the option key is treated as meta
    public var optionAsMetaKey: Bool = true

    /// Whether mouse reporting is allowed (when terminal requests mouse mode)
    public var allowMouseReporting: Bool = true

    /// Whether we're in a key repeat
    private var isKeyRepeating: Bool = false

    /// Track the active IME composition so AppKit can manage marked text correctly.
    private var markedText: NSAttributedString?
    private var markedTextSelectionRange = NSRange(location: 0, length: 0)

    // MARK: - NSTextInputClient

    open func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attributedString = string as? NSAttributedString {
            text = attributedString.string
        } else if let plainString = string as? String {
            text = plainString
        } else {
            return
        }

        markedText = nil
        markedTextSelectionRange = NSRange(location: 0, length: 0)
        send(text: text)
    }

    open override func doCommand(by selector: Selector) {
        // Handle various commands
        switch selector {
        case #selector(insertNewline(_:)):
            send(text: "\r")
        case #selector(insertTab(_:)):
            send(text: "\t")
        case #selector(deleteBackward(_:)):
            send(text: "\u{7f}")
        case #selector(deleteForward(_:)):
            send(text: "\u{4}")
        case #selector(moveUp(_:)):
            send(text: "\u{1b}[A")
        case #selector(moveDown(_:)):
            send(text: "\u{1b}[B")
        case #selector(moveLeft(_:)):
            send(text: "\u{1b}[D")
        case #selector(moveRight(_:)):
            send(text: "\u{1b}[C")
        default:
            break
        }
    }

    open func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attributedString = string as? NSAttributedString {
            markedText = attributedString
        } else if let plainString = string as? String {
            markedText = NSAttributedString(string: plainString)
        } else {
            markedText = nil
        }
        markedTextSelectionRange = selectedRange
    }

    open func unmarkText() {
        markedText = nil
        markedTextSelectionRange = NSRange(location: 0, length: 0)
    }

    open func selectedRange() -> NSRange {
        guard hasMarkedText() else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return markedTextSelectionRange
    }

    open func markedRange() -> NSRange {
        guard let markedText else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedText.length)
    }

    open func hasMarkedText() -> Bool {
        (markedText?.length ?? 0) > 0
    }

    open func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let markedText else { return nil }
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: markedText.length))
        guard safeRange.length > 0 else { return nil }
        actualRange?.pointee = safeRange
        return markedText.attributedSubstring(from: safeRange)
    }

    open func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.foregroundColor, .backgroundColor, .underlineStyle]
    }

    open func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let terminal = terminal else { return .zero }
        actualRange?.pointee = hasMarkedText() ? markedRange() : range
        let buffer = terminal.buffer
        let x = buffer.x
        let y = buffer.y

        let cellRect = NSRect(
            x: CGFloat(x) * cellDimension.width,
            y: frame.height - CGFloat(y + 1) * cellDimension.height,
            width: cellDimension.width,
            height: cellDimension.height
        )

        let windowRect = convert(cellRect, to: nil)
        return window?.convertToScreen(windowRect) ?? windowRect
    }

    open func characterIndex(for point: NSPoint) -> Int {
        guard let terminal = terminal, cellDimension.width > 0, cellDimension.height > 0 else { return NSNotFound }
        let col = Int(point.x / cellDimension.width)
        let row = Int((frame.height - point.y) / cellDimension.height)

        return row * terminal.cols + col
    }

    // MARK: - Keyboard handling

    /// Intercept key equivalents so Cmd+C / Cmd+V / Cmd+A are handled by the
    /// terminal view instead of being consumed by the SwiftUI Edit menu.
    override open func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return super.performKeyEquivalent(with: event) }

        switch event.charactersIgnoringModifiers {
        case "c":
            copySelection()
            return true
        case "v":
            pasteFromClipboard()
            return true
        case "a":
            selection?.selectAll()
            setTerminalNeedsDisplay()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override open func keyDown(with event: NSEvent) {
        let modifierFlags = event.modifierFlags

        // Handle Cmd+C copy
        if modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copySelection()
            return
        }

        // Handle Cmd+V paste
        if modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            pasteFromClipboard()
            return
        }

        // Handle Cmd+A select all
        if modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "a" {
            selection?.selectAll()
            setTerminalNeedsDisplay()
            return
        }

        // Clear selection for all other key events
        selection?.active = false

        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }

        // Handle option as meta
        if optionAsMetaKey,
           modifierFlags.contains(.option),
           !modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           let char = chars.first
        {
            // Send ESC + key
            send(text: "\u{1b}\(char)")
            return
        }

        // Handle Control key combinations explicitly.
        // interpretKeyEvents is unreliable for control characters — it may
        // swallow Ctrl+C, Ctrl+\\, etc. or route them to the wrong NSTextInputClient
        // method.  Send the raw control byte directly instead.
        if modifierFlags.contains(.control),
           !modifierFlags.contains(.command),
           !modifierFlags.contains(.option),
           let chars = event.charactersIgnoringModifiers,
           let char = chars.first,
           let byte = applyControlToCharacter(char)
        {
            send([byte])
            return
        }

        if handleSpecialKey(event.keyCode, modifierFlags: modifierFlags) {
            return
        }

        interpretKeyEvents([event])
    }

    /// Map a printable character to its control-code byte (Ctrl+key).
    private func applyControlToCharacter(_ ch: Character) -> UInt8? {
        guard let scalar = ch.asciiValue else { return nil }
        switch ch {
        case "A"..."Z": return scalar &- 0x40   // Ctrl-A = 1 ... Ctrl-Z = 26
        case "a"..."z": return scalar &- 0x60
        case "[":      return 0x1b               // Ctrl-[ = ESC
        case "\\":      return 0x1c
        case "]":      return 0x1d
        case "^", "6": return 0x1e
        case "_":      return 0x1f
        case " ":      return 0
        default:       return nil
        }
    }

    @discardableResult
    private func handleSpecialKey(_ keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard terminal != nil else { return false }

        var sequence: String = ""

        switch Int(keyCode) {
        case kVK_Return:
            sequence = "\r"
        case kVK_Tab:
            sequence = "\t"
        case kVK_Escape:
            sequence = "\u{1b}"
        case kVK_Delete:
            sequence = "\u{7f}"
        case kVK_ForwardDelete:
            sequence = "\u{1b}[3~"
        case kVK_UpArrow:
            sequence = modifierFlags.contains(.shift) ? "\u{1b}[1;2A" : "\u{1b}[A"
        case kVK_DownArrow:
            sequence = modifierFlags.contains(.shift) ? "\u{1b}[1;2B" : "\u{1b}[B"
        case kVK_LeftArrow:
            sequence = modifierFlags.contains(.shift) ? "\u{1b}[1;2D" : "\u{1b}[D"
        case kVK_RightArrow:
            sequence = modifierFlags.contains(.shift) ? "\u{1b}[1;2C" : "\u{1b}[C"
        case kVK_Home:
            sequence = "\u{1b}[H"
        case kVK_End:
            sequence = "\u{1b}[F"
        case kVK_PageUp:
            sequence = "\u{1b}[5~"
        case kVK_PageDown:
            sequence = "\u{1b}[6~"
        case kVK_F1:
            sequence = "\u{1b}OP"
        case kVK_F2:
            sequence = "\u{1b}OQ"
        case kVK_F3:
            sequence = "\u{1b}OR"
        case kVK_F4:
            sequence = "\u{1b}OS"
        case kVK_F5:
            sequence = "\u{1b}[15~"
        case kVK_F6:
            sequence = "\u{1b}[17~"
        case kVK_F7:
            sequence = "\u{1b}[18~"
        case kVK_F8:
            sequence = "\u{1b}[19~"
        case kVK_F9:
            sequence = "\u{1b}[20~"
        case kVK_F10:
            sequence = "\u{1b}[21~"
        case kVK_F11:
            sequence = "\u{1b}[23~"
        case kVK_F12:
            sequence = "\u{1b}[24~"
        default:
            return false
        }

        send(text: sequence)
        return true
    }

    // MARK: - Copy/Paste

    @objc
    open func copy(_ sender: Any?) {
        copySelection()
    }

    @objc
    open func paste(_ sender: Any?) {
        pasteFromClipboard()
    }

    public override func selectAll(_ sender: Any?) {
        selection?.selectAll()
        setTerminalNeedsDisplay()
    }

    // MARK: - Mouse handling

    private func clampedGridPosition(for event: NSEvent) -> Position? {
        guard let terminal = terminal else { return nil }

        let point = convert(event.locationInWindow, from: nil)
        let col = Int(point.x / cellDimension.width)
        let row = Int((frame.height - point.y) / cellDimension.height)

        let clampedCol = max(0, min(col, terminal.cols - 1))
        let screenRow = max(0, min(row, terminal.rows - 1))
        let bufferRow = min(
            max(0, screenRow + terminal.displayBuffer.yDisp),
            max(0, terminal.displayBuffer.lines.count - 1)
        )

        return Position(col: clampedCol, row: bufferRow)
    }

    private func clampedScreenGridPosition(for event: NSEvent) -> Position? {
        guard let terminal = terminal else { return nil }

        let point = convert(event.locationInWindow, from: nil)
        let col = Int(point.x / cellDimension.width)
        let row = Int((frame.height - point.y) / cellDimension.height)

        return Position(
            col: max(0, min(col, terminal.cols - 1)),
            row: max(0, min(row, terminal.rows - 1))
        )
    }

    /// Whether a mouse-reporting drag is in progress
    private var mouseTrackingActive: Bool = false
    private var scrollWheelAccumulator: CGFloat = 0

    /// Auto-scroll state for drag selection beyond visible area
    private var autoScrollDelta = 0
    private var autoScrollTimer: Timer?

    /// Converts mouse event to buffer position without clamping to visible rows.
    /// Used during selection drag so selection can extend beyond the visible area.
    private func unclampedGridPosition(for event: NSEvent) -> Position? {
        guard let terminal = terminal else { return nil }

        let point = convert(event.locationInWindow, from: nil)
        let col = Int(point.x / cellDimension.width)
        let row = Int((frame.height - point.y) / cellDimension.height)

        let clampedCol = max(0, min(col, terminal.cols - 1))
        let screenRow = row  // unclamped — can be negative or beyond rows
        let bufferRow = min(
            max(0, screenRow + terminal.displayBuffer.yDisp),
            max(0, terminal.displayBuffer.lines.count - 1)
        )

        return Position(col: clampedCol, row: bufferRow)
    }

    private func calcScrollingVelocity(delta: Int) -> Int {
        if delta > 9 {
            return max(terminal.rows, 20)
        }
        if delta > 5 {
            return 10
        }
        if delta > 1 {
            return 3
        }
        return 1
    }

    private func scrollingTimerElapsed(_ source: Timer) {
        guard let terminal = terminal else { return }
        if autoScrollDelta == 0 { return }

        let displayBuffer = terminal.displayBuffer
        let maxYDisp = max(0, displayBuffer.lines.count - displayBuffer.rows)
        let newYDisp = max(0, min(displayBuffer.yDisp + autoScrollDelta, maxYDisp))

        if newYDisp != displayBuffer.yDisp {
            terminal.userScrolling = newYDisp != maxYDisp
            terminal.setViewYDisp(newYDisp)
            renderer?.markAllDirty(reason: "autoScroll")
            terminalDelegate?.scrolled(source: self, position: Double(newYDisp) / Double(max(1, maxYDisp)))
            setTerminalNeedsDisplay()

            // Extend selection to the new edge row
            if let selection = selection, selection.active {
                let edgeRow = autoScrollDelta > 0
                    ? newYDisp + displayBuffer.rows - 1
                    : newYDisp
                selection.dragExtend(bufferPosition: Position(col: terminal.cols - 1, row: min(edgeRow, max(0, displayBuffer.lines.count - 1))))
            }
        }
    }

    private func startAutoScrollTimer() {
        guard autoScrollTimer == nil else { return }
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            self?.scrollingTimerElapsed(timer)
        }
    }

    private func stopAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollDelta = 0
    }

    private func clampedPixelPosition(for event: NSEvent) -> Position {
        let point = convert(event.locationInWindow, from: nil)
        let x = min(max(point.x, 0), bounds.width)
        let y = min(max(point.y, 0), bounds.height)
        return Position(col: Int(x), row: Int(bounds.height - y))
    }

    override open func mouseDown(with event: NSEvent) {
        // Make this view the first responder when clicked
        window?.makeFirstResponder(self)

        guard let terminal = terminal else { return }

        // Holding Option overrides mouse reporting so the user can select/copy text
        // in applications like tmux or vim that capture the mouse.
        let forceSelection = event.modifierFlags.contains(.option)

        // Forward to terminal if mouse reporting is active
        if terminal.mouseMode != .off && allowMouseReporting && !forceSelection {
            guard let hit = clampedScreenGridPosition(for: event) else { return }
            sendMouseEvent(button: event.buttonNumber, col: hit.col, row: hit.row, pressed: true, event: event)
            mouseTrackingActive = true
        } else {
            // Text selection
            guard let hit = clampedGridPosition(for: event) else { return }

            switch event.clickCount {
            case 1:
                selection?.active = false
                if event.modifierFlags.contains(.shift) {
                    selection?.shiftExtend(bufferPosition: hit)
                } else {
                    selection?.setSoftStart(bufferPosition: hit)
                }
            case 2:
                selection?.selectWordOrExpression(at: hit, in: terminal.displayBuffer)
            default:
                selection?.select(row: hit.row)
            }
        }

        setTerminalNeedsDisplay()
    }

    override open func mouseDragged(with event: NSEvent) {
        guard let terminal = terminal else { return }
        let displayBuffer = terminal.displayBuffer

        // Holding Option overrides mouse reporting for text selection
        let forceSelection = event.modifierFlags.contains(.option)

        if terminal.mouseMode != .off && allowMouseReporting && mouseTrackingActive && !forceSelection {
            guard let hit = clampedScreenGridPosition(for: event) else { return }
            sendMouseEvent(button: event.buttonNumber, col: hit.col, row: hit.row, pressed: true, event: event, motion: true)
        } else {
            // Use unclamped position so selection can extend beyond visible area
            guard let hit = unclampedGridPosition(for: event) else { return }
            if selection?.active == true {
                selection?.dragExtend(bufferPosition: hit)
            } else {
                selection?.setSoftStart(bufferPosition: hit)
                selection?.startSelection()
            }

            // Auto-scroll when mouse is beyond visible area
            let point = convert(event.locationInWindow, from: nil)
            let screenRow = Int((frame.height - point.y) / cellDimension.height)
            autoScrollDelta = 0
            if selection?.active == true {
                if screenRow < 0 {
                    autoScrollDelta = calcScrollingVelocity(delta: screenRow * -1) * -1
                } else if screenRow >= displayBuffer.rows {
                    autoScrollDelta = calcScrollingVelocity(delta: screenRow - displayBuffer.rows)
                }
            }

            if autoScrollDelta != 0 {
                startAutoScrollTimer()
            } else {
                stopAutoScrollTimer()
            }
        }

        setTerminalNeedsDisplay()
    }

    override open func mouseUp(with event: NSEvent) {
        stopAutoScrollTimer()

        // Holding Option overrides mouse reporting for text selection
        let forceSelection = event.modifierFlags.contains(.option)

        if let terminal = terminal, terminal.mouseMode != .off && allowMouseReporting && mouseTrackingActive && !forceSelection {
            guard let hit = clampedScreenGridPosition(for: event) else { return }
            sendMouseEvent(button: event.buttonNumber, col: hit.col, row: hit.row, pressed: false, event: event)
            mouseTrackingActive = false
        }

        // Auto-copy selected text to clipboard
        if let selection = selection, selection.active {
            let text = selection.getSelectedText()
            if !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                onTextSelected?(text)
            }
        }

        setTerminalNeedsDisplay()
    }

    override open func scrollWheel(with event: NSEvent) {
        guard let terminal = terminal else { return }
        let steps = scrollingSteps(for: event)
        guard steps != 0 else { return }

        if terminal.mouseMode != .off && allowMouseReporting {
            guard let hit = clampedScreenGridPosition(for: event) else { return }
            let button = steps > 0 ? 4 : 5
            for _ in 0..<abs(steps) {
                sendMouseEvent(button: button, col: hit.col, row: hit.row, pressed: true, event: event)
            }
            return
        }

        let displayBuffer = terminal.displayBuffer
        let maxYDisp = max(0, displayBuffer.lines.count - displayBuffer.rows)
        let newYDisp = max(0, min(displayBuffer.yDisp - steps, maxYDisp))
        if newYDisp != displayBuffer.yDisp {
            terminal.userScrolling = newYDisp != maxYDisp
            terminal.setViewYDisp(newYDisp)
            renderer?.markAllDirty(reason: "wheelScroll")
            terminalDelegate?.scrolled(source: self, position: Double(newYDisp) / Double(max(1, maxYDisp)))
            setTerminalNeedsDisplay()
        }
    }

    private func scrollingSteps(for event: NSEvent) -> Int {
        let rawDelta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / max(cellDimension.height, 1)
            : event.deltaY
        scrollWheelAccumulator += rawDelta
        let steps = Int(scrollWheelAccumulator.rounded(.towardZero))
        if steps != 0 {
            scrollWheelAccumulator -= CGFloat(steps)
        }
        return steps
    }

    private func sendMouseEvent(button: Int, col: Int, row: Int, pressed: Bool, event: NSEvent, motion: Bool = false) {
        guard let terminal else { return }

        let flags = terminal.encodeButton(
            button: button,
            release: !pressed,
            shift: event.modifierFlags.contains(.shift),
            meta: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )
        let pixels = clampedPixelPosition(for: event)

        if motion {
            terminal.sendMotion(buttonFlags: flags, x: col, y: row, pixelX: pixels.col, pixelY: pixels.row)
        } else {
            terminal.sendEvent(buttonFlags: flags, x: col, y: row, pixelX: pixels.col, pixelY: pixels.row)
        }
    }

    // MARK: - View lifecycle

    override open func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupRenderer()
        if window != nil, bounds.width > 1, bounds.height > 1 {
            refreshDisplay(immediately: true)
        }
    }

    override open func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        handleResize(newSize: newSize)
    }

    override open func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        handleResize(newSize: newSize)
    }

    private func handleResize(newSize: NSSize) {
        guard cellDimension != .zero else { return }
        guard newSize.width > 1, newSize.height > 1 else { return }

        updateDrawableMetrics()

        let newCols = Int(newSize.width / cellDimension.width)
        let newRows = Int(newSize.height / cellDimension.height)

        if let terminal = terminal,
           (newCols != terminal.cols || newRows != terminal.rows) {
            selection?.active = false
            terminal.resize(cols: newCols, rows: newRows)
            setTerminalNeedsDisplay()
        }
    }

    // MARK: - Selection

    /// Returns the currently selected text, or empty string if no selection
    public func getSelectedText() -> String {
        guard let selection = selection, selection.active else { return "" }
        return selection.getSelectedText()
    }

    public func copySelection() {
        guard let selection = selection, selection.active else { return }
        let text = selection.getSelectedText()
        if !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    /// Internal paste implementation (avoids name collision with `paste(_ sender:)`)
    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }

        selection?.active = false

        if let terminal = terminal, terminal.bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteStart[0...])
        }
        send(text: text)
        if let terminal = terminal, terminal.bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteEnd[0...])
        }
        // The echoed text arrives asynchronously from the remote shell.
        // Schedule repeated full redraws to ensure it renders correctly.
        for delay in [0.05, 0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.renderer?.markAllDirty(reason: "pasteEcho")
                self?.refreshDisplay(immediately: true)
            }
        }
    }
}
#endif
