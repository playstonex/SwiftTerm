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

/// Protocol defining the terminal interface that matches XTerminal
public protocol NativeTerminalProtocol {
    @discardableResult func setupBufferChain(callback: ((String) -> Void)?) -> Self
    @discardableResult func setupTitleChain(callback: ((String) -> Void)?) -> Self
    @discardableResult func setupBellChain(callback: (() -> Void)?) -> Self
    @discardableResult func setupSizeChain(callback: ((CGSize) -> Void)?) -> Self
    @discardableResult func setupCopyChain(callback: ((String) -> Void)?) -> Self
    @discardableResult func setupNavigationChain(callback: (() -> Void)?) -> Self
    func write(_ str: String)
    func requestTerminalSize() -> CGSize
    func setTerminalFontSize(with size: Int)
    func setTerminalFontName(with name: String)
    func getSelection(completion: @escaping (String?) -> Void)
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
    private var copyCallback: ((String) -> Void)?
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
    public func setupCopyChain(callback: ((String) -> Void)?) -> Self {
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
        // This will be implemented by the platform-specific view
        // The view will call this to notify the adapter that data was written
        bufferCallback?(str)
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
    }

    func notifyTitle(_ title: String) {
        titleCallback?(title)
    }

    func notifyBell() {
        bellCallback?()
    }

    func notifySize(_ size: CGSize) {
        sizeCallback?(size)
    }

    func notifyCopy(_ content: String) {
        copyCallback?(content)
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
