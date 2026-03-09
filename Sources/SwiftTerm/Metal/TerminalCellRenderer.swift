//
//  TerminalCellRenderer.swift
//  SwiftTerm
//
//  Converts Terminal buffer cells to vertex data for Metal rendering.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import CoreGraphics
import CoreText
import Metal
import simd

struct CachedRowVertices {
    var backgroundVertices: [TerminalVertex] = []
    var glyphVertices: [TerminalVertex] = []
    var decorationVertices: [TerminalVertex] = []
}

/// Renders terminal cells to vertex data
class TerminalCellRenderer {
    /// The glyph cache for rasterizing glyphs
    let glyphCache: GlyphCache

    /// The command queue for Metal operations
    private let commandQueue: MTLCommandQueue

    /// Color table for fast color lookups
    private var colorTable: MetalColorTable?

    /// Display scale used for pixel snapping.
    private let scale: CGFloat

    /// Initialize a new cell renderer
    init(device: MTLDevice, commandQueue: MTLCommandQueue, scale: CGFloat) {
        self.commandQueue = commandQueue
        self.scale = scale
        self.glyphCache = GlyphCache(device: device, commandQueue: commandQueue, scale: scale)
    }

    private func pixelAlign(_ value: Float) -> Float {
        let scale = max(Float(self.scale), 1)
        return (value * scale).rounded() / scale
    }

    func prepareFrame(terminal: Terminal) {
        colorTable = MetalColorTable(terminal: terminal)
    }

