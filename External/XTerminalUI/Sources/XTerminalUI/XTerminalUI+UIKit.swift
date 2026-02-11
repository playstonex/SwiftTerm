//
//  XTerminalUI+UIKit.swift
//
//
//  Created by Lakr Aream on 2022/2/6.
//

#if canImport(UIKit)
    import UIKit

    public class XTerminalView: UIView, XTerminal {
        private let associatedCore = XTerminalCore()
        public var onLongPress: ((String) -> Void)?

        public required init() {
            super.init(frame: CGRect())
            addSubview(associatedCore.associatedWebView)
            associatedCore.associatedWebView.bindFrameToSuperviewBounds()

            // Add long press gesture for copying
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            associatedCore.associatedWebView.addGestureRecognizer(longPress)
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                // Get current line or buffer
                associatedCore.getSelection { [weak self] selection in
                    if let selection = selection, !selection.isEmpty {
                        self?.onLongPress?(selection)
                    }
                }
            }
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
            // Set the view's and WebView's background color to match the terminal theme
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let bgColor = UIColor(hex: background)
                self.backgroundColor = bgColor
                let webView = self.associatedCore.associatedWebView
                // Keep isOpaque = false to prevent white background artifacts
                webView.isOpaque = false
                webView.backgroundColor = bgColor
                webView.scrollView.backgroundColor = bgColor

                // For iOS 15+, also set underPageBackgroundColor
                if #available(iOS 15.0, *) {
                    webView.underPageBackgroundColor = bgColor
                }
            }
        }

        public func requestTerminalSize() -> CGSize {
            associatedCore.requestTerminalSize()
        }

        public func getSelection(completion: @escaping (String?) -> Void) {
            associatedCore.getSelection(completion: completion)
        }

        public func evaluateJavaScript(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
            DispatchQueue.main.async {
                self.associatedCore.associatedWebView.evaluateJavaScript(script, completionHandler: completion)
            }
        }
    }

    extension UIView {
        /// Adds constraints to this `UIView` instances `superview` object to make sure this always has the same size as the superview.
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

    extension UIColor {
        /// Initialize a UIColor from a hex string (e.g., "#1e1e1e" or "1e1e1e")
        convenience init(hex: String) {
            var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

            var rgb: UInt64 = 0

            Scanner(string: hexSanitized).scanHexInt64(&rgb)

            let length = hexSanitized.count
            var r: CGFloat = 0.0
            var g: CGFloat = 0.0
            var b: CGFloat = 0.0
            var a: CGFloat = 1.0

            if length == 6 {
                r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
                g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
                b = CGFloat(rgb & 0x0000FF) / 255.0
            } else if length == 8 {
                r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
                g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
                b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
                a = CGFloat(rgb & 0x000000FF) / 255.0
            }

            self.init(red: r, green: g, blue: b, alpha: a)
        }
    }
#endif
