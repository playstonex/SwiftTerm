//
//  SwiftTerminalAdapter.swift
//  SwiftTerminal
//
//  Native Swift terminal adapter using SwiftTerm
//

import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

import SwiftTerm

public struct TerminalClipboardPayload: Equatable {
    public let plainText: String
    public let htmlText: String

    public init(plainText: String, htmlText: String? = nil) {
        self.plainText = plainText
        self.htmlText = htmlText ?? Self.htmlDocument(for: plainText)
    }

    public init(terminalText: String) {
        let rendered = Self.renderTerminalHTML(from: terminalText)
        self.plainText = rendered.plainText
        self.htmlText = rendered.htmlText
    }

    public func writeToPasteboard() {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
        if let data = htmlText.data(using: .utf8) {
            pasteboard.setData(data, forType: .html)
        }
        #elseif canImport(UIKit)
        UIPasteboard.general.setItems(
            [[
                "public.utf8-plain-text": plainText,
                "public.html": htmlText
            ]],
            options: [:]
        )
        #endif
    }

    private static func htmlDocument(for text: String) -> String {
        return """
        <html><body><pre style="font-family: Menlo, Monaco, 'SF Mono', monospace; white-space: pre-wrap;">\(escapeHTML(text))</pre></body></html>
        """
    }

    private struct ANSIStyle: Equatable {
        var bold = false
        var underline = false
        var foreground: String?
        var background: String?

        var css: String {
            var styles = ["white-space: pre-wrap"]
            if let foreground {
                styles.append("color: \(foreground)")
            }
            if let background {
                styles.append("background-color: \(background)")
            }
            if bold {
                styles.append("font-weight: 700")
            }
            if underline {
                styles.append("text-decoration: underline")
            }
            return styles.joined(separator: "; ")
        }
    }

    private static func renderTerminalHTML(from text: String) -> (plainText: String, htmlText: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "")
            .removingOSCSequences()

        guard let regex = try? NSRegularExpression(pattern: #"\u{001B}\[([0-9;]*)m"#) else {
            let plainText = sanitizePlainTerminalSegment(normalized)
            return (plainText, htmlDocument(for: plainText))
        }

        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        var lastIndex = normalized.startIndex
        var style = ANSIStyle()
        var plainText = ""
        var html = "<html><body><pre style=\"font-family: Menlo, Monaco, 'SF Mono', monospace; white-space: pre-wrap;\">"

        for match in regex.matches(in: normalized, range: nsRange) {
            guard let range = Range(match.range, in: normalized) else { continue }
            let segment = String(normalized[lastIndex..<range.lowerBound])
            let sanitized = sanitizePlainTerminalSegment(segment)
            plainText += sanitized
            html += styledHTML(for: sanitized, style: style)

            if let codeRange = Range(match.range(at: 1), in: normalized) {
                applySGRCodes(String(normalized[codeRange]), to: &style)
            }
            lastIndex = range.upperBound
        }

