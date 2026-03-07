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

/// Renders terminal cells to vertex data
class TerminalCellRenderer {
    private static var didLogEmptyGlyphDiagnostics = false

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
        var candidateGlyphs = 0
        var glyphMisses = 0
        var firstRenderableCharacter: Character?

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

                // Get background color
                let bgColor = resolveColor(charData.attribute.bg, terminal: terminal, isFg: false, isBold: false)

                // Run-length encode background colors for efficiency
                var runLength = 1
                while col + runLength < cols {
                    let nextChar = line[col + runLength]
                    let nextBgColor = resolveColor(nextChar.attribute.bg, terminal: terminal, isFg: false, isBold: false)
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
                if firstRenderableCharacter == nil {
                    firstRenderableCharacter = character
                }
                candidateGlyphs += 1

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
                } else {
                    glyphMisses += 1
                }

                col += Int(charData.width)
            }
        }

        if builder.glyphVertices.isEmpty && candidateGlyphs > 0 && !Self.didLogEmptyGlyphDiagnostics {
            Self.didLogEmptyGlyphDiagnostics = true
            print("MetalTerminal glyph diagnostics candidates=\(candidateGlyphs) misses=\(glyphMisses) first=\(String(describing: firstRenderableCharacter))")
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
