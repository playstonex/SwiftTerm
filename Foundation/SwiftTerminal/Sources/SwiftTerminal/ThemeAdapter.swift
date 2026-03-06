//
//  ThemeAdapter.swift
//  SwiftTerminal
//
//  Converts TerminalTheme colors to SwiftTerm color format
//

import Foundation
import SwiftTerm

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Helper for converting theme colors between formats
public struct ThemeAdapter {

    /// Color representation for SwiftTerm
    public struct TermColors: Equatable {
        public var foreground: ColorRGB
        public var background: ColorRGB
        public var cursor: ColorRGB
        public var black: ColorRGB
        public var red: ColorRGB
        public var green: ColorRGB
        public var yellow: ColorRGB
        public var blue: ColorRGB
        public var magenta: ColorRGB
        public var cyan: ColorRGB
        public var white: ColorRGB
        public var brightBlack: ColorRGB
        public var brightRed: ColorRGB
        public var brightGreen: ColorRGB
        public var brightYellow: ColorRGB
        public var brightBlue: ColorRGB
        public var brightMagenta: ColorRGB
        public var brightCyan: ColorRGB
        public var brightWhite: ColorRGB

        /// Get ANSI color array for SwiftTerm (16 colors in order: black, red, green, yellow, blue, magenta, cyan, white, bright variants)
        public var ansiColors: [Color] {
            return [
                black.toTerminalColor(),
                red.toTerminalColor(),
                green.toTerminalColor(),
                yellow.toTerminalColor(),
                blue.toTerminalColor(),
                magenta.toTerminalColor(),
                cyan.toTerminalColor(),
                white.toTerminalColor(),
                brightBlack.toTerminalColor(),
                brightRed.toTerminalColor(),
                brightGreen.toTerminalColor(),
                brightYellow.toTerminalColor(),
                brightBlue.toTerminalColor(),
                brightMagenta.toTerminalColor(),
                brightCyan.toTerminalColor(),
                brightWhite.toTerminalColor()
            ]
        }
    }

    /// RGB color representation
    public struct ColorRGB: Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public init(hex: String) {
            var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

            var rgb: UInt64 = 0
            Scanner(string: hexSanitized).scanHexInt64(&rgb)

            let length = hexSanitized.count

            if length == 6 {
                self.red = Double((rgb & 0xFF0000) >> 16) / 255.0
                self.green = Double((rgb & 0x00FF00) >> 8) / 255.0
                self.blue = Double(rgb & 0x0000FF) / 255.0
            } else if length == 8 {
                self.red = Double((rgb & 0xFF000000) >> 24) / 255.0
                self.green = Double((rgb & 0x00FF0000) >> 16) / 255.0
                self.blue = Double((rgb & 0x0000FF00) >> 8) / 255.0
            } else {
                self.red = 0
                self.green = 0
                self.blue = 0
            }
        }

        /// Convert to SwiftTerm Color (values are 0-65535 range)
        public func toTerminalColor() -> Color {
            let r = UInt16(red * 65535)
            let g = UInt16(green * 65535)
            let b = UInt16(blue * 65535)
            return Color(red: r, green: g, blue: b)
        }
    }

    /// Parse a terminal theme from color strings
    public static func parseTheme(
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
    ) -> TermColors {
        return TermColors(
            foreground: ColorRGB(hex: foreground),
            background: ColorRGB(hex: background),
            cursor: ColorRGB(hex: cursor),
            black: ColorRGB(hex: black),
            red: ColorRGB(hex: red),
            green: ColorRGB(hex: green),
            yellow: ColorRGB(hex: yellow),
            blue: ColorRGB(hex: blue),
            magenta: ColorRGB(hex: magenta),
            cyan: ColorRGB(hex: cyan),
            white: ColorRGB(hex: white),
            brightBlack: ColorRGB(hex: brightBlack),
            brightRed: ColorRGB(hex: brightRed),
            brightGreen: ColorRGB(hex: brightGreen),
            brightYellow: ColorRGB(hex: brightYellow),
            brightBlue: ColorRGB(hex: brightBlue),
            brightMagenta: ColorRGB(hex: brightMagenta),
            brightCyan: ColorRGB(hex: brightCyan),
            brightWhite: ColorRGB(hex: brightWhite)
        )
    }

    #if canImport(AppKit)
    /// Convert hex string to NSColor
    public static func nsColor(from hex: String) -> NSColor {
        let rgb = ColorRGB(hex: hex)
        return NSColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
    }
    #endif

    #if canImport(UIKit)
    /// Convert hex string to UIColor
    public static func uiColor(from hex: String) -> UIColor {
        let rgb = ColorRGB(hex: hex)
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
    }
    #endif
}
