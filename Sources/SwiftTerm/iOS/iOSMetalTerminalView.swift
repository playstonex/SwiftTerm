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
open class iOSMetalTerminalView: MetalTerminalView, UITextInput, UITextInputTraits {
    // MARK: - UITextInput properties

    public weak var inputDelegate: UITextInputDelegate?

    public var markedTextStyle: [NSAttributedString.Key: Any]?

    public var markedTextRange: UITextRange? {
        return nil
    }

    public var selectedTextRange: UITextRange? {
        get {
            guard let terminal = terminal else { return nil }
            let buffer = terminal.buffer
            let start = MetalTextPosition(row: buffer.y, col: buffer.x)
            let end = MetalTextPosition(row: buffer.y, col: buffer.x)
            return MetalTextRange(start: start, end: end)
        }
        set {
            // Not used for terminal
        }
    }

    public var autocapitalizationType: UITextAutocapitalizationType = .none
    public var autocorrectionType: UITextAutocorrectionType = .no
    public var spellCheckingType: UITextSpellCheckingType = .no
    public var smartQuotesType: UITextSmartQuotesType = .no
    public var smartDashesType: UITextSmartDashesType = .no
    public var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    public var keyboardType: UIKeyboardType = .asciiCapable
    public var keyboardAppearance: UIKeyboardAppearance = .dark
    public var returnKeyType: UIReturnKeyType = .default
    public var enablesReturnKeyAutomatically: Bool = false
    public var isSecureTextEntry: Bool = false

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

    /// Edit menu interaction for iOS 16+ (stored as Any to avoid @available issues)
    private var editMenuInteraction: Any?