    /// Build a frame of vertex data from the terminal buffer
    /// - Parameters:
    ///   - terminal: The terminal to render
    ///   - fontSet: The font set to use for rendering
    ///   - cellDimension: The size of each cell
    ///   - selection: Optional selection service for rendering selection
    ///   - commandBuffer: Optional command buffer for glyph uploads
    /// - Returns: A VertexBufferBuilder containing the vertex data
    internal func buildFrame(
        terminal: Terminal,
        fontSet: FontSet,
        cellDimension: CGSize,
        selection: SelectionService? = nil,
        commandBuffer: MTLCommandBuffer? = nil
    ) -> VertexBufferBuilder {
        let builder = VertexBufferBuilder()

        // Update color table
        colorTable = MetalColorTable(terminal: terminal)

        let buffer = terminal.displayBuffer
        let cols = terminal.cols
        let rows = terminal.rows
        let yDisp = buffer.yDisp

        let cellWidth = Float(cellDimension.width)
        let cellHeight = Float(cellDimension.height)

        // First pass: build background vertices
        for row in 0..<rows {
            let line = buffer.lines[yDisp + row]
            var col = 0

            while col < cols {
                let charData = line[col]

                // Get background color — placeholder cells (width==0) inherit the wide char's bg.
                let bgColor: SIMD4<Float>
                if charData.width == 0 && col > 0 {
                    bgColor = resolveColor(line[col - 1].attribute.bg, terminal: terminal, isFg: false, isBold: false)
                } else {
                    bgColor = resolveColor(charData.attribute.bg, terminal: terminal, isFg: false, isBold: false)
                }

                // Run-length encode background colors for efficiency
                var runLength = 1
                while col + runLength < cols {
                    let nextChar = line[col + runLength]
                    let nextBgColor: SIMD4<Float>
                    if nextChar.width == 0 && col + runLength > 0 {
                        nextBgColor = resolveColor(line[col + runLength - 1].attribute.bg, terminal: terminal, isFg: false, isBold: false)
                    } else {
                        nextBgColor = resolveColor(nextChar.attribute.bg, terminal: terminal, isFg: false, isBold: false)
                    }
                    if nextBgColor == bgColor && nextChar.attribute.style == charData.attribute.style {
                        runLength += 1
                    } else {
                        break
                    }
                }

                let x = Float(col) * cellWidth
                let y = Float(row) * cellHeight

                builder.addBackgroundQuad(
                    x: x,
                    y: y,
                    width: cellWidth * Float(runLength),
                    height: cellHeight,
                    color: bgColor
                )

                col += runLength
            }
        }

        // Second pass: render selection (drawn before glyphs)
        if let selection = selection, selection.active {
            // Determine the true start and end based on buffer position
            let isReversed = Position.compare(selection.start, selection.end) == .after
            let trueStart = isReversed ? selection.end : selection.start
            let trueEnd = isReversed ? selection.start : selection.end

            // Selection coordinates are buffer-relative (with scroll offset)
            // Convert to screen-relative by subtracting yDisp
            let startRow = trueStart.row - yDisp
            let endRow = trueEnd.row - yDisp

            let selectionColor = SIMD4<Float>(0.3, 0.3, 1.0, 0.5)
            let visibleStartRow = max(0, startRow)
            let visibleEndRowExclusive = min(rows, endRow + 1)

            if visibleStartRow < visibleEndRowExclusive {
                for row in visibleStartRow..<visibleEndRowExclusive {
                    let startCol: Int
                    let endCol: Int

                    if row == startRow && row == endRow {
                        startCol = trueStart.col
                        endCol = trueEnd.col
                    } else if row == startRow {
                        startCol = trueStart.col
                        endCol = cols - 1
                    } else if row == endRow {
                        startCol = 0
                        endCol = trueEnd.col
                    } else {
                        startCol = 0
                        endCol = cols - 1
                    }

                    if startCol < cols && endCol >= 0 {
                        let clampedStart = max(0, startCol)
                        let clampedEnd = min(cols - 1, endCol)

                        guard clampedStart <= clampedEnd else {
                            continue
                        }

                        let x = Float(clampedStart) * cellWidth
                        let y = Float(row) * cellHeight
                        let width = Float(clampedEnd - clampedStart + 1) * cellWidth

                        builder.addSelectionQuad(x: x, y: y, width: width, height: cellHeight, color: selectionColor)
                    }
                }
            }
        }

        // Third pass: render glyphs
        for row in 0..<rows {
            let line = buffer.lines[yDisp + row]
            var col = 0

            while col < cols {
                let charData = line[col]

                // Skip null characters (empty cells)
                if charData.code == 0 {
                    col += 1
                    continue
                }

                // Skip placeholder cells for wide characters
                if charData.width == 0 {
                    col += 1
                    continue
                }

                // Get foreground color
                var fgColor = resolveColor(charData.attribute.fg, terminal: terminal, isFg: true, isBold: charData.attribute.style.contains(.bold))

                // Apply dim effect if needed
                if charData.attribute.style.contains(.dim) {
                    fgColor = colorTable?.dimmed(fgColor) ?? fgColor
                }

                // Handle inverse style
                var bgColor = resolveColor(charData.attribute.bg, terminal: terminal, isFg: false, isBold: false)
                if charData.attribute.style.contains(.inverse) {
                    swap(&fgColor, &bgColor)
                }

                // Handle invisible style
                if charData.attribute.style.contains(.invisible) {
                    fgColor = SIMD4<Float>(fgColor.x, fgColor.y, fgColor.z, 0.0)
                }

                // Get the character
                let character = terminal.getCharacter(for: charData)

                // Select the appropriate font
                let font = selectFont(for: charData.attribute.style, from: fontSet)

                // Get the glyph from cache
                if let cachedGlyph = glyphCache.getOrCreateGlyph(character: character, font: font, commandBuffer: commandBuffer) {
                    let x = Float(col) * cellWidth
                    let y = Float(row) * cellHeight

                    // The cache stores the quad origin directly in cell coordinates.
                    let glyphX = pixelAlign(x + cachedGlyph.bearing.x)
                    let glyphY = pixelAlign(y + cachedGlyph.bearing.y)
                    let glyphWidth = max(1 / max(Float(scale), 1), pixelAlign(Float(cachedGlyph.size.x)))
                    let glyphHeight = max(1 / max(Float(scale), 1), pixelAlign(Float(cachedGlyph.size.y)))

                    builder.addGlyphQuad(
                        x: glyphX,
                        y: glyphY,
                        width: glyphWidth,
                        height: glyphHeight,
                        uvRect: cachedGlyph.uvRect,
                        fgColor: fgColor,
                        bgColor: bgColor
                    )
                }

                col += Int(charData.width)
            }
        }

        // Fourth pass: render decorations (underline, strikethrough)
        for row in 0..<rows {
            let line = buffer.lines[yDisp + row]
            var col = 0

            while col < cols {
                let charData = line[col]

                // Get decoration color
                var decorationColor = resolveColor(charData.attribute.fg, terminal: terminal, isFg: true, isBold: charData.attribute.style.contains(.bold))

                // Handle underline color
                if let underlineColor = charData.attribute.underlineColor {
                    decorationColor = underlineColor.toSIMD4(
                        palette: terminal.ansiColors,
                        defaultFg: terminal.foregroundColor,
                        defaultBg: terminal.backgroundColor
                    )
                }

                let x = Float(col) * cellWidth
                let y = Float(row) * cellHeight

                // Render underline
                if charData.attribute.style.contains(.underline) {
                    let underlineY = y + cellHeight - 2.0
                    let underlineHeight: Float = 1.0

                    builder.addDecorationQuad(
                        x: x,
                        y: underlineY,
                        width: cellWidth * Float(charData.width),
                        height: underlineHeight,
                        color: decorationColor
                    )
                }

                // Render strikethrough
                if charData.attribute.style.contains(.crossedOut) {
                    let strikeY = y + cellHeight * 0.4
                    let strikeHeight: Float = 1.0

                    builder.addDecorationQuad(
                        x: x,
                        y: strikeY,
                        width: cellWidth * Float(charData.width),
                        height: strikeHeight,
                        color: decorationColor
                    )
                }

                col += max(1, Int(charData.width))
            }
        }

        // Fifth pass: render cursor
        if terminal.cursorHidden == false {
            let cursorX = buffer.x
            let cursorY = buffer.y

            if cursorY >= 0 && cursorY < rows && cursorX >= 0 && cursorX < cols {
                let cursorColor = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)

                let x = Float(cursorX) * cellWidth
                let y = Float(cursorY) * cellHeight

                // Cursor style
                let cursorStyle = terminal.options.cursorStyle
                switch cursorStyle {
                case .blinkBlock, .steadyBlock:
                    builder.addCursorQuad(x: x, y: y, width: cellWidth, height: cellHeight, color: cursorColor)
                case .blinkUnderline, .steadyUnderline:
                    let underlineHeight: Float = 2.0
                    builder.addCursorQuad(x: x, y: y + cellHeight - underlineHeight, width: cellWidth, height: underlineHeight, color: cursorColor)
                case .blinkBar, .steadyBar:
                    let barWidth: Float = 2.0
                    builder.addCursorQuad(x: x, y: y, width: barWidth, height: cellHeight, color: cursorColor)
                }
            }
        }

