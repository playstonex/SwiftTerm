//
//  VertexBufferBuilder.swift
//  SwiftTerm
//
//  Builds vertex buffers for Metal rendering.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import simd

/// Vertex flags
enum VertexFlags: Float {
    case normal = 0
    case cursor = 1
    case selection = 2
}

/// Vertex structure for terminal rendering
struct TerminalVertex {
    /// Position in screen coordinates
    var position: SIMD2<Float>
    /// UV coordinates for texture sampling
    var uv: SIMD2<Float>
    /// Foreground color (RGBA)
    var fgColor: SIMD4<Float>
    /// Background color (RGBA)
    var bgColor: SIMD4<Float>
    /// Flags for special rendering
    var flags: Float

    init(position: SIMD2<Float>, uv: SIMD2<Float>, fgColor: SIMD4<Float>, bgColor: SIMD4<Float>, flags: Float = 0) {
        self.position = position
        self.uv = uv
        self.fgColor = fgColor
        self.bgColor = bgColor
        self.flags = flags
    }
}

/// Builds vertex buffers for rendering terminal content
class VertexBufferBuilder {
    /// Background vertices (drawn first, no texture)
    var backgroundVertices: [TerminalVertex] = []

    /// Glyph vertices (drawn second, with atlas texture)
    var glyphVertices: [TerminalVertex] = []

    /// Decoration vertices (drawn last, for underline/strikethrough)
    var decorationVertices: [TerminalVertex] = []

    /// Cursor vertices
    var cursorVertices: [TerminalVertex] = []

    /// Selection vertices
    var selectionVertices: [TerminalVertex] = []

    init() {}

    /// Clear all vertices
    func clear() {
        backgroundVertices.removeAll(keepingCapacity: true)
        glyphVertices.removeAll(keepingCapacity: true)
        decorationVertices.removeAll(keepingCapacity: true)
        cursorVertices.removeAll(keepingCapacity: true)
        selectionVertices.removeAll(keepingCapacity: true)
    }

    /// Add a background quad
    /// - Parameters:
    ///   - x: X position
    ///   - y: Y position
    ///   - width: Width
    ///   - height: Height
    ///   - color: Background color
    func addBackgroundQuad(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) {
        // Two triangles forming a quad
        // Triangle 1: top-left, bottom-left, top-right
        backgroundVertices.append(TerminalVertex(position: SIMD2<Float>(x, y), uv: SIMD2<Float>(0, 0), fgColor: color, bgColor: color))
        backgroundVertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color))
        backgroundVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color))

        // Triangle 2: top-right, bottom-left, bottom-right
        backgroundVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color))
        backgroundVertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color))
        backgroundVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y + height), uv: SIMD2<Float>(1, 1), fgColor: color, bgColor: color))
    }

    /// Add a glyph quad
    /// - Parameters:
    ///   - x: X position
    ///   - y: Y position
    ///   - width: Width
    ///   - height: Height
    ///   - uvRect: UV coordinates in the atlas
    ///   - fgColor: Foreground color
    func addGlyphQuad(x: Float, y: Float, width: Float, height: Float, uvRect: CGRect, fgColor: SIMD4<Float>, bgColor: SIMD4<Float>) {
        // Sample inside the glyph texel footprint to avoid bleeding from transparent atlas padding.
        let atlasWidth = max(Float(width), 1)
        let atlasHeight = max(Float(height), 1)
        let insetU = Float(uvRect.width) / atlasWidth * 0.5
        let insetV = Float(uvRect.height) / atlasHeight * 0.5
        let u0 = Float(uvRect.origin.x) + insetU
        let v0 = Float(uvRect.origin.y) + insetV
        let u1 = Float(uvRect.origin.x + uvRect.width) - insetU
        let v1 = Float(uvRect.origin.y + uvRect.height) - insetV

        // Two triangles forming a quad
        // Triangle 1: top-left, bottom-left, top-right
        glyphVertices.append(TerminalVertex(position: SIMD2<Float>(x, y), uv: SIMD2<Float>(u0, v1), fgColor: fgColor, bgColor: bgColor))
        glyphVertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(u0, v0), fgColor: fgColor, bgColor: bgColor))
        glyphVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(u1, v1), fgColor: fgColor, bgColor: bgColor))

        // Triangle 2: top-right, bottom-left, bottom-right
        glyphVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(u1, v1), fgColor: fgColor, bgColor: bgColor))
        glyphVertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(u0, v0), fgColor: fgColor, bgColor: bgColor))
        glyphVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y + height), uv: SIMD2<Float>(u1, v0), fgColor: fgColor, bgColor: bgColor))
    }

    /// Add a decoration quad (for underline or strikethrough)
    /// - Parameters:
    ///   - x: X position
    ///   - y: Y position
    ///   - width: Width
    ///   - height: Height
    ///   - color: Decoration color
    func addDecorationQuad(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) {
        // Two triangles forming a quad
        // Triangle 1: top-left, bottom-left, top-right
        decorationVertices.append(TerminalVertex(position: SIMD2<Float>(x, y), uv: SIMD2<Float>(0, 0), fgColor: color, bgColor: color))
        decorationVertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color))
        decorationVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color))

        // Triangle 2: top-right, bottom-left, bottom-right
        decorationVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color))
        decorationVertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color))
        decorationVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y + height), uv: SIMD2<Float>(1, 1), fgColor: color, bgColor: color))
    }

    /// Add a cursor quad
    /// - Parameters:
    ///   - x: X position
    ///   - y: Y position
    ///   - width: Width
    ///   - height: Height
    ///   - color: Cursor color
    func addCursorQuad(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) {
        // Two triangles forming a quad
        cursorVertices.append(TerminalVertex(position: SIMD2<Float>(x, y), uv: SIMD2<Float>(0, 0), fgColor: color, bgColor: color, flags: VertexFlags.cursor.rawValue))
        cursorVertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color, flags: VertexFlags.cursor.rawValue))
        cursorVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color, flags: VertexFlags.cursor.rawValue))

        cursorVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color, flags: VertexFlags.cursor.rawValue))
        cursorVertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color, flags: VertexFlags.cursor.rawValue))
        cursorVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y + height), uv: SIMD2<Float>(1, 1), fgColor: color, bgColor: color, flags: VertexFlags.cursor.rawValue))
    }

    /// Add a selection quad
    /// - Parameters:
    ///   - x: X position
    ///   - y: Y position
    ///   - width: Width
    ///   - height: Height
    ///   - color: Selection color
    func addSelectionQuad(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) {
        // Two triangles forming a quad
        selectionVertices.append(TerminalVertex(position: SIMD2<Float>(x, y), uv: SIMD2<Float>(0, 0), fgColor: color, bgColor: color, flags: VertexFlags.selection.rawValue))
        selectionVertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color, flags: VertexFlags.selection.rawValue))
        selectionVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color, flags: VertexFlags.selection.rawValue))

        selectionVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color, flags: VertexFlags.selection.rawValue))
        selectionVertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color, flags: VertexFlags.selection.rawValue))
        selectionVertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y + height), uv: SIMD2<Float>(1, 1), fgColor: color, bgColor: color, flags: VertexFlags.selection.rawValue))
    }

    /// Get the total vertex count
    var totalVertexCount: Int {
        return backgroundVertices.count + glyphVertices.count + decorationVertices.count + cursorVertices.count + selectionVertices.count
    }
}
#endif
