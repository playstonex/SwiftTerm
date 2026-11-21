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
}
#endif
