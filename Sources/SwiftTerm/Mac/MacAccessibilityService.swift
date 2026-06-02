//
//  MacAccessibilityService.swift
//
//  Provides accessibility support for the terminal views,
//  exposing terminal content, selection, and cursor state to VoiceOver.
//
//  Created by Miguel de Icaza on 3/5/20.
//

import Foundation

#if os(macOS)
import AppKit
#endif

/// Accessibility service that bridges the terminal's text buffer to platform accessibility APIs.
///
/// VoiceOver users can read visible terminal content via `accessibilityValue`,
/// hear about selections via `accessibilitySelectedText`, and navigate the terminal
/// as a text area. The service is invalidated whenever the terminal content changes
/// or the view resizes.
class AccessibilityService {

    // MARK: - State

    /// Cached visible text, rebuilt lazily after `invalidate()`.
    private var cachedVisibleText: String = ""

    /// Incremented each time `invalidate()` is called so we can lazily rebuild cache.
    private var generation: Int = 0
    private var lastBuiltGeneration: Int = -1

    // MARK: - Public API

    /// Called by the host view whenever the terminal buffer changes, the view is resized,
    /// or the selection changes.
    func invalidate() {
        generation += 1
    }

    /// Returns the visible terminal content for accessibility value.
    ///
    /// The text represents what is currently shown in the terminal viewport,
    /// joined by newlines, with trailing whitespace trimmed per line.
    func accessibilityValue(terminal: Terminal?) -> String {
        ensureCache(terminal: terminal)
        return cachedVisibleText
    }

    /// Returns the currently selected text.
    func accessibilitySelectedText(selection: SelectionService?) -> String {
        if let selection, selection.active {
            return selection.getSelectedText()
        }
        return ""
    }

    /// Returns a human-readable description of the cursor position.
    func accessibilityCursorDescription(terminal: Terminal?) -> String {
        guard let terminal else { return "" }
        let row = terminal.buffer.y + 1
        let col = terminal.buffer.x + 1
        return "Cursor at row \(row), column \(col)"
    }

    /// Returns a string suitable for `accessibilityLabel`.
    func accessibilityLabel() -> String {
        return "Terminal"
    }

    #if os(macOS)
    /// Returns the accessibility role string (macOS only).
    func accessibilityRole() -> NSAccessibility.Role {
        return .textArea
    }
    #endif

    // MARK: - Cache

    /// Rebuilds the cached strings only when the generation has changed.
    private func ensureCache(terminal: Terminal?) {
        guard generation != lastBuiltGeneration else { return }
        lastBuiltGeneration = generation
        rebuildCache(terminal: terminal)
    }

    private func rebuildCache(terminal: Terminal?) {
        guard let terminal else {
            cachedVisibleText = ""
            return
        }

        let buffer = terminal.displayBuffer
        var lines: [String] = []
        lines.reserveCapacity(terminal.rows)

        for row in 0..<terminal.rows {
            let lineIndex = row + buffer.yDisp
            guard lineIndex >= 0, lineIndex < buffer.lines.count else { continue }
            let text = buffer.translateBufferLineToString(
                lineIndex: lineIndex,
                trimRight: true,
                startCol: 0,
                endCol: terminal.cols,
                characterProvider: { terminal.getCharacter(for: $0) }
            )
            let cleaned = text.replacingOccurrences(of: "\u{0}", with: " ")
            lines.append(cleaned)
        }

        cachedVisibleText = lines.joined(separator: "\n")
    }
}
