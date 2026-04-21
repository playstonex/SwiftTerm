//
//  iOSMetalTerminalView.swift
//  SwiftTerm
//
//  iOS-specific Metal terminal view.
//

#if os(iOS) || os(visionOS)
import Foundation
import UIKit
import Metal
import MetalKit

/// iOS Metal-based terminal view
open class iOSMetalTerminalView: MetalTerminalView, UITextInput, UITextInputTraits, UIGestureRecognizerDelegate {
    // MARK: - UITextInput properties

    public weak var inputDelegate: UITextInputDelegate?

    public var markedTextStyle: [NSAttributedString.Key: Any]?

    public lazy var tokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)

    // MARK: - IME state (linear-offset based, matching iOSTextInput.swift pattern)

    /// Buffer holding the current composing text from the IME.
    private var textInputStorage: String = ""

    /// The range within textInputStorage that is "marked" (composing).
    private var _markedTextRange: IMETextRange?

    /// The current selection within textInputStorage (or cursor position when empty).
    private var _selectedTextRange: IMETextRange = IMETextRange(
        start: IMETextPosition(offset: 0),
        end: IMETextPosition(offset: 0)
    )

    public var returnByteSequence: [UInt8] = [13]

    public var markedTextRange: UITextRange? {
        return _markedTextRange
    }

    public var selectedTextRange: UITextRange? {
        get { return _selectedTextRange }
        set {
            guard let newValue, let range = coerceTextRange(newValue) else { return }
            let isSameRange = range.startOffset == _selectedTextRange.startOffset
                && range.endOffset == _selectedTextRange.endOffset
            guard !isSameRange else { return }
            inputDelegate?.selectionWillChange(self)
            _selectedTextRange = range
            inputDelegate?.selectionDidChange(self)
        }
    }

    public var autocapitalizationType: UITextAutocapitalizationType = .none
    public var autocorrectionType: UITextAutocorrectionType = .no
    public var spellCheckingType: UITextSpellCheckingType = .no
    public var smartQuotesType: UITextSmartQuotesType = .no
    public var smartDashesType: UITextSmartDashesType = .no
    public var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    public var keyboardType: UIKeyboardType = .default
    public var keyboardAppearance: UIKeyboardAppearance = .default
    public var returnKeyType: UIReturnKeyType = .default
    public var enablesReturnKeyAutomatically: Bool = false
    public var isSecureTextEntry: Bool = false
    public var textContentType: UITextContentType! = .none

    // MARK: - Input handling

    /// Whether the terminal should respond to mouse events
    public var allowMouseReporting: Bool = true

    /// Touch tracking state
    private var touchStartPosition: CGPoint = .zero
    private var isLongPress: Bool = false

    /// Whether option should be sent as meta for hardware keyboard input.
    public var optionAsMetaKey: Bool = true

    /// Whether backspace should send Ctrl+H instead of DEL.
    public var backspaceSendsControlH: Bool = false

    private var editMenuInteraction: Any?

    private var pendingKittyKeyEvent: PendingKittyKeyEvent?

    private lazy var composingLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont(name: "Menlo", size: 14) ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0, alpha: 0.7)
        label.layer.cornerRadius = 3
        label.clipsToBounds = true
        label.isHidden = true
        label.sizeToFit()
        addSubview(label)
        return label
    }()

    /// Selection auto-scroll task for dragging beyond screen edges
    private var selectionScrollTask: Task<(), Never>?

    /// Drag handles for adjusting selection range
    private var startHandle: SelectionHandleView?
    private var endHandle: SelectionHandleView?

    // MARK: - Initialization

    override public init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        commonInit()
    }

    public required init(coder: NSCoder) {
        super.init(frame: .zero, device: nil)
        commonInit()
    }

    private func commonInit() {
        // Set up touch handling
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = false

        // Set up gesture recognizers
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.delegate = self
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)

        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delegate = self
        doubleTapGesture.cancelsTouchesInView = false
        addGestureRecognizer(doubleTapGesture)

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.delegate = self
        longPressGesture.cancelsTouchesInView = false
        addGestureRecognizer(longPressGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = false
        panGesture.delaysTouchesBegan = false
        panGesture.delaysTouchesEnded = false
        addGestureRecognizer(panGesture)

        tapGesture.require(toFail: panGesture)
        doubleTapGesture.require(toFail: panGesture)

        // Note: Do NOT call becomeFirstResponder here - the view is not yet in a window.
        // The view will become first responder when tapped or when explicitly requested.
    }

    // MARK: - Keyboard handling

    override open var canBecomeFirstResponder: Bool {
        return true
    }

    override open var canResignFirstResponder: Bool {
        return true
    }

    override open func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        // UIKit handles keyboard notifications automatically for UITextInput views.
        // Do NOT post keyboardWillShowNotification manually — it triggers a feedback
        // loop with the SwiftUI parent's handleKeyboardTransition, causing delayed
        // resizes that can steal first responder and break key delivery.
        return result
    }

    override open func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            // Hide keyboard
            NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        }
        return result
    }

    // MARK: - UIKeyInput

    open var hasText: Bool {
        return true
    }

    open func insertText(_ text: String) {
        if selection?.active == true {
            selection?.active = false
            removeSelectionHandles()
            setTerminalNeedsDisplay()
        }
        let rangeToReplace = _markedTextRange ?? _selectedTextRange
        beginTextInputEdit()
        let insertionOffset = rangeToReplace.startOffset
        textInputStorage.replaceSubrange(rangeToReplace.fullRange(in: textInputStorage), with: text)
        _markedTextRange = nil
        hideComposingOverlay()
        let insertedPosition = IMETextPosition(offset: insertionOffset + utf16Length(of: text))
        _selectedTextRange = IMETextRange(start: insertedPosition, end: insertedPosition)
        endTextInputEdit()
        sendCommittedText(text)
    }

    open func deleteBackward() {
        let rangeToDelete = _markedTextRange ?? _selectedTextRange
        var newCursorOffset = rangeToDelete.startOffset
        if rangeToDelete.isEmpty {
            guard newCursorOffset > 0 else {
                send([backspaceSendsControlH ? 8 : 0x7f])
                return
            }

            beginTextInputEdit()
            let deleteRange = IMETextRange(
                start: IMETextPosition(offset: newCursorOffset - 1),
                end: IMETextPosition(offset: newCursorOffset)
            )
            textInputStorage.removeSubrange(deleteRange.fullRange(in: textInputStorage))
            _markedTextRange = nil
            newCursorOffset -= 1
            let cursor = IMETextPosition(offset: newCursorOffset)
            _selectedTextRange = IMETextRange(start: cursor, end: cursor)
            endTextInputEdit()
            send([backspaceSendsControlH ? 8 : 0x7f])
            return
        }

        beginTextInputEdit()
        let oldText = String(textInputStorage[rangeToDelete.fullRange(in: textInputStorage)])
        textInputStorage.removeSubrange(rangeToDelete.fullRange(in: textInputStorage))
        _markedTextRange = nil
        let cursor = IMETextPosition(offset: newCursorOffset)
        _selectedTextRange = IMETextRange(start: cursor, end: cursor)
        endTextInputEdit()

        let hasPendingHardwareKey = pendingKittyKeyEvent != nil
        if terminal.keyboardEnhancementFlags.isEmpty || !hasPendingHardwareKey {
            for _ in oldText {
                send([backspaceSendsControlH ? 8 : 0x7f])
            }
            return
        }
        for _ in oldText {
            _ = sendKittyEvent(
                KittyKeyEvent(
                    key: .functional(.backspace),
                    modifiers: [],
                    eventType: .press,
                    text: nil,
                    shiftedKey: nil,
                    baseLayoutKey: nil,
                    composing: false
                )
            )
        }
    }

    private func beginTextInputEdit() {
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.textWillChange(self)
    }

    private func endTextInputEdit() {
        inputDelegate?.textDidChange(self)
        inputDelegate?.selectionDidChange(self)
    }

    private func utf16Length(of string: String) -> Int {
        (string as NSString).length
    }

    private func clampOffset(_ offset: Int) -> Int {
        max(0, min(offset, utf16Length(of: textInputStorage)))
    }

    private func coerceTextPosition(_ position: UITextPosition) -> IMETextPosition? {
        guard let position = position as? IMETextPosition else { return nil }
        let clampedOffset = clampOffset(position.offset)
        return clampedOffset == position.offset ? position : IMETextPosition(offset: clampedOffset)
    }

    private func coerceTextRange(_ range: UITextRange) -> IMETextRange? {
        if let range = range as? IMETextRange {
            let start = clampOffset(range.startOffset)
            let end = clampOffset(range.endOffset)
            if start == range.startOffset, end == range.endOffset {
                return range
            }
            return IMETextRange(start: IMETextPosition(offset: start), end: IMETextPosition(offset: end))
        }

        guard let start = coerceTextPosition(range.start),
              let end = coerceTextPosition(range.end) else {
            return nil
        }
        return IMETextRange(start: start, end: end)
    }

    private func cursorRect() -> CGRect {
        guard let terminal = terminal else { return .zero }
        return CGRect(
            x: CGFloat(terminal.buffer.x) * cellDimension.width,
            y: CGFloat(terminal.buffer.y) * cellDimension.height,
            width: max(2, cellDimension.width),
            height: cellDimension.height
        )
    }

    private func sendCommittedText(_ text: String) {
        let hasPendingHardwareKey = pendingKittyKeyEvent != nil
        if !terminal.keyboardEnhancementFlags.isEmpty && hasPendingHardwareKey {
            sendKittyTextInput(text)
            return
        }
        if text == "\n" {
            send(returnByteSequence)
            return
        }
        send(text: text)
    }

    private func showComposingOverlay(_ text: String) {
        composingLabel.text = text
        composingLabel.sizeToFit()
        composingLabel.frame.size.width += 6
        composingLabel.frame.size.height += 4
        composingLabel.font = UIFont(name: "Menlo", size: min(cellDimension.height - 2, 18)) ?? UIFont.monospacedSystemFont(ofSize: min(cellDimension.height - 2, 18), weight: .regular)

        let cursor = cursorRect()
        var originX = cursor.origin.x
        let originY = cursor.origin.y - composingLabel.frame.height - 2
        if originX + composingLabel.frame.width > bounds.width {
            originX = bounds.width - composingLabel.frame.width - 4
        }
        composingLabel.frame.origin = CGPoint(x: max(0, originX), y: max(0, originY))
        composingLabel.isHidden = false
    }

    private func hideComposingOverlay() {
        composingLabel.isHidden = true
    }

    // MARK: - Hardware Keyboard Support

    /// Key commands for hardware keyboard input - return nil to use UIKeyInput for text
    override open var keyCommands: [UIKeyCommand]? {
        return nil
    }

    /// Handle hardware keyboard key press events
    /// Note: The parent view (SwiftTerminalView) handles pressesBegan for special keys
    /// This is kept for direct use when this view is used standalone
    override open func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let kittyFlags = terminal.keyboardEnhancementFlags
        var handledSpecialKey = false

        if !kittyFlags.isEmpty {
            pendingKittyKeyEvent = nil
        }

        for press in presses {
            guard let key = press.key else { continue }

            if !kittyFlags.isEmpty {
                if key.modifierFlags.contains([.alternate, .command]),
                   key.charactersIgnoringModifiers == "o" {
                    optionAsMetaKey.toggle()
                    handledSpecialKey = true
                    continue
                }

                if let functionKey = kittyFunctionalKey(for: key.keyCode) {
                    if !kittyFlags.contains(.reportAllKeys), isKittyModifierKey(functionKey) {
                        continue
                    }

                    let includeOption = optionAsMetaKey || functionKey == .leftAlt || functionKey == .rightAlt
                    let modifiers = kittyModifiers(from: key, includeOption: includeOption)
                    let text = kittyTextForFunctionalKey(functionKey, uiKey: key)
                    handledSpecialKey = sendKittyEvent(
                        KittyKeyEvent(
                            key: .functional(functionKey),
                            modifiers: modifiers,
                            eventType: .press,
                            text: text,
                            shiftedKey: nil,
                            baseLayoutKey: nil,
                            composing: false
                        )
                    ) || handledSpecialKey
                    continue
                }

                if key.modifierFlags.contains(.control) || (optionAsMetaKey && key.modifierFlags.contains(.alternate)) {
                    handledSpecialKey = sendKittyModifiedTextEvent(for: key) || handledSpecialKey
                    continue
                }

                pendingKittyKeyEvent = PendingKittyKeyEvent(key: key, eventType: .press)
                continue
            }

            handledSpecialKey = sendLegacyKeyPress(for: key) || handledSpecialKey
        }

        if !handledSpecialKey {
            super.pressesBegan(presses, with: event)
        }
    }

    /// Handle hardware keyboard key release events
    override open func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let kittyFlags = terminal.keyboardEnhancementFlags
        if kittyFlags.contains(.reportEvents) {
            for press in presses {
                guard let key = press.key else { continue }
                let functionKey = kittyFunctionalKey(for: key.keyCode)
                let hasAltOrCtrl = key.modifierFlags.contains(.control) || (optionAsMetaKey && key.modifierFlags.contains(.alternate))

                if let functionKey,
                   !kittyFlags.contains(.reportAllKeys),
                   isKittyModifierKey(functionKey) {
                    continue
                }

                if let functionKey,
                   !kittyFlags.contains(.reportAllKeys),
                   (functionKey == .tab || functionKey == .enter || functionKey == .backspace) {
                    continue
                }

                let shouldHandle = kittyFlags.contains(.reportAllKeys) || hasAltOrCtrl || functionKey != nil
                if shouldHandle, let kittyEvent = kittyKeyEvent(from: key, eventType: .release, text: nil) {
                    _ = sendKittyEvent(kittyEvent)
                }
            }
        }
        super.pressesEnded(presses, with: event)
    }

    private func sendLegacyKeyPress(for key: UIKey) -> Bool {
        switch key.keyCode {
        case .keyboardUpArrow:
            send(data: (terminal.applicationCursor ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal)[...])
            return true
        case .keyboardDownArrow:
            send(data: (terminal.applicationCursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal)[...])
            return true
        case .keyboardLeftArrow:
            if key.modifierFlags.contains(.alternate) {
                send(data: EscapeSequences.emacsBack[...])
            } else if key.modifierFlags.contains(.control) {
                send(data: EscapeSequences.controlLeft[...])
            } else {
                send(data: (terminal.applicationCursor ? EscapeSequences.moveLeftApp : EscapeSequences.moveLeftNormal)[...])
            }
            return true
        case .keyboardRightArrow:
            if key.modifierFlags.contains(.alternate) {
                send(data: EscapeSequences.emacsForward[...])
            } else if key.modifierFlags.contains(.control) {
                send(data: EscapeSequences.controlRight[...])
            } else {
                send(data: (terminal.applicationCursor ? EscapeSequences.moveRightApp : EscapeSequences.moveRightNormal)[...])
            }
            return true
        case .keyboardHome:
            send(data: (terminal.applicationCursor ? EscapeSequences.moveHomeApp : EscapeSequences.moveHomeNormal)[...])
            return true
        case .keyboardEnd:
            send(data: (terminal.applicationCursor ? EscapeSequences.moveEndApp : EscapeSequences.moveEndNormal)[...])
            return true
        case .keyboardPageUp:
            send(data: EscapeSequences.cmdPageUp[...])
            return true
        case .keyboardPageDown:
            send(data: EscapeSequences.cmdPageDown[...])
            return true
        case .keyboardTab:
            if key.modifierFlags.contains(.shift) {
                send(data: EscapeSequences.cmdBackTab[...])
            } else {
                send([9])
            }
            return true
        case .keyboardDeleteForward:
            send(data: EscapeSequences.cmdDelKey[...])
            return true
        case .keyboardEscape:
            send([0x1b])
            return true
        case .keyboardF1:
            send(data: EscapeSequences.cmdF[0][...])
            return true
        case .keyboardF2:
            send(data: EscapeSequences.cmdF[1][...])
            return true
        case .keyboardF3:
            send(data: EscapeSequences.cmdF[2][...])
            return true
        case .keyboardF4:
            send(data: EscapeSequences.cmdF[3][...])
            return true
        case .keyboardF5:
            send(data: EscapeSequences.cmdF[4][...])
            return true
        case .keyboardF6:
            send(data: EscapeSequences.cmdF[5][...])
            return true
        case .keyboardF7:
            send(data: EscapeSequences.cmdF[6][...])
            return true
        case .keyboardF8:
            send(data: EscapeSequences.cmdF[7][...])
            return true
        case .keyboardF9:
            send(data: EscapeSequences.cmdF[8][...])
            return true
        case .keyboardF10:
            send(data: EscapeSequences.cmdF[9][...])
            return true
        case .keyboardF11:
            send(data: EscapeSequences.cmdF[10][...])
            return true
        case .keyboardF12:
            send(data: EscapeSequences.cmdF[11][...])
            return true
        default:
            if key.modifierFlags.contains([.alternate, .command]),
               key.charactersIgnoringModifiers == "o" {
                optionAsMetaKey.toggle()
                return true
            }
            if key.modifierFlags.contains(.alternate) && optionAsMetaKey {
                send(text: "\u{1b}\(key.charactersIgnoringModifiers)")
                return true
            }
            if key.modifierFlags.contains(.control) {
                let controlBytes = applyControlToEventCharacters(key.charactersIgnoringModifiers)
                if !controlBytes.isEmpty {
                    send(controlBytes)
                    return true
                }
            }
            return false
        }
    }

    private func applyControlToEventCharacters(_ value: String) -> [UInt8] {
        let bytes = [UInt8](value.utf8)
        guard bytes.count == 1 else {
            return []
        }
        let scalar = UnicodeScalar(bytes[0])
        let character = Character(scalar)
        switch character {
        case "A"..."Z":
            return [character.asciiValue! - 0x40]
        case "a"..."z":
            return [character.asciiValue! - 0x60]
        case "\\":
            return [0x1c]
        case "_":
            return [0x1f]
        case "]":
            return [0x1d]
        case "[":
            return [0x1b]
        case "^", "6":
            return [0x1e]
        case " ":
            return [0]
        default:
            return []
        }
    }

    private func kittyEncoder() -> KittyKeyboardEncoder {
        KittyKeyboardEncoder(
            flags: terminal.keyboardEnhancementFlags,
            applicationCursor: terminal.applicationCursor,
            backspaceSendsControlH: backspaceSendsControlH
        )
    }

    private func kittyModifiers(from key: UIKey, includeOption: Bool) -> KittyKeyboardModifiers {
        var modifiers: KittyKeyboardModifiers = []
        if key.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if key.modifierFlags.contains(.control) { modifiers.insert(.ctrl) }
        if includeOption, key.modifierFlags.contains(.alternate) { modifiers.insert(.alt) }
        if key.modifierFlags.contains(.command) { modifiers.insert(.super) }
        if key.modifierFlags.contains(.alphaShift) { modifiers.insert(.capsLock) }
        return modifiers
    }

    private func kittyFunctionalKey(for keyCode: UIKeyboardHIDUsage) -> KittyFunctionalKey? {
        switch keyCode {
        case .keyboardCapsLock, .keyboardLockingCapsLock:
            return .capsLock
        case .keyboardLockingNumLock:
            return .numLock
        case .keyboardScrollLock, .keyboardLockingScrollLock:
            return .scrollLock
        case .keyboardLeftShift:
            return .leftShift
        case .keyboardRightShift:
            return .rightShift
        case .keyboardLeftControl:
            return .leftControl
        case .keyboardRightControl:
            return .rightControl
        case .keyboardLeftAlt:
            return .leftAlt
        case .keyboardRightAlt:
            return .rightAlt
        case .keyboardLeftGUI:
            return .leftSuper
        case .keyboardRightGUI:
            return .rightSuper
        case .keyboardUpArrow:
            return .up
        case .keyboardDownArrow:
            return .down
        case .keyboardLeftArrow:
            return .left
        case .keyboardRightArrow:
            return .right
        case .keyboardPageUp:
            return .pageUp
        case .keyboardPageDown:
            return .pageDown
        case .keyboardHome:
            return .home
        case .keyboardEnd:
            return .end
        case .keyboardInsert:
            return .insert
        case .keyboardDeleteForward:
            return .delete
        case .keyboardEscape:
            return .escape
        case .keyboardTab:
            return .tab
        case .keyboardF1:
            return .f1
        case .keyboardF2:
            return .f2
        case .keyboardF3:
            return .f3
        case .keyboardF4:
            return .f4
        case .keyboardF5:
            return .f5
        case .keyboardF6:
            return .f6
        case .keyboardF7:
            return .f7
        case .keyboardF8:
            return .f8
        case .keyboardF9:
            return .f9
        case .keyboardF10:
            return .f10
        case .keyboardF11:
            return .f11
        case .keyboardF12:
            return .f12
        case .keyboardF13:
            return .f13
        case .keyboardF14:
            return .f14
        case .keyboardF15:
            return .f15
        case .keyboardF16:
            return .f16
        case .keyboardF17:
            return .f17
        case .keyboardF18:
            return .f18
        case .keyboardF19:
            return .f19
        case .keyboardF20:
            return .f20
        case .keyboardF21:
            return .f21
        case .keyboardF22:
            return .f22
        case .keyboardF23:
            return .f23
        case .keyboardF24:
            return .f24
        case .keypadNumLock:
            return .numLock
        case .keypadSlash:
            return .keypadDivide
        case .keypadAsterisk:
            return .keypadMultiply
        case .keypadHyphen:
            return .keypadSubtract
        case .keypadPlus:
            return .keypadAdd
        case .keypadEnter:
            return .keypadEnter
        case .keypad1:
            return .keypad1
        case .keypad2:
            return .keypad2
        case .keypad3:
            return .keypad3
        case .keypad4:
            return .keypad4
        case .keypad5:
            return .keypad5
        case .keypad6:
            return .keypad6
        case .keypad7:
            return .keypad7
        case .keypad8:
            return .keypad8
        case .keypad9:
            return .keypad9
        case .keypad0:
            return .keypad0
        case .keypadPeriod:
            return .keypadDecimal
        case .keypadEqualSign, .keypadEqualSignAS400:
            return .keypadEqual
        case .keypadComma:
            return .keypadSeparator
        case .keyboardPause:
            return .pause
        case .keyboardPrintScreen:
            return .printScreen
        case .keyboardStop:
            return .mediaStop
        case .keyboardMute:
            return .volumeMute
        case .keyboardVolumeUp:
            return .volumeUp
        case .keyboardVolumeDown:
            return .volumeDown
        case .keyboardApplication, .keyboardMenu:
            return .menu
        default:
            return nil
        }
    }

    private func kittyBaseLayoutKey(for keyCode: UIKeyboardHIDUsage) -> UnicodeScalar? {
        func scalar(_ char: Character) -> UnicodeScalar {
            char.unicodeScalars.first!
        }

        switch keyCode {
        case .keyboardA: return scalar("a")
        case .keyboardB: return scalar("b")
        case .keyboardC: return scalar("c")
        case .keyboardD: return scalar("d")
        case .keyboardE: return scalar("e")
        case .keyboardF: return scalar("f")
        case .keyboardG: return scalar("g")
        case .keyboardH: return scalar("h")
        case .keyboardI: return scalar("i")
        case .keyboardJ: return scalar("j")
        case .keyboardK: return scalar("k")
        case .keyboardL: return scalar("l")
        case .keyboardM: return scalar("m")
        case .keyboardN: return scalar("n")
        case .keyboardO: return scalar("o")
        case .keyboardP: return scalar("p")
        case .keyboardQ: return scalar("q")
        case .keyboardR: return scalar("r")
        case .keyboardS: return scalar("s")
        case .keyboardT: return scalar("t")
        case .keyboardU: return scalar("u")
        case .keyboardV: return scalar("v")
        case .keyboardW: return scalar("w")
        case .keyboardX: return scalar("x")
        case .keyboardY: return scalar("y")
        case .keyboardZ: return scalar("z")
        case .keyboard1: return scalar("1")
        case .keyboard2: return scalar("2")
        case .keyboard3: return scalar("3")
        case .keyboard4: return scalar("4")
        case .keyboard5: return scalar("5")
        case .keyboard6: return scalar("6")
        case .keyboard7: return scalar("7")
        case .keyboard8: return scalar("8")
        case .keyboard9: return scalar("9")
        case .keyboard0: return scalar("0")
        case .keyboardHyphen: return scalar("-")
        case .keyboardEqualSign: return scalar("=")
        case .keyboardOpenBracket: return scalar("[")
        case .keyboardCloseBracket: return scalar("]")
        case .keyboardBackslash: return scalar("\\")
        case .keyboardSemicolon: return scalar(";")
        case .keyboardQuote: return scalar("'")
        case .keyboardGraveAccentAndTilde: return scalar("`")
        case .keyboardComma: return scalar(",")
        case .keyboardPeriod: return scalar(".")
        case .keyboardSlash: return scalar("/")
        case .keyboardSpacebar: return scalar(" ")
        default:
            return nil
        }
    }

    private func isKittyModifierKey(_ key: KittyFunctionalKey) -> Bool {
        switch key {
        case .leftShift, .rightShift,
             .leftControl, .rightControl,
             .leftAlt, .rightAlt,
             .leftSuper, .rightSuper,
             .capsLock, .numLock, .scrollLock,
             .isoLevel3Shift, .isoLevel5Shift:
            return true
        default:
            return false
        }
    }

    private func kittyTextEvent(from key: UIKey, eventType: KittyKeyboardEventType, text: String? = nil) -> KittyKeyEvent? {
        guard let chars = key.charactersIgnoringModifiers.unicodeScalars.first else {
            return nil
        }
        let baseScalar = String(chars).lowercased().unicodeScalars.first ?? chars
        let shiftedScalar = key.modifierFlags.contains(.shift) ? key.characters.unicodeScalars.first : nil
        let baseLayout = kittyBaseLayoutKey(for: key.keyCode)
        let baseLayoutKey = baseLayout == baseScalar ? nil : baseLayout
        let modifiers = kittyModifiers(from: key, includeOption: optionAsMetaKey)
        return KittyKeyEvent(
            key: .unicode(baseScalar.value),
            modifiers: modifiers,
            eventType: eventType,
            text: text,
            shiftedKey: shiftedScalar,
            baseLayoutKey: baseLayoutKey,
            composing: false
        )
    }

    private func kittyKeyEvent(from key: UIKey, eventType: KittyKeyboardEventType, text: String? = nil) -> KittyKeyEvent? {
        if let functionKey = kittyFunctionalKey(for: key.keyCode) {
            let includeOption = optionAsMetaKey || functionKey == .leftAlt || functionKey == .rightAlt
            let modifiers = kittyModifiers(from: key, includeOption: includeOption)
            return KittyKeyEvent(
                key: .functional(functionKey),
                modifiers: modifiers,
                eventType: eventType,
                text: text,
                shiftedKey: nil,
                baseLayoutKey: nil,
                composing: false
            )
        }
        return kittyTextEvent(from: key, eventType: eventType, text: text)
    }

    private func kittyTextEventFromText(_ text: String, modifiers: KittyKeyboardModifiers, eventType: KittyKeyboardEventType) -> KittyKeyEvent {
        KittyKeyEvent(
            key: .none,
            modifiers: modifiers,
            eventType: eventType,
            text: text,
            shiftedKey: nil,
            baseLayoutKey: nil,
            composing: false
        )
    }

    private func kittyTextForFunctionalKey(_ key: KittyFunctionalKey, uiKey: UIKey) -> String? {
        switch key {
        case .keypad0, .keypad1, .keypad2, .keypad3, .keypad4,
             .keypad5, .keypad6, .keypad7, .keypad8, .keypad9,
             .keypadDecimal, .keypadDivide, .keypadMultiply, .keypadSubtract,
             .keypadAdd, .keypadEqual, .keypadSeparator:
            let text = uiKey.characters
            return text.isEmpty ? nil : text
        default:
            return nil
        }
    }

    @discardableResult
    private func sendKittyEvent(_ event: KittyKeyEvent) -> Bool {
        guard let bytes = kittyEncoder().encode(event) else { return false }
        send(bytes)
        return true
    }

    private func sendKittyModifiedTextEvent(for key: UIKey) -> Bool {
        guard let event = kittyTextEvent(from: key, eventType: .press) else {
            return false
        }
        return sendKittyEvent(event)
    }

    private func sendKittyTextInput(_ text: String) {
        let pendingEvent = pendingKittyKeyEvent
        pendingKittyKeyEvent = nil

        if text == "\n" {
            if terminal.keyboardEnhancementFlags.contains(.reportAllKeys) {
                _ = sendKittyEvent(
                    KittyKeyEvent(
                        key: .functional(.enter),
                        modifiers: [],
                        eventType: .press,
                        text: nil,
                        shiftedKey: nil,
                        baseLayoutKey: nil,
                        composing: false
                    )
                )
            } else {
                send([13])
            }
            return
        }

        let event: KittyKeyEvent
        if text.unicodeScalars.count == 1,
           let pendingEvent,
           let kittyEvent = kittyTextEvent(from: pendingEvent.key, eventType: pendingEvent.eventType, text: text) {
            event = kittyEvent
        } else {
            event = kittyTextEventFromText(text, modifiers: [], eventType: .press)
        }
        _ = sendKittyEvent(event)
    }

    private struct PendingKittyKeyEvent {
        let key: UIKey
        let eventType: KittyKeyboardEventType
    }

    private func clampedTouchPosition(at location: CGPoint) -> (grid: Position, pixels: Position)? {
        guard let terminal = terminal else { return nil }

        let clampedX = min(max(location.x, 0), bounds.width)
        let clampedY = min(max(location.y, 0), bounds.height)
        let col = max(0, min(Int(clampedX / cellDimension.width), terminal.cols - 1))
        let row = max(0, min(Int(clampedY / cellDimension.height), terminal.rows - 1))

        return (
            grid: Position(col: col, row: row),
            pixels: Position(col: Int(clampedX), row: Int(clampedY))
        )
    }

    // MARK: - Gesture handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !isLongPress else {
            isLongPress = false
            return
        }

        guard let terminal = terminal else { return }

        stopSelectionScrollTimer()
        if selection?.active == true {
            selection?.active = false
            removeSelectionHandles()
            setTerminalNeedsDisplay()
        }

        if terminal.mouseMode != .off && allowMouseReporting {
            let location = gesture.location(in: self)
            guard let hit = clampedTouchPosition(at: location) else { return }
            sendTouchToTerminal(button: 0, col: hit.grid.col, row: hit.grid.row, pressed: true, motion: false, pixels: hit.pixels)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.sendTouchToTerminal(button: 0, col: hit.grid.col, row: hit.grid.row, pressed: false, motion: false, pixels: hit.pixels)
            }
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        let col = Int(location.x / cellDimension.width)
        let row = Int(location.y / cellDimension.height)

        // Double tap selects word
        guard let terminal = terminal, let selection = selection else { return }
        let bufferRow = row + terminal.displayBuffer.yDisp
        selection.selectWordOrExpression(at: Position(col: col, row: bufferRow), in: terminal.buffer)
        setTerminalNeedsDisplay()

        // Show edit menu after word selection
        showEditMenu(at: location)
        updateSelectionHandles()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        isLongPress = true

        let location = gesture.location(in: self)
        let col = Int(location.x / cellDimension.width)
        let row = Int(location.y / cellDimension.height)

        guard let terminal = terminal, let selection = selection else { return }

        switch gesture.state {
        case .began:
            selection.startSelection(row: row, col: col)
        case .changed:
            selection.dragExtend(row: row, col: col)
        case .ended:
            // Auto-copy selected text and show edit menu
            autoCopySelection()
            showEditMenu(at: location)
            updateSelectionHandles()
        default:
            break
        }

        setTerminalNeedsDisplay()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let terminal = terminal, cellDimension.height > 0 else { return }

        if selection?.active == true {
            selection?.active = false
            removeSelectionHandles()
            setTerminalNeedsDisplay()
        }

        if gesture.state == .began {
            terminal.userScrolling = true
        }

        let translation = gesture.translation(in: self)
        let scrollDelta = Int((-translation.y / cellDimension.height).rounded(.towardZero))
        guard scrollDelta != 0 else {
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                terminal.userScrolling = false
            }
            return
        }

        if terminal.mouseMode != .off && allowMouseReporting {
            let location = gesture.location(in: self)
            guard let hit = clampedTouchPosition(at: location) else { return }
            // UIPanGestureRecognizer reports finger movement, not wheel delta.
            // Finger-up should move terminal content up, which corresponds to wheel-down for tmux.
            let button = scrollDelta > 0 ? 5 : 4

            for _ in 0..<abs(scrollDelta) {
                sendTouchToTerminal(button: button, col: hit.grid.col, row: hit.grid.row, pressed: true, motion: false, pixels: hit.pixels)
            }

            gesture.setTranslation(.zero, in: self)
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                terminal.userScrolling = false
            }
            return
        }

        let displayBuffer = terminal.displayBuffer
        let maxYDisp = max(0, displayBuffer.lines.count - displayBuffer.rows)
        let newYDisp = max(0, min(displayBuffer.yDisp + scrollDelta, maxYDisp))
        if newYDisp != displayBuffer.yDisp {
            terminal.setViewYDisp(newYDisp)
            renderer?.markAllDirty(reason: "gestureScroll")
            terminalDelegate?.scrolled(source: self, position: Double(newYDisp) / Double(max(1, maxYDisp)))
            setTerminalNeedsDisplay()
            updateSelectionHandles()
        }

        gesture.setTranslation(.zero, in: self)
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            terminal.userScrolling = false
        }
    }

    private func startSelectionScrollTimer(direction: Int) {
        guard selectionScrollTask == nil else { return }
        selectionScrollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let terminal = self.terminal else { return }
                let displayBuffer = terminal.displayBuffer
                let maxYDisp = max(0, displayBuffer.lines.count - displayBuffer.rows)
                let scrollAmount = direction < 0 ? -1 : 1
                let newYDisp = max(0, min(displayBuffer.yDisp + scrollAmount, maxYDisp))

                if newYDisp != displayBuffer.yDisp {
                    terminal.userScrolling = newYDisp != maxYDisp
                    terminal.setViewYDisp(newYDisp)
                    self.renderer?.markAllDirty(reason: "selectionScroll")
                    self.terminalDelegate?.scrolled(source: self, position: Double(newYDisp) / Double(max(1, maxYDisp)))
                    self.setTerminalNeedsDisplay()
                    self.updateSelectionHandles()

                    // Extend selection to the new edge row
                    if let selection = self.selection, selection.active {
                        let edgeRow = direction > 0
                            ? newYDisp + displayBuffer.rows - 1
                            : newYDisp
                        selection.dragExtend(row: edgeRow - newYDisp, col: terminal.cols - 1)
                    }
                }

                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopSelectionScrollTimer() {
        selectionScrollTask?.cancel()
        selectionScrollTask = nil
    }

    private func sendTouchToTerminal(button: Int, col: Int, row: Int, pressed: Bool, motion: Bool, pixels: Position) {
        guard let terminal else { return }

        let flags = terminal.encodeButton(
            button: button,
            release: !pressed,
            shift: false,
            meta: false,
            control: false
        )

        if motion {
            terminal.sendMotion(buttonFlags: flags, x: col, y: row, pixelX: pixels.col, pixelY: pixels.row)
        } else {
            terminal.sendEvent(buttonFlags: flags, x: col, y: row, pixelX: pixels.col, pixelY: pixels.row)
        }
    }

    // MARK: - Scrolling

    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        if gestureRecognizers?.contains(where: { $0 is UIPanGestureRecognizer && $0.state == .changed }) == true {
            return
        }

        guard let touch = touches.first else { return }
        let currentLocation = touch.location(in: self)
        let previousLocation = touch.previousLocation(in: self)

        let delta = currentLocation.y - previousLocation.y

        guard let terminal = terminal else { return }
        if terminal.mouseMode != .off && allowMouseReporting {
            return
        }
        let displayBuffer = terminal.displayBuffer

        let scrollDelta = Int(-delta / cellDimension.height)
        if scrollDelta != 0 {
            terminal.userScrolling = true
            let maxYDisp = max(0, displayBuffer.lines.count - displayBuffer.rows)
            let newYDisp = max(0, min(displayBuffer.yDisp + scrollDelta, maxYDisp))
            if newYDisp != displayBuffer.yDisp {
                terminal.setViewYDisp(newYDisp)
                renderer?.markAllDirty(reason: "touchScroll")
                setTerminalNeedsDisplay()
            }
        }
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        terminal?.userScrolling = false
    }

    override open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        terminal?.userScrolling = false
    }

    // MARK: - UITextInput protocol

    open func text(in range: UITextRange) -> String? {
        if let range = coerceTextRange(range) {
            if range.isEmpty {
                return ""
            }
            return String(textInputStorage[range.fullRange(in: textInputStorage)])
        }
        // Fallback: return selected terminal text
        guard let selection = selection, selection.active else { return nil }
        return selection.getSelectedText()
    }

    open func replace(_ range: UITextRange, withText text: String) {
        guard _markedTextRange == nil, let range = coerceTextRange(range) else { return }

        beginTextInputEdit()
        let oldText = String(textInputStorage[range.fullRange(in: textInputStorage)])
        textInputStorage.replaceSubrange(range.fullRange(in: textInputStorage), with: text)
        let insertionOffset = range.startOffset + utf16Length(of: text)
        let insertedPosition = IMETextPosition(offset: insertionOffset)
        _selectedTextRange = IMETextRange(start: insertedPosition, end: insertedPosition)
        endTextInputEdit()

        for _ in oldText {
            send([backspaceSendsControlH ? 8 : 0x7f])
        }
        if !text.isEmpty {
            sendCommittedText(text)
        }
    }

    open func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        let replacementRange = _markedTextRange ?? _selectedTextRange
        let rangeStartOffset = replacementRange.startOffset
        beginTextInputEdit()

        if let markedText {
            textInputStorage.replaceSubrange(replacementRange.fullRange(in: textInputStorage), with: markedText)
            let markedLength = utf16Length(of: markedText)
            let selectedLocation = max(0, min(selectedRange.location, markedLength))
            let selectedLength = max(0, min(selectedRange.length, markedLength - selectedLocation))
            _markedTextRange = IMETextRange(
                start: IMETextPosition(offset: rangeStartOffset),
                end: IMETextPosition(offset: rangeStartOffset + markedLength)
            )
            _selectedTextRange = IMETextRange(
                start: IMETextPosition(offset: rangeStartOffset + selectedLocation),
                end: IMETextPosition(offset: rangeStartOffset + selectedLocation + selectedLength)
            )
            showComposingOverlay(markedText)
        } else {
            textInputStorage.removeSubrange(replacementRange.fullRange(in: textInputStorage))
            _markedTextRange = nil
            let cursor = IMETextPosition(offset: rangeStartOffset)
            _selectedTextRange = IMETextRange(start: cursor, end: cursor)
            hideComposingOverlay()
        }

        endTextInputEdit()
    }

    open func unmarkText() {
        guard let marked = _markedTextRange else { return }

        if let committedText = text(in: marked), !committedText.isEmpty {
            insertText(committedText)
            return
        }

        beginTextInputEdit()
        let rangeEnd = IMETextPosition(offset: marked.endOffset)
        _selectedTextRange = IMETextRange(start: rangeEnd, end: rangeEnd)
        _markedTextRange = nil
        hideComposingOverlay()
        endTextInputEdit()
    }

    open var beginningOfDocument: UITextPosition {
        return IMETextPosition(offset: 0)
    }

    open var endOfDocument: UITextPosition {
        return IMETextPosition(offset: utf16Length(of: textInputStorage))
    }

    open func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let from = coerceTextPosition(fromPosition),
              let to = coerceTextPosition(toPosition) else { return nil }
        return IMETextRange(start: from, end: to)
    }

    open func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let pos = coerceTextPosition(position) else { return nil }
        let newOffset = clampOffset(pos.offset + offset)
        return IMETextPosition(offset: newOffset)
    }

    open func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        return self.position(from: position, offset: offset)
    }

    open func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        guard let pos1 = coerceTextPosition(position),
              let pos2 = coerceTextPosition(other) else { return .orderedSame }
        if pos1.offset < pos2.offset { return .orderedAscending }
        if pos1.offset > pos2.offset { return .orderedDescending }
        return .orderedSame
    }

    open func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        guard let from = coerceTextPosition(from),
              let to = coerceTextPosition(toPosition) else { return 0 }
        return to.offset - from.offset
    }

    open func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        guard let range = coerceTextRange(range) else { return nil }
        switch direction {
        case .left, .up:
            return range.start
        case .right, .down:
            return range.end
        @unknown default:
            return range.end
        }
    }

    open func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        guard let position = coerceTextPosition(position) else { return nil }
        switch direction {
        case .left, .up:
            return IMETextRange(start: IMETextPosition(offset: 0), end: position)
        case .right, .down:
            return IMETextRange(start: position, end: IMETextPosition(offset: utf16Length(of: textInputStorage)))
        @unknown default:
            return IMETextRange(start: position, end: IMETextPosition(offset: utf16Length(of: textInputStorage)))
        }
    }

    open func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        if let range = coerceTextRange(range), !range.isEmpty {
            var rect = cursorRect()
            rect.size.width = max(cellDimension.width, CGFloat(range.length) * cellDimension.width)
            return [IMETextSelectionRect(rect: rect, range: range, string: textInputStorage)]
        }
        return []
    }

    open func caretRect(for position: UITextPosition) -> CGRect {
        cursorRect()
    }

    open func closestPosition(to point: CGPoint) -> UITextPosition? {
        _selectedTextRange.start
    }

    open func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        coerceTextRange(range)?.start
    }

    open func firstRect(for range: UITextRange) -> CGRect {
        cursorRect()
    }

    open func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        return .leftToRight
    }

    open func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {
        // Terminal doesn't support writing direction changes
    }

    open func characterRange(at point: CGPoint) -> UITextRange? {
        IMETextRange(start: IMETextPosition(offset: 0), end: IMETextPosition(offset: utf16Length(of: textInputStorage)))
    }

    // MARK: - View lifecycle

    override open func layoutSubviews() {
        super.layoutSubviews()

        guard cellDimension != .zero else { return }
        guard bounds.width > 1, bounds.height > 1 else { return }

        updateDrawableMetrics()

        let newCols = Int(bounds.width / cellDimension.width)
        let newRows = Int(bounds.height / cellDimension.height)

        if let terminal = terminal,
           (newCols != terminal.cols || newRows != terminal.rows) {
            selection?.active = false
            terminal.resize(cols: newCols, rows: newRows)
            setTerminalNeedsDisplay()
        }

        if window != nil {
            refreshDisplay()
        }
    }

    override open func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, bounds.width > 1, bounds.height > 1 {
            refreshDisplay(immediately: true)
        }
    }

    override open func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil, bounds.width > 1, bounds.height > 1 {
            refreshDisplay(immediately: window != nil)
        }
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't allow simultaneous recognition with the navigation swipe-back
        // edge gesture — it causes the back animation to fire while selecting text.
        if otherGestureRecognizer is UIScreenEdgePanGestureRecognizer {
            return false
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Our pan gesture takes priority over the navigation edge-pan so that
        // scrolling / text selection always wins over swipe-back.
        if gestureRecognizer is UIPanGestureRecognizer,
           otherGestureRecognizer is UIScreenEdgePanGestureRecognizer {
            return true
        }
        return false
    }

    // MARK: - Selection & Edit Menu

    @objc open override func selectAll(_ sender: Any?) {
        selection?.selectAll()
        setTerminalNeedsDisplay()
    }

    /// Returns the currently selected text, or empty string if no selection
    public func getSelectedText() -> String {
        guard let selection = selection, selection.active else { return "" }
        return selection.getSelectedText()
    }

    /// Standard UIResponder copy action — called by the system edit menu
    @objc open override func copy(_ sender: Any?) {
        guard let selection = selection, selection.active else { return }
        let text = selection.getSelectedText()
        UIPasteboard.general.string = text
        selection.active = false
        setTerminalNeedsDisplay()
    }

    /// Auto-copy selected text to clipboard and notify via onTextSelected callback.
    /// Called when a selection gesture completes. Does NOT clear the selection.
    private func autoCopySelection() {
        guard let selection = selection, selection.active else { return }
        let text = selection.getSelectedText()
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        onTextSelected?(text)
    }

    /// Legacy method kept for programmatic use
    public func copySelection() {
        copy(nil)
    }

    /// Standard UIResponder paste action — called by the system edit menu
    @objc open override func paste(_ sender: Any?) {
        // Clear any active selection before paste
        selection?.active = false
        removeSelectionHandles()

        if let text = UIPasteboard.general.string {
            if let terminal = terminal, terminal.bracketedPasteMode {
                send(data: EscapeSequences.bracketedPasteStart[0...])
            }
            send(text: text)
            if let terminal = terminal, terminal.bracketedPasteMode {
                send(data: EscapeSequences.bracketedPasteEnd[0...])
            }
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

    /// Tell iOS which edit menu actions this view supports
    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)):
            return selection?.active == true
        case #selector(paste(_:)):
            return UIPasteboard.general.hasStrings
        case #selector(selectAll(_:)):
            return true
        default:
            return false
        }
    }

    /// Show the system edit menu at the given location
    private func showEditMenu(at location: CGPoint) {
        if #available(iOS 16.0, *) {
            let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: location)
            // Lazily create edit menu interaction if needed
            if editMenuInteraction == nil {
                let interaction = UIEditMenuInteraction(delegate: nil)
                addInteraction(interaction)
                editMenuInteraction = interaction
            }
            (editMenuInteraction as? UIEditMenuInteraction)?.presentEditMenu(with: config)
        } else {
            let menuRect = CGRect(x: location.x, y: location.y, width: 1, height: 1)
            let menu = UIMenuController.shared
            menu.showMenu(from: self, rect: menuRect)
        }
    }

    // MARK: - Selection Handles

    /// Convert a buffer Position to a screen CGPoint in this view's coordinate space.
    private func screenPoint(for bufferPosition: Position) -> CGPoint {
        guard let terminal = terminal else { return .zero }
        let displayBuffer = terminal.displayBuffer
        let screenRow = bufferPosition.row - displayBuffer.yDisp
        let x = CGFloat(bufferPosition.col) * cellDimension.width
        let y = CGFloat(screenRow) * cellDimension.height
        return CGPoint(x: x, y: y)
    }

    /// Convert a screen CGPoint to a buffer Position.
    private func bufferPosition(for screenPoint: CGPoint) -> Position {
        guard let terminal = terminal else { return Position(col: 0, row: 0) }
        let col = max(0, min(Int(screenPoint.x / cellDimension.width), terminal.cols - 1))
        let screenRow = max(0, min(Int(screenPoint.y / cellDimension.height), terminal.rows - 1))
        let bufferRow = screenRow + terminal.displayBuffer.yDisp
        return Position(col: col, row: bufferRow)
    }

    /// Create selection handles if needed and position them at the current selection bounds.
    func updateSelectionHandles() {
        guard let selection = selection, selection.active, selection.hasSelectionRange,
              let terminal = terminal, cellDimension.width > 0, cellDimension.height > 0 else {
            removeSelectionHandles()
            return
        }

        // Ensure handles exist
        if startHandle == nil {
            let handle = SelectionHandleView(role: .start)
            handle.onDrag = { [weak self] location in
                self?.handleStartDrag(to: location)
            }
            addSubview(handle)
            startHandle = handle
        }
        if endHandle == nil {
            let handle = SelectionHandleView(role: .end)
            handle.onDrag = { [weak self] location in
                self?.handleEndDrag(to: location)
            }
            addSubview(handle)
            endHandle = handle
        }

        // Position handles at selection bounds
        let normalStart: Position
        let normalEnd: Position
        if Position.compare(selection.start, selection.end) == .before {
            normalStart = selection.start
            normalEnd = selection.end
        } else {
            normalStart = selection.end
            normalEnd = selection.start
        }

        let startPoint = screenPoint(for: normalStart)
        let endPoint = screenPoint(for: normalEnd)

        let handleSize = startHandle!.intrinsicContentSize

        // Start handle: positioned at top-left of start cell, circle at bottom
        startHandle?.frame = CGRect(
            x: startPoint.x - handleSize.width / 2,
            y: startPoint.y - handleSize.height,
            width: handleSize.width,
            height: handleSize.height
        )

        // End handle: positioned at bottom-right of end cell, circle at top
        endHandle?.frame = CGRect(
            x: endPoint.x + cellDimension.width - handleSize.width / 2,
            y: endPoint.y + cellDimension.height - 2,
            width: handleSize.width,
            height: handleSize.height
        )
    }

    /// Remove all selection handles.
    func removeSelectionHandles() {
        startHandle?.removeFromSuperview()
        startHandle = nil
        endHandle?.removeFromSuperview()
        endHandle = nil
    }

    /// Handle drag of the start selection handle.
    private func handleStartDrag(to screenLocation: CGPoint) {
        guard let selection = selection else { return }
        let bufferPos = bufferPosition(for: screenLocation)

        // Set pivot to the end position and extend from there
        let normalEnd: Position
        if Position.compare(selection.start, selection.end) == .before {
            normalEnd = selection.end
        } else {
            normalEnd = selection.start
        }
        selection.pivot = normalEnd
        selection.pivotExtend(bufferPosition: bufferPos)

        setTerminalNeedsDisplay()
        updateSelectionHandles()
    }

    /// Handle drag of the end selection handle.
    private func handleEndDrag(to screenLocation: CGPoint) {
        guard let selection = selection else { return }
        let bufferPos = bufferPosition(for: screenLocation)

        // Set pivot to the start position and extend from there
        let normalStart: Position
        if Position.compare(selection.start, selection.end) == .before {
            normalStart = selection.start
        } else {
            normalStart = selection.end
        }
        selection.pivot = normalStart
        selection.pivotExtend(bufferPosition: bufferPos)

        setTerminalNeedsDisplay()
        updateSelectionHandles()
    }
}

