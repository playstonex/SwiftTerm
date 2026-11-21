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

/// Vertex structure for terminal rendering. Must match the Metal
/// `TerminalVertex` layout in Shaders.metal (56 byte stride).
struct TerminalVertex {
    /// Position in view coordinates (points, y down)
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

/// Glyph quads must be batched by the atlas texture they sample and by the
/// monochrome/color pipeline that draws them.
struct GlyphBucketKey: Equatable {
    let atlasIndex: Int
    let isColor: Bool
}

/// An ordered list of glyph-vertex buckets. Bucket order follows first use
/// so glyph z-order stays stable within a row.
struct GlyphBucketList {
    fileprivate(set) var buckets: [(key: GlyphBucketKey, vertices: [TerminalVertex])] = []

    var isEmpty: Bool { buckets.isEmpty }

    var totalCount: Int {
        buckets.reduce(0) { $0 + $1.vertices.count }
    }

    /// Append a quad sampling `glyph`. The UV rect is inset by half a texel
    /// (measured in texture texels) so linear sampling never bleeds into the
    /// transparent padding of neighboring atlas slots.
    mutating func addQuad(
        glyph: CachedGlyph,
        fgColor: SIMD4<Float>,
        bgColor: SIMD4<Float>,
        x: Float,
        y: Float,
        width: Float,
        height: Float
    ) {
        let uv = glyph.uvRect
        let texelWidth = max(glyph.texelSize.x, 1)
        let texelHeight = max(glyph.texelSize.y, 1)
        let insetU = Float(uv.width) / Float(texelWidth) * 0.5
        let insetV = Float(uv.height) / Float(texelHeight) * 0.5
        let u0 = Float(uv.minX) + insetU
        let v0 = Float(uv.minY) + insetV
        let u1 = Float(uv.maxX) - insetU
        let v1 = Float(uv.maxY) - insetV

        let key = GlyphBucketKey(atlasIndex: glyph.atlasIndex, isColor: glyph.isColor)
        let index = bucketIndex(forKey: key)

        // Two triangles forming a quad
        buckets[index].vertices.append(TerminalVertex(position: SIMD2<Float>(x, y), uv: SIMD2<Float>(u0, v1), fgColor: fgColor, bgColor: bgColor))
        buckets[index].vertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(u0, v0), fgColor: fgColor, bgColor: bgColor))
        buckets[index].vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(u1, v1), fgColor: fgColor, bgColor: bgColor))
        buckets[index].vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(u1, v1), fgColor: fgColor, bgColor: bgColor))
        buckets[index].vertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(u0, v0), fgColor: fgColor, bgColor: bgColor))
        buckets[index].vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y + height), uv: SIMD2<Float>(u1, v0), fgColor: fgColor, bgColor: bgColor))
    }

    /// Merge another list bucket-by-bucket, preserving per-bucket order.
    mutating func merge(_ other: GlyphBucketList) {
        for bucket in other.buckets {
            let index = bucketIndex(forKey: bucket.key)
            buckets[index].vertices.append(contentsOf: bucket.vertices)
        }
    }

    mutating func removeAll(keepingCapacity: Bool = true) {
        buckets.removeAll(keepingCapacity: keepingCapacity)
    }

    private mutating func bucketIndex(forKey key: GlyphBucketKey) -> Int {
        for index in buckets.indices where buckets[index].key == key {
            return index
        }
        buckets.append((key, []))
        return buckets.count - 1
    }
}

/// Builds vertex buffers for rendering terminal content
class VertexBufferBuilder {
    /// Background vertices (drawn first, no texture)
    var backgroundVertices: [TerminalVertex] = []

    /// Selection highlight vertices (drawn after backgrounds, before glyphs)
    var selectionVertices: [TerminalVertex] = []

    /// Glyph vertices grouped by render bucket (atlas texture × pipeline)
    var glyphBuckets = GlyphBucketList()

    /// Decoration vertices (underline / strikethrough / marked-text marks)
    var decorationVertices: [TerminalVertex] = []

    /// Cursor cell background quads
    var cursorVertices: [TerminalVertex] = []

    /// Glyphs redrawn on top of the block cursor (inverted text)
    var cursorGlyphBuckets = GlyphBucketList()

    init() {}

    /// Clear all vertices
    func clear() {
        backgroundVertices.removeAll(keepingCapacity: true)
        selectionVertices.removeAll(keepingCapacity: true)
        glyphBuckets.removeAll()
        decorationVertices.removeAll(keepingCapacity: true)
        cursorVertices.removeAll(keepingCapacity: true)
        cursorGlyphBuckets.removeAll()
    }

    /// Add a background quad
    func addBackgroundQuad(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) {
        appendQuad(to: &backgroundVertices, x: x, y: y, width: width, height: height, color: color)
    }

    /// Add a selection quad
    func addSelectionQuad(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) {
        appendQuad(to: &selectionVertices, x: x, y: y, width: width, height: height, color: color, flags: VertexFlags.selection.rawValue)
    }

    /// Add a decoration quad (for underline or strikethrough)
    func addDecorationQuad(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) {
        appendQuad(to: &decorationVertices, x: x, y: y, width: width, height: height, color: color)
    }

    /// Add a cursor quad
    func addCursorQuad(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) {
        appendQuad(to: &cursorVertices, x: x, y: y, width: width, height: height, color: color, flags: VertexFlags.cursor.rawValue)
    }

    /// Two triangles forming a quad
    private func appendQuad(
        to vertices: inout [TerminalVertex],
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        color: SIMD4<Float>,
        flags: Float = 0
    ) {
        vertices.append(TerminalVertex(position: SIMD2<Float>(x, y), uv: SIMD2<Float>(0, 0), fgColor: color, bgColor: color, flags: flags))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color, flags: flags))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color, flags: flags))

        vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color, flags: flags))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color, flags: flags))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y + height), uv: SIMD2<Float>(1, 1), fgColor: color, bgColor: color, flags: flags))
    }

    /// Get the total vertex count
    var totalVertexCount: Int {
        return backgroundVertices.count + selectionVertices.count + glyphBuckets.totalCount
            + decorationVertices.count + cursorVertices.count + cursorGlyphBuckets.totalCount
    }
}
#endif
