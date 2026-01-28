//
//  XTerminalUI+AppKit.swift
//
//
//  Created by Lakr Aream on 2022/2/6.
//

import Foundation

#if canImport(AppKit)
    import AppKit

    public class XTerminalView: NSView, XTerminal {
        private let associatedCore = XTerminalCore()

        public required init() {
            super.init(frame: CGRect())
            addSubview(associatedCore.associatedWebView)
            associatedCore.associatedWebView.bindFrameToSuperviewBounds()
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("unavailable")
        }

        @discardableResult
        public func setupBufferChain(callback: ((String) -> Void)?) -> Self {
            associatedCore.setupBufferChain(callback: callback)
            return self
        }

        @discardableResult
        public func setupTitleChain(callback: ((String) -> Void)?) -> Self {
            associatedCore.setupTitleChain(callback: callback)
            return self
        }

        @discardableResult
        public func setupBellChain(callback: (() -> Void)?) -> Self {
            associatedCore.setupBellChain(callback: callback)
            return self
        }

        @discardableResult
        public func setupSizeChain(callback: ((CGSize) -> Void)?) -> Self {
            associatedCore.setupSizeChain(callback: callback)
            return self
        }

        @discardableResult
        public func setupCopyChain(callback: ((String) -> Void)?) -> Self {
            associatedCore.setupCopyChain(callback: callback)
            return self
        }

        @discardableResult
        public func setupNavigationChain(callback: (() -> Void)?) -> Self {
            associatedCore.setupNavigationChain(callback: callback)
            return self
        }

        public func write(_ str: String) {
            associatedCore.write(str)
        }

        public func setTerminalFontSize(with size: Int) {
            associatedCore.setTerminalFontSize(with: size)
        }

        public func setTerminalFontName(with name: String) {
            associatedCore.setTerminalFontName(with: name)
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
            associatedCore.setTerminalTheme(
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

        public func requestTerminalSize() -> CGSize {
            associatedCore.requestTerminalSize()
        }
    }

    extension NSView {
        /// Adds constraints to this `NSView` instances `superview` object to make sure this always has the same size as the superview.
        /// Please note that this has no effect if its `superview` is `nil` – add this `UIView` instance as a subview before calling this.
        func bindFrameToSuperviewBounds() {
            guard let superview = superview else {
                print("Error! `superview` was nil – call `addSubview(view: UIView)` before calling `bindFrameToSuperviewBounds()` to fix this.")
                return
            }

            translatesAutoresizingMaskIntoConstraints = false
            topAnchor.constraint(equalTo: superview.topAnchor, constant: 0).isActive = true
            bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: 0).isActive = true
            leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: 0).isActive = true
            trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: 0).isActive = true
        }
    }

#endif