// MARK: - Helper classes for UITextInput (IME / linear-offset based)

/// Linear-offset text position for IME composing state.
private class IMETextPosition: UITextPosition {
    let offset: Int

    init(offset: Int) {
        self.offset = offset
        super.init()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? IMETextPosition else { return false }
        return offset == other.offset
    }

    override var hash: Int { offset.hashValue }
}

/// Linear-offset text range for IME composing state.
private final class IMETextRange: UITextRange {
    private let _start: IMETextPosition
    private let _end: IMETextPosition

    var startOffset: Int { _start.offset }
    var endOffset: Int { _end.offset }
    var length: Int { endOffset - startOffset }

    override var start: UITextPosition { _start }
    override var end: UITextPosition { _end }
    override var isEmpty: Bool { _start.offset == _end.offset }

    init(start: IMETextPosition, end: IMETextPosition) {
        if start.offset <= end.offset {
            self._start = start
            self._end = end
        } else {
            self._start = end
            self._end = start
        }
        super.init()
    }

    required init?(coder: NSCoder) { fatalError() }

    func fullRange(in baseString: String) -> Range<String.Index> {
        let startIndex = String.Index(utf16Offset: startOffset, in: baseString)
        let endIndex = String.Index(utf16Offset: endOffset, in: baseString)
        return startIndex..<endIndex
    }
}

/// Text selection rect for IME candidate display.
private class IMETextSelectionRect: UITextSelectionRect {
    override var rect: CGRect { _rect }
    override var writingDirection: NSWritingDirection { .leftToRight }
    override var containsStart: Bool { _containsStart }
    override var containsEnd: Bool { _containsEnd }
    override var isVertical: Bool { false }

    private let _rect: CGRect
    private let _containsStart: Bool
    private let _containsEnd: Bool

    init(rect: CGRect, range: IMETextRange, string: String) {
        self._rect = rect
        self._containsStart = range.startOffset == 0
        self._containsEnd = range.endOffset == (string as NSString).length
        super.init()
    }
}
#endif
