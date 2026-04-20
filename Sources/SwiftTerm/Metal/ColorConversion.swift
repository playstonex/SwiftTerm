//
//  ColorConversion.swift
//  SwiftTerm
//
//  Color conversion utilities for Metal rendering.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import simd

/// Extension for converting terminal colors to SIMD4<Float> for Metal
extension Attribute.Color {
    /// Convert a terminal color to SIMD4<Float>
    /// - Parameters:
    ///   - palette: The ANSI color palette
    ///   - defaultFg: Default foreground color
    ///   - defaultBg: Default background color
    /// - Returns: SIMD4<Float> representation of the color
    func toSIMD4(palette: [Color], defaultFg: Color, defaultBg: Color) -> SIMD4<Float> {
        let color: Color
        switch self {
        case .defaultColor:
            color = defaultFg
        case .defaultInvertedColor:
            color = defaultBg
        case .ansi256(let code):
            let idx = Int(code)
            if idx >= 0 && idx < palette.count {
                color = palette[idx]
            } else {
                color = defaultFg
            }
        case .trueColor(let r, let g, let b):
            return SIMD4<Float>(Float(r) / 255.0, Float(g) / 255.0, Float(b) / 255.0, 1.0)
        }

        return SIMD4<Float>(
            Float(color.red) / 65535.0,
            Float(color.green) / 65535.0,
            Float(color.blue) / 65535.0,
            1.0
        )
    }
}

/// Extension for Color to SIMD4<Float>
extension Color {
    /// Convert to SIMD4<Float>
    func toSIMD4() -> SIMD4<Float> {
        return SIMD4<Float>(
            Float(red) / 65535.0,
            Float(green) / 65535.0,
            Float(blue) / 65535.0,
            1.0
        )
    }

    /// Create from SIMD4<Float>
    static func fromSIMD4(_ value: SIMD4<Float>) -> Color {
        return Color(
            red: UInt16(value.x * 65535.0),
            green: UInt16(value.y * 65535.0),
            blue: UInt16(value.z * 65535.0)
        )
    }
}

/// Helper for building color lookup tables for Metal
class MetalColorTable {
    /// ANSI color palette as SIMD4<Float> values
    var ansiColors: [SIMD4<Float>] = []

    /// Default foreground color
    var defaultForeground: SIMD4<Float> = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)

    /// Default background color
    var defaultBackground: SIMD4<Float> = SIMD4<Float>(0.0, 0.0, 0.0, 1.0)

    /// Initialize from a Terminal's color state
    init(terminal: Terminal) {
        // Convert ANSI colors
        ansiColors = terminal.ansiColors.map { $0.toSIMD4() }

        // Set default colors
        defaultForeground = terminal.foregroundColor.toSIMD4()
        defaultBackground = terminal.backgroundColor.toSIMD4()
    }

    /// Get a color from the attribute
    func color(for attributeColor: Attribute.Color, isBold: Bool, useBrightColors: Bool) -> SIMD4<Float> {
        switch attributeColor {
        case .defaultColor:
            return defaultForeground
        case .defaultInvertedColor:
            return defaultBackground
        case .ansi256(let code):
            var idx = Int(code)
            // Handle bold brightening for codes 0-7
            if isBold && useBrightColors && code < 8 {
                idx = Int(code) + 8
            }
            // Handle bright colors dimming if not using bright colors
            if !useBrightColors && code > 7 && code < 16 {
                idx = Int(code) - 8
            }
            if idx >= 0 && idx < ansiColors.count {
                return ansiColors[idx]
            }
            return defaultForeground
        case .trueColor(let r, let g, let b):
            return SIMD4<Float>(Float(r) / 255.0, Float(g) / 255.0, Float(b) / 255.0, 1.0)
        }
    }

    /// Apply dim effect to a color
    func dimmed(_ color: SIMD4<Float>) -> SIMD4<Float> {
        return SIMD4<Float>(color.x * 0.5, color.y * 0.5, color.z * 0.5, color.w)
    }
}
#endif