        return builder
    }

    internal func buildRowVertices(
        terminal: Terminal,
        fontSet: FontSet,
        cellDimension: CGSize,
        row: Int,
        commandBuffer: MTLCommandBuffer? = nil
    ) -> CachedRowVertices {
        let buffer = terminal.displayBuffer
        let cols = terminal.cols
        let yDisp = buffer.yDisp
        let cellWidth = Float(cellDimension.width)
        let cellHeight = Float(cellDimension.height)
        let line = buffer.lines[yDisp + row]
        let y = Float(row) * cellHeight

        var cached = CachedRowVertices()

        var col = 0
        while col < cols {
            let charData = line[col]
            // For placeholder cells (width==0, continuation of a wide char), use the
            // preceding wide char's background so the full 2-cell span gets one color.
            let bgColor: SIMD4<Float>
            if charData.width == 0 && col > 0 {
                bgColor = resolveColor(line[col - 1].attribute.bg, terminal: terminal, isFg: false, isBold: false)
            } else {
                bgColor = resolveColor(charData.attribute.bg, terminal: terminal, isFg: false, isBold: false)
            }

            var runLength = 1
            while col + runLength < cols {
                let nextChar = line[col + runLength]
                // Treat placeholder cells as having the same bg as the wide char they belong to.
                let nextBgColor: SIMD4<Float>
                if nextChar.width == 0 && col + runLength > 0 {
                    nextBgColor = resolveColor(line[col + runLength - 1].attribute.bg, terminal: terminal, isFg: false, isBold: false)
                } else {
                    nextBgColor = resolveColor(nextChar.attribute.bg, terminal: terminal, isFg: false, isBold: false)
                }
                if nextBgColor == bgColor && nextChar.attribute.style == charData.attribute.style {
                    runLength += 1
                } else {
                    break
                }
            }

            let x = Float(col) * cellWidth
            appendQuad(
                to: &cached.backgroundVertices,
                x: x,
                y: y,
                width: cellWidth * Float(runLength),
                height: cellHeight,
                color: bgColor
            )
            col += runLength
        }

        col = 0
        while col < cols {
            let charData = line[col]
            if charData.code == 0 || charData.width == 0 {
                col += 1
                continue
            }

            var fgColor = resolveColor(charData.attribute.fg, terminal: terminal, isFg: true, isBold: charData.attribute.style.contains(.bold))
            if charData.attribute.style.contains(.dim) {
                fgColor = colorTable?.dimmed(fgColor) ?? fgColor
            }

            var bgColor = resolveColor(charData.attribute.bg, terminal: terminal, isFg: false, isBold: false)
            if charData.attribute.style.contains(.inverse) {
                swap(&fgColor, &bgColor)
            }
            if charData.attribute.style.contains(.invisible) {
                fgColor = SIMD4<Float>(fgColor.x, fgColor.y, fgColor.z, 0.0)
            }

            let character = terminal.getCharacter(for: charData)
            let font = selectFont(for: charData.attribute.style, from: fontSet)

            if let cachedGlyph = glyphCache.getOrCreateGlyph(character: character, font: font, commandBuffer: commandBuffer) {
                let x = Float(col) * cellWidth
                let glyphX = pixelAlign(x + cachedGlyph.bearing.x)
                let glyphY = pixelAlign(y + cachedGlyph.bearing.y)
                let glyphWidth = max(1 / max(Float(scale), 1), pixelAlign(Float(cachedGlyph.size.x)))
                let glyphHeight = max(1 / max(Float(scale), 1), pixelAlign(Float(cachedGlyph.size.y)))

                appendGlyphQuad(
                    to: &cached.glyphVertices,
                    x: glyphX,
                    y: glyphY,
                    width: glyphWidth,
                    height: glyphHeight,
                    uvRect: cachedGlyph.uvRect,
                    fgColor: fgColor,
                    bgColor: bgColor
                )
            }

            var decorationColor = resolveColor(charData.attribute.fg, terminal: terminal, isFg: true, isBold: charData.attribute.style.contains(.bold))
            if let underlineColor = charData.attribute.underlineColor {
                decorationColor = underlineColor.toSIMD4(
                    palette: terminal.ansiColors,
                    defaultFg: terminal.foregroundColor,
                    defaultBg: terminal.backgroundColor
                )
            }

            let x = Float(col) * cellWidth
            if charData.attribute.style.contains(.underline) {
                appendQuad(
                    to: &cached.decorationVertices,
                    x: x,
                    y: y + cellHeight - 2.0,
                    width: cellWidth * Float(charData.width),
                    height: 1.0,
                    color: decorationColor
                )
            }
            if charData.attribute.style.contains(.crossedOut) {
                appendQuad(
                    to: &cached.decorationVertices,
                    x: x,
                    y: y + cellHeight * 0.4,
                    width: cellWidth * Float(charData.width),
                    height: 1.0,
                    color: decorationColor
                )
            }

            col += max(1, Int(charData.width))
        }

        return cached
    }

    internal func buildSelectionVertices(
        terminal: Terminal,
        cellDimension: CGSize,
        selection: SelectionService?
    ) -> [TerminalVertex] {
        guard let selection = selection, selection.active else { return [] }
        let builder = VertexBufferBuilder()
        let buffer = terminal.displayBuffer
        let cols = terminal.cols
        let rows = terminal.rows
        let yDisp = buffer.yDisp
        let cellWidth = Float(cellDimension.width)
        let cellHeight = Float(cellDimension.height)

        let isReversed = Position.compare(selection.start, selection.end) == .after
        let trueStart = isReversed ? selection.end : selection.start
        let trueEnd = isReversed ? selection.start : selection.end

        let startRow = trueStart.row - yDisp
        let endRow = trueEnd.row - yDisp
        let selectionColor = SIMD4<Float>(0.3, 0.3, 1.0, 0.5)
        let visibleStartRow = max(0, startRow)
        let visibleEndRowExclusive = min(rows, endRow + 1)

        if visibleStartRow < visibleEndRowExclusive {
            for row in visibleStartRow..<visibleEndRowExclusive {
                let startCol: Int
                let endCol: Int

                if row == startRow && row == endRow {
                    startCol = trueStart.col
                    endCol = trueEnd.col
                } else if row == startRow {
                    startCol = trueStart.col
                    endCol = cols - 1
                } else if row == endRow {
                    startCol = 0
                    endCol = trueEnd.col
                } else {
                    startCol = 0
                    endCol = cols - 1
                }

                if startCol < cols && endCol >= 0 {
                    let clampedStart = max(0, startCol)
                    let clampedEnd = min(cols - 1, endCol)
                    guard clampedStart <= clampedEnd else { continue }

                    builder.addSelectionQuad(
                        x: Float(clampedStart) * cellWidth,
                        y: Float(row) * cellHeight,
                        width: Float(clampedEnd - clampedStart + 1) * cellWidth,
                        height: cellHeight,
                        color: selectionColor
                    )
                }
            }
        }

        return builder.selectionVertices
    }

    internal func buildCursorVertices(
        terminal: Terminal,
        cellDimension: CGSize
    ) -> [TerminalVertex] {
        guard terminal.cursorHidden == false else { return [] }
        let buffer = terminal.displayBuffer
        let cols = terminal.cols
        let rows = terminal.rows
        let cursorX = buffer.x
        let cursorY = buffer.y
        guard cursorY >= 0 && cursorY < rows && cursorX >= 0 && cursorX < cols else { return [] }

        let cellWidth = Float(cellDimension.width)
        let cellHeight = Float(cellDimension.height)
        let cursorColor = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
        let x = Float(cursorX) * cellWidth
        let y = Float(cursorY) * cellHeight
        let builder = VertexBufferBuilder()

        switch terminal.options.cursorStyle {
        case .blinkBlock, .steadyBlock:
            builder.addCursorQuad(x: x, y: y, width: cellWidth, height: cellHeight, color: cursorColor)
        case .blinkUnderline, .steadyUnderline:
            builder.addCursorQuad(x: x, y: y + cellHeight - 2.0, width: cellWidth, height: 2.0, color: cursorColor)
        case .blinkBar, .steadyBar:
            builder.addCursorQuad(x: x, y: y, width: 2.0, height: cellHeight, color: cursorColor)
        }

        return builder.cursorVertices
    }

    private func appendQuad(
        to vertices: inout [TerminalVertex],
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        color: SIMD4<Float>
    ) {
        vertices.append(TerminalVertex(position: SIMD2<Float>(x, y), uv: SIMD2<Float>(0, 0), fgColor: color, bgColor: color))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(1, 0), fgColor: color, bgColor: color))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(0, 1), fgColor: color, bgColor: color))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y + height), uv: SIMD2<Float>(1, 1), fgColor: color, bgColor: color))
    }

    private func appendGlyphQuad(
        to vertices: inout [TerminalVertex],
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        uvRect: CGRect,
        fgColor: SIMD4<Float>,
        bgColor: SIMD4<Float>
    ) {
        let atlasWidth = max(Float(width), 1)
        let atlasHeight = max(Float(height), 1)
        let insetU = Float(uvRect.width) / atlasWidth * 0.5
        let insetV = Float(uvRect.height) / atlasHeight * 0.5
        let u0 = Float(uvRect.origin.x) + insetU
        let v0 = Float(uvRect.origin.y) + insetV
        let u1 = Float(uvRect.origin.x + uvRect.width) - insetU
        let v1 = Float(uvRect.origin.y + uvRect.height) - insetV

        vertices.append(TerminalVertex(position: SIMD2<Float>(x, y), uv: SIMD2<Float>(u0, v1), fgColor: fgColor, bgColor: bgColor))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(u0, v0), fgColor: fgColor, bgColor: bgColor))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(u1, v1), fgColor: fgColor, bgColor: bgColor))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y), uv: SIMD2<Float>(u1, v1), fgColor: fgColor, bgColor: bgColor))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x, y + height), uv: SIMD2<Float>(u0, v0), fgColor: fgColor, bgColor: bgColor))
        vertices.append(TerminalVertex(position: SIMD2<Float>(x + width, y + height), uv: SIMD2<Float>(u1, v0), fgColor: fgColor, bgColor: bgColor))
    }

    /// Select the appropriate font for a character style
    private func selectFont(for style: CharacterStyle, from fontSet: FontSet) -> CTFont {
        if style.contains(.bold) {
            if style.contains(.italic) {
                return fontSet.boldItalic
            }
            return fontSet.bold
        }
        if style.contains(.italic) {
            return fontSet.italic
        }
        return fontSet.normal
    }

    /// Resolve an attribute color to SIMD4<Float>
    private func resolveColor(_ color: Attribute.Color, terminal: Terminal, isFg: Bool, isBold: Bool) -> SIMD4<Float> {
        let useBrightColors = true // This should be configurable

        switch color {
        case .defaultColor:
            return isFg ? terminal.foregroundColor.toSIMD4() : terminal.backgroundColor.toSIMD4()
        case .defaultInvertedColor:
            return isFg ? terminal.backgroundColor.toSIMD4() : terminal.foregroundColor.toSIMD4()
        case .ansi256(let code):
            var idx = Int(code)
            // Handle bold brightening for codes 0-7
            if isBold && useBrightColors && code < 8 {
                idx = Int(code) + 8
            }
            if idx >= 0 && idx < terminal.ansiColors.count {
                return terminal.ansiColors[idx].toSIMD4()
            }
            return isFg ? terminal.foregroundColor.toSIMD4() : terminal.backgroundColor.toSIMD4()
        case .trueColor(let r, let g, let b):
            return SIMD4<Float>(Float(r) / 255.0, Float(g) / 255.0, Float(b) / 255.0, 1.0)
        }
    }

    /// Clear the glyph cache
    public func clearCache() {
        glyphCache.clear()
    }
}
#endif
