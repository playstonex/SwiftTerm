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

    // MARK: - NSTextInputClient

    open func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = string as? String else { return }
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
        // Handle IME
    }

    open func unmarkText() {
        // Handle IME
    }

    open func selectedRange() -> NSRange {
        return NSRange(location: NSNotFound, length: 0)
    }

    open func markedRange() -> NSRange {
        return NSRange(location: NSNotFound, length: 0)
    }

    open func hasMarkedText() -> Bool {
        return false
    }

    open func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }

    open func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return []
    }

    open func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let terminal = terminal else { return .zero }
        let buffer = terminal.buffer
        let x = buffer.x
        let y = buffer.y

        let cellRect = NSRect(
            x: CGFloat(x) * cellDimension.width,
            y: frame.height - CGFloat(y + 1) * cellDimension.height,
            width: cellDimension.width,
            height: cellDimension.height
        )

        return convert(cellRect, to: nil)
    }

    open func characterIndex(for point: NSPoint) -> Int {
        guard let terminal = terminal else { return 0 }
        let col = Int(point.x / cellDimension.width)
        let row = Int((frame.height - point.y) / cellDimension.height)

        return row * terminal.cols + col
    }

    // MARK: - Keyboard handling

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

        // Handle option as meta
        if optionAsMetaKey && modifierFlags.contains(.option) {
            // Send ESC + key
            let chars = event.charactersIgnoringModifiers ?? ""
            if let char = chars.first {
                send(text: "\u{1b}\(char)")
            }
            return
        }

        // Handle special keys
        handleKeyCode(event.keyCode, modifierFlags: modifierFlags, event: event)
    }

    private func handleKeyCode(_ keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, event: NSEvent) {
        guard terminal != nil else { return }

        var sequence: String = ""

        switch Int(keyCode) {
        case kVK_Return:
            sequence = "\r"
        case kVK_Tab:
            sequence = "\t"
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
            if let chars = event.characters {
                insertText(chars, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            return
        }

        send(text: sequence)
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

    /// Whether a mouse-reporting drag is in progress
    private var mouseTrackingActive: Bool = false

    override open func mouseDown(with event: NSEvent) {
        // Make this view the first responder when clicked
        window?.makeFirstResponder(self)

        guard let terminal = terminal else { return }

        let point = convert(event.locationInWindow, from: nil)
        let col = Int(point.x / cellDimension.width)
        let row = Int((frame.height - point.y) / cellDimension.height)

        // Forward to terminal if mouse reporting is active
        if terminal.mouseMode != .off && allowMouseReporting {
            sendMouseEvent(button: event.buttonNumber, col: col, row: row, pressed: true, modifierFlags: event.modifierFlags)
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

        let point = convert(event.locationInWindow, from: nil)
        let col = Int(point.x / cellDimension.width)
        let row = Int((frame.height - point.y) / cellDimension.height)

        if terminal.mouseMode != .off && allowMouseReporting && mouseTrackingActive {
            sendMouseEvent(button: event.buttonNumber, col: col, row: row, pressed: true, modifierFlags: event.modifierFlags, motion: true)
        } else {
            guard let hit = clampedGridPosition(for: event) else { return }
            if selection?.active == true {
                selection?.dragExtend(bufferPosition: hit)
            } else {
                selection?.setSoftStart(bufferPosition: hit)
                selection?.startSelection()
            }
        }

        setTerminalNeedsDisplay()
    }

    override open func mouseUp(with event: NSEvent) {
        if let terminal = terminal, terminal.mouseMode != .off && allowMouseReporting && mouseTrackingActive {
            let point = convert(event.locationInWindow, from: nil)
            let col = Int(point.x / cellDimension.width)
            let row = Int((frame.height - point.y) / cellDimension.height)
            sendMouseEvent(button: event.buttonNumber, col: col, row: row, pressed: false, modifierFlags: event.modifierFlags)
            mouseTrackingActive = false
        }

        setTerminalNeedsDisplay()
    }

    override open func scrollWheel(with event: NSEvent) {
        guard let terminal = terminal else { return }

        let rawDelta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / max(cellDimension.height, 1)
            : event.scrollingDeltaY
        let delta = Int(rawDelta.rounded(.toNearestOrAwayFromZero))
        if delta != 0 {
            let buffer = terminal.buffer
            let newYDisp = max(0, min(buffer.yDisp - delta, buffer.lines.count - terminal.rows))
            if newYDisp != buffer.yDisp {
                terminal.buffer.yDisp = newYDisp
                setTerminalNeedsDisplay()
            }
        }
    }

    private func sendMouseEvent(button: Int, col: Int, row: Int, pressed: Bool, modifierFlags: NSEvent.ModifierFlags, motion: Bool = false) {
        guard terminal != nil else { return }

        var buttonCode: UInt8 = 0
        if pressed {
            buttonCode = UInt8(button)
        }
        if motion {
            buttonCode += 32
        }

        var modifierCode: UInt8 = 0
        if modifierFlags.contains(.shift) { modifierCode += 1 }
        if modifierFlags.contains(.option) || modifierFlags.contains(.control) { modifierCode += 4 }

        let sequence = "\u{1b}[<\(buttonCode);\(col + 1);\(row + 1)\(pressed ? "M" : "m")"
        send(text: sequence)
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
        if let terminal = terminal, terminal.bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteStart[0...])
        }
        send(text: text)
        if let terminal = terminal, terminal.bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteEnd[0...])
        }
    }
}
#endif