    private var pendingKittyKeyEvent: PendingKittyKeyEvent?

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
        addGestureRecognizer(tapGesture)

        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPressGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

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
        if result {
            // Show keyboard
            NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        }
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
        if terminal.keyboardEnhancementFlags.isEmpty {
            send(text: text)
            return
        }
        sendKittyTextInput(text)
    }

    open func deleteBackward() {
        if terminal.keyboardEnhancementFlags.isEmpty {
            send([backspaceSendsControlH ? 8 : 0x7f])
            return
        }
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

    // MARK: - Gesture handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // Make sure we become first responder to receive keyboard input
        if !isFirstResponder {
            _ = becomeFirstResponder()
        }

        guard !isLongPress else {
            isLongPress = false
            return
        }

        let location = gesture.location(in: self)
        let col = Int(location.x / cellDimension.width)
        let row = Int(location.y / cellDimension.height)

        guard let terminal = terminal else { return }

        // Handle mouse reporting
        if terminal.mouseMode != .off && allowMouseReporting {
            sendTouchToTerminal(button: 0, col: col, row: row, pressed: true, motion: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.sendTouchToTerminal(button: 0, col: col, row: row, pressed: false, motion: false)
            }
        } else {
            // Handle selection - clear selection on tap
            selection?.active = false
            setTerminalNeedsDisplay()
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        let col = Int(location.x / cellDimension.width)
        let row = Int(location.y / cellDimension.height)

        // Double tap selects word
        guard let terminal = terminal, let selection = selection else { return }
        let bufferRow = row + terminal.buffer.yDisp
        selection.selectWordOrExpression(at: Position(col: col, row: bufferRow), in: terminal.buffer)
        setTerminalNeedsDisplay()

        // Show edit menu after word selection
        showEditMenu(at: location)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        isLongPress = true

        let location = gesture.location(in: self)
        let col = Int(location.x / cellDimension.width)
        let row = Int(location.y / cellDimension.height)

        guard let terminal = terminal, let selection = selection else { return }

        switch gesture.state {
        case .began:
            let bufferRow = row + terminal.buffer.yDisp
            selection.startSelection(row: bufferRow, col: col)
        case .changed:
            let bufferRow = row + terminal.buffer.yDisp
            selection.dragExtend(row: bufferRow, col: col)
        case .ended:
            // Show edit menu for copy
            showEditMenu(at: location)
        default:
            break
        }

        setTerminalNeedsDisplay()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let terminal = terminal, cellDimension.height > 0 else { return }

        let translation = gesture.translation(in: self)
        let scrollDelta = Int((-translation.y / cellDimension.height).rounded(.towardZero))
        guard scrollDelta != 0 else { return }

        let buffer = terminal.buffer
        let newYDisp = max(0, min(buffer.yDisp + scrollDelta, buffer.lines.count - terminal.rows))
        if newYDisp != buffer.yDisp {
            buffer.yDisp = newYDisp
            terminalDelegate?.scrolled(source: self, position: Double(newYDisp) / Double(max(1, buffer.lines.count - terminal.rows)))
            setTerminalNeedsDisplay()
        }

        gesture.setTranslation(.zero, in: self)
    }

    private func sendTouchToTerminal(button: Int, col: Int, row: Int, pressed: Bool, motion: Bool) {
        guard terminal != nil else { return }

        var buttonCode: UInt8 = pressed ? UInt8(button) : UInt8(button + 3)
        if motion {
            buttonCode = UInt8(button + 32)
        }

        let sequence = "\u{1b}[<\(buttonCode);\(col + 1);\(row + 1)\(pressed ? "M" : "m")"
        send(text: sequence)
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
        let buffer = terminal.buffer

        // Scroll the buffer
        let scrollDelta = Int(-delta / cellDimension.height)
        if scrollDelta != 0 {
            let newYDisp = max(0, min(buffer.yDisp + scrollDelta, buffer.lines.count - terminal.rows))
            if newYDisp != buffer.yDisp {
                buffer.yDisp = newYDisp
                setTerminalNeedsDisplay()
            }
        }
    }

    // MARK: - UITextInput protocol

    open func text(in range: UITextRange) -> String? {
        guard let terminal = terminal, let selection = selection, selection.active else { return nil }
        return selection.getSelectedText()
    }

    open func replace(_ range: UITextRange, withText text: String) {
        insertText(text)
    }

    open func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        // Handle IME
    }

    open func unmarkText() {
        // Handle IME
    }

    open var beginningOfDocument: UITextPosition {
        return MetalTextPosition(row: 0, col: 0)
    }

    open var endOfDocument: UITextPosition {
        guard let terminal = terminal else { return MetalTextPosition(row: 0, col: 0) }
        let buffer = terminal.buffer
        return MetalTextPosition(row: buffer.lines.count - 1, col: terminal.cols - 1)
    }

    open func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let from = fromPosition as? MetalTextPosition,
              let to = toPosition as? MetalTextPosition else { return nil }
        return MetalTextRange(start: from, end: to)
    }

    open func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let pos = position as? MetalTextPosition,
              let terminal = terminal else { return nil }

        var col = pos.col + offset
        var row = pos.row

        while col < 0 {
            col += terminal.cols
            row -= 1
        }
        while col >= terminal.cols {
            col -= terminal.cols
            row += 1
        }

        row = max(0, min(row, terminal.buffer.lines.count - 1))
        col = max(0, min(col, terminal.cols - 1))

        return MetalTextPosition(row: row, col: col)
    }

    open func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        return self.position(from: position, offset: offset)
    }

    open func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        guard let pos1 = position as? MetalTextPosition,
              let pos2 = other as? MetalTextPosition else { return .orderedSame }

        if pos1.row < pos2.row { return .orderedAscending }
        if pos1.row > pos2.row { return .orderedDescending }
        if pos1.col < pos2.col { return .orderedAscending }
        if pos1.col > pos2.col { return .orderedDescending }
        return .orderedSame
    }

    open func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        guard let from = from as? MetalTextPosition,
              let to = toPosition as? MetalTextPosition,
              let terminal = terminal else { return 0 }

        let fromOffset = from.row * terminal.cols + from.col
        let toOffset = to.row * terminal.cols + to.col
        return toOffset - fromOffset
    }

    open func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        return nil
    }

    open func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        return nil
    }

    open var tokenizer: UITextInputTokenizer {
        return MetalTextInputTokenizer()
    }

    open func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        guard let textRange = range as? MetalTextRange,
              let start = textRange.start as? MetalTextPosition,
              let end = textRange.end as? MetalTextPosition,
              let terminal = terminal else { return [] }

        var rects: [UITextSelectionRect] = []

        let startRow = min(start.row, end.row)
        let endRow = max(start.row, end.row)
        let startCol = (start.row < end.row || (start.row == end.row && start.col < end.col)) ? start.col : end.col
        let endCol = (start.row < end.row || (start.row == end.row && start.col < end.col)) ? end.col : start.col

        for row in startRow...endRow {
            let rectStart = row == startRow ? startCol : 0
            let rectEnd = row == endRow ? endCol : terminal.cols - 1

            let rect = CGRect(
                x: CGFloat(rectStart) * cellDimension.width,
                y: CGFloat(row) * cellDimension.height,
                width: CGFloat(rectEnd - rectStart + 1) * cellDimension.width,
                height: cellDimension.height
            )

            rects.append(MetalTextSelectionRect(rect: rect))
        }

        return rects
    }

    open func caretRect(for position: UITextPosition) -> CGRect {
        guard let pos = position as? MetalTextPosition,
              let terminal = terminal else { return .zero }

        return CGRect(
            x: CGFloat(pos.col) * cellDimension.width,
            y: CGFloat(pos.row) * cellDimension.height,
            width: 2,
            height: cellDimension.height
        )
    }

    open func closestPosition(to point: CGPoint) -> UITextPosition? {
        guard let terminal = terminal else { return nil }
        let col = Int(point.x / cellDimension.width)
        let row = Int(point.y / cellDimension.height)
        return MetalTextPosition(row: min(row, terminal.rows - 1), col: min(col, terminal.cols - 1))
    }

    open func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        return closestPosition(to: point)
    }

    open func firstRect(for range: UITextRange) -> CGRect {
        guard let textRange = range as? MetalTextRange,
              let start = textRange.start as? MetalTextPosition else { return .zero }

        return CGRect(
            x: CGFloat(start.col) * cellDimension.width,
            y: CGFloat(start.row) * cellDimension.height,
            width: cellDimension.width,
            height: cellDimension.height
        )
    }

    open func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        return .leftToRight
    }

    open func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {
        // Terminal doesn't support writing direction changes
    }

    open func characterRange(at point: CGPoint) -> UITextRange? {
        guard let terminal = terminal else { return nil }
        let col = Int(point.x / cellDimension.width)
        let row = Int(point.y / cellDimension.height)
        let pos = MetalTextPosition(row: min(row, terminal.rows - 1), col: min(col, terminal.cols - 1))
        return MetalTextRange(start: pos, end: pos)
    }

    // MARK: - View lifecycle

    override open func layoutSubviews() {
        super.layoutSubviews()

        guard cellDimension != .zero else { return }

        updateDrawableMetrics()

        let newCols = Int(bounds.width / cellDimension.width)
        let newRows = Int(bounds.height / cellDimension.height)

        if let terminal = terminal,
           (newCols != terminal.cols || newRows != terminal.rows) {
            selection?.active = false
            terminal.resize(cols: newCols, rows: newRows)
            setTerminalNeedsDisplay()
        }
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

    /// Legacy method kept for programmatic use
    public func copySelection() {
        copy(nil)
    }

    /// Standard UIResponder paste action — called by the system edit menu
    @objc open override func paste(_ sender: Any?) {
        // Clear any active selection so pasted text renders with normal theme colors
        selection?.active = false

        if let text = UIPasteboard.general.string {
            if let terminal = terminal, terminal.bracketedPasteMode {
                send(data: EscapeSequences.bracketedPasteStart[0...])
            }
            send(text: text)
            if let terminal = terminal, terminal.bracketedPasteMode {
                send(data: EscapeSequences.bracketedPasteEnd[0...])
            }
        }
        setTerminalNeedsDisplay()
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
}

// MARK: - Helper classes for UITextInput

/// Text position for terminal input
private class MetalTextPosition: UITextPosition {
    let row: Int
    let col: Int

    init(row: Int, col: Int) {
        self.row = row
        self.col = col
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MetalTextPosition else { return false }
        return row == other.row && col == other.col
    }

    override var hash: Int {
        return row.hashValue ^ col.hashValue
    }
}

/// Text range for terminal input
private class MetalTextRange: UITextRange {
    override var start: UITextPosition {
        return _start
    }
    override var end: UITextPosition {
        return _end
    }
    override var isEmpty: Bool {
        guard let s = _start as? MetalTextPosition,
              let e = _end as? MetalTextPosition else { return true }
        return s.row == e.row && s.col == e.col
    }

    private let _start: MetalTextPosition
    private let _end: MetalTextPosition

    init(start: MetalTextPosition, end: MetalTextPosition) {
        self._start = start
        self._end = end
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Text selection rect for terminal input
private class MetalTextSelectionRect: UITextSelectionRect {
    override var rect: CGRect { _rect }
    override var writingDirection: NSWritingDirection { .leftToRight }
    override var containsStart: Bool { true }
    override var containsEnd: Bool { true }
    override var isVertical: Bool { false }

    private let _rect: CGRect

    init(rect: CGRect) {
        self._rect = rect
        super.init()
    }
}

/// Text input tokenizer for terminal input
private class MetalTextInputTokenizer: NSObject, UITextInputTokenizer {
    @objc func rangeEnclosingPosition(_ position: UITextPosition, with granularity: UITextGranularity, inDirection direction: UITextDirection) -> UITextRange? {
        return nil
    }

    @objc func isPosition(_ position: UITextPosition, atBoundary granularity: UITextGranularity, inDirection direction: UITextDirection) -> Bool {
        return false
    }

    @objc func isPosition(_ position: UITextPosition, withinTextUnit granularity: UITextGranularity, inDirection direction: UITextDirection) -> Bool {
        return true
    }

    @objc func position(from position: UITextPosition, toBoundary granularity: UITextGranularity, inDirection direction: UITextDirection) -> UITextPosition? {
        return nil
    }
}
#endif