        let trailing = sanitizePlainTerminalSegment(String(normalized[lastIndex...]))
        plainText += trailing
        html += styledHTML(for: trailing, style: style)
        html += "</pre></body></html>"
        return (plainText, html)
    }

    private static func styledHTML(for text: String, style: ANSIStyle) -> String {
        guard !text.isEmpty else { return "" }
        let escaped = escapeHTML(text)
        guard style != ANSIStyle() else { return escaped }
        return "<span style=\"\(style.css)\">\(escaped)</span>"
    }

    private static func applySGRCodes(_ rawCodes: String, to style: inout ANSIStyle) {
        let codes = rawCodes.isEmpty
            ? [0]
            : rawCodes.split(separator: ";").compactMap { Int($0) }

        for code in codes {
            switch code {
            case 0:
                style = ANSIStyle()
            case 1:
                style.bold = true
            case 22:
                style.bold = false
            case 4:
                style.underline = true
            case 24:
                style.underline = false
            case 30 ... 37:
                style.foreground = ansiColor(code - 30, bright: false)
            case 39:
                style.foreground = nil
            case 40 ... 47:
                style.background = ansiColor(code - 40, bright: false)
            case 49:
                style.background = nil
            case 90 ... 97:
                style.foreground = ansiColor(code - 90, bright: true)
            case 100 ... 107:
                style.background = ansiColor(code - 100, bright: true)
            default:
                continue
            }
        }
    }

    private static func ansiColor(_ index: Int, bright: Bool) -> String {
        let standard = ["#1d1f21", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb", "#8abeb7", "#c5c8c6"]
        let brightColors = ["#666666", "#d54e53", "#b9ca4a", "#e7c547", "#7aa6da", "#c397d8", "#70c0b1", "#eaeaea"]
        let palette = bright ? brightColors : standard
        return palette.indices.contains(index) ? palette[index] : "#c5c8c6"
    }

    private static func sanitizePlainTerminalSegment(_ text: String) -> String {
        var sanitized = text
        sanitized = sanitized.replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(of: "\u{1B}\\([0-9A-Za-z]", with: "", options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(of: "\u{08}", with: "")
        return sanitized
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension String {
    func removingOSCSequences() -> String {
        replacingOccurrences(
            of: "\u{1B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{1B}\\\\)",
            with: "",
            options: .regularExpression
        )
    }
}

public enum TerminalEvent: Equatable {
    case input(String)
    case title(String)
    case bell
    case size(CGSize)
    case copy(TerminalClipboardPayload)
}

/// Protocol defining the terminal interface that matches XTerminal
public protocol NativeTerminalProtocol {
    @discardableResult func setupEventChain(callback: ((TerminalEvent) -> Void)?) -> Self
    @discardableResult func setupBufferChain(callback: ((String) -> Void)?) -> Self
    @discardableResult func setupTitleChain(callback: ((String) -> Void)?) -> Self
    @discardableResult func setupBellChain(callback: (() -> Void)?) -> Self
    @discardableResult func setupSizeChain(callback: ((CGSize) -> Void)?) -> Self
    @discardableResult func setupCopyChain(callback: ((TerminalClipboardPayload) -> Void)?) -> Self
    @discardableResult func setupNavigationChain(callback: (() -> Void)?) -> Self
    func write(_ str: String)
    func write(data: Data)
    func requestTerminalSize() -> CGSize
    func setTerminalFontSize(with size: Int)
    func setTerminalFontName(with name: String)
    func activateKeyboard()
    func dismissKeyboard()
    func getSelection(completion: @escaping (String?) -> Void)
    func refreshDisplay()
    func setTerminalTheme(
        foreground: String,
        background: String,
        cursor: String,
        black: String,
        red: String,
        green: String,
        yellow: String,
        blue: String,
        magenta: String,
        cyan: String,
        white: String,
        brightBlack: String,
        brightRed: String,
        brightGreen: String,
        brightYellow: String,
        brightBlue: String,
        brightMagenta: String,
        brightCyan: String,
        brightWhite: String
    )
}

/// Adapter that bridges SwiftTerm to the XTerminal protocol
public final class SwiftTerminalAdapter: NativeTerminalProtocol {

    // MARK: - Callbacks

    private var bufferCallback: ((String) -> Void)?
    private var titleCallback: ((String) -> Void)?
    private var bellCallback: (() -> Void)?
    private var sizeCallback: ((CGSize) -> Void)?
    private var copyCallback: ((TerminalClipboardPayload) -> Void)?
    private var eventCallback: ((TerminalEvent) -> Void)?
    private var navigationCallback: (() -> Void)?

    // MARK: - State

    private var currentFontSize: Int = 14
    private var currentFontName: String = "Menlo"
    private var currentTheme: TerminalThemeColors?

    // MARK: - Theme Helper

    struct TerminalThemeColors {
        let foreground: String
        let background: String
        let cursor: String
        let black: String
        let red: String
        let green: String
        let yellow: String
        let blue: String
        let magenta: String
        let cyan: String
        let white: String
        let brightBlack: String
        let brightRed: String
        let brightGreen: String
        let brightYellow: String
        let brightBlue: String
        let brightMagenta: String
        let brightCyan: String
        let brightWhite: String
    }

    // MARK: - NativeTerminalProtocol Implementation

    @discardableResult
    public func setupEventChain(callback: ((TerminalEvent) -> Void)?) -> Self {
        eventCallback = callback
        return self
    }

    @discardableResult
    public func setupBufferChain(callback: ((String) -> Void)?) -> Self {
        bufferCallback = callback
        return self
    }

    @discardableResult
    public func setupTitleChain(callback: ((String) -> Void)?) -> Self {
        titleCallback = callback
        return self
    }

    @discardableResult
    public func setupBellChain(callback: (() -> Void)?) -> Self {
        bellCallback = callback
        return self
    }

    @discardableResult
    public func setupSizeChain(callback: ((CGSize) -> Void)?) -> Self {
        sizeCallback = callback
        return self
    }

    @discardableResult
    public func setupCopyChain(callback: ((TerminalClipboardPayload) -> Void)?) -> Self {
        copyCallback = callback
        return self
    }

    @discardableResult
    public func setupNavigationChain(callback: (() -> Void)?) -> Self {
        navigationCallback = callback
        // Native view is ready instantly, no need to wait for navigation
        callback?()
        return self
    }

    public func write(_ str: String) {
        // This method is for displaying output to the terminal
        // It should NOT call bufferCallback which is for user input
        // The platform-specific view implements write using terminal.feed()
    }

    public func write(data: Data) {
        // This method is for displaying raw terminal bytes to the terminal.
        // The platform-specific view implements write using terminal.feed().
    }

    public func requestTerminalSize() -> CGSize {
        // Will be overridden by platform view
        return CGSize(width: 80, height: 24)
    }

    public func setTerminalFontSize(with size: Int) {
        currentFontSize = size
    }

    public func setTerminalFontName(with name: String) {
        currentFontName = name
    }

    public func getSelection(completion: @escaping (String?) -> Void) {
        // Will be implemented by platform-specific view
        completion(nil)
    }

    public func activateKeyboard() {
        // Will be implemented by platform-specific view
    }

    public func dismissKeyboard() {
        // Will be implemented by platform-specific view
    }

    public func refreshDisplay() {
        // Will be implemented by platform-specific view
    }

    public func setTerminalTheme(
        foreground: String,
        background: String,
        cursor: String,
        black: String,
        red: String,
        green: String,
        yellow: String,
        blue: String,
        magenta: String,
        cyan: String,
        white: String,
        brightBlack: String,
        brightRed: String,
        brightGreen: String,
        brightYellow: String,
        brightBlue: String,
        brightMagenta: String,
        brightCyan: String,
        brightWhite: String
    ) {
        currentTheme = TerminalThemeColors(
            foreground: foreground,
            background: background,
            cursor: cursor,
            black: black,
            red: red,
            green: green,
            yellow: yellow,
            blue: blue,
            magenta: magenta,
            cyan: cyan,
            white: white,
            brightBlack: brightBlack,
            brightRed: brightRed,
            brightGreen: brightGreen,
            brightYellow: brightYellow,
            brightBlue: brightBlue,
            brightMagenta: brightMagenta,
            brightCyan: brightCyan,
            brightWhite: brightWhite
        )
    }

    // MARK: - Internal Methods for Platform Views

    func notifyBuffer(_ str: String) {
        bufferCallback?(str)
        eventCallback?(.input(str))
    }

    func notifyTitle(_ title: String) {
        titleCallback?(title)
        eventCallback?(.title(title))
    }

    func notifyBell() {
        bellCallback?()
        eventCallback?(.bell)
    }

    func notifySize(_ size: CGSize) {
        sizeCallback?(size)
        eventCallback?(.size(size))
    }

    func notifyCopy(_ content: String) {
        let payload = TerminalClipboardPayload(terminalText: content)
        copyCallback?(payload)
        eventCallback?(.copy(payload))
    }

    func getCurrentFontSize() -> Int {
        return currentFontSize
    }

    func getCurrentFontName() -> String {
        return currentFontName
    }

    func getCurrentTheme() -> TerminalThemeColors? {
        return currentTheme
    }
}
