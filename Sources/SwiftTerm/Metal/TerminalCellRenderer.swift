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

/// Per-row cached vertex data.
struct CachedRowVertices {
    var backgroundVertices: [TerminalVertex] = []
    var glyphBuckets = GlyphBucketList()
    var decorationVertices: [TerminalVertex] = []
}

/// Redraw data for the cursor cell: a background quad plus the cell's glyph
/// drawn on top, so a block cursor no longer hides the character underneath.
/// Two variants are kept (cursor shown / hidden) so blinking can swap between
/// them without touching the row caches.
struct CursorOverlay {
    /// The cursor cell in view coordinates (points, y down, origin of row grid).
    let cellRect: CGRect
    /// Background quad (cursor color when shown, cell background when hidden)
    var quads: [TerminalVertex] = []
    /// The glyph redrawn on top of the quad
    var glyphBuckets = GlyphBucketList()
}

/// Renders terminal cells to vertex data
class TerminalCellRenderer {
    /// The glyph cache for rasterizing glyphs
    let glyphCache: GlyphCache

    /// Display scale used for pixel snapping.
    var scale: CGFloat

    /// Selection highlight color (RGBA with alpha for sourceAlpha blending)
    var selectionColor: SIMD4<Float> = SIMD4<Float>(0.3, 0.3, 1.0, 0.5)

    /// Whether bold text also uses the bright palette entries
    var useBrightColors: Bool = true

    /// Block cursor fill color
    var caretColor: SIMD4<Float> = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)

    /// Text color drawn on top of the block cursor
    var caretTextColor: SIMD4<Float> = SIMD4<Float>(0.0, 0.0, 0.0, 1.0)

    /// Initialize a new cell renderer
    init(device: MTLDevice, scale: CGFloat) {
        self.scale = scale
        self.glyphCache = GlyphCache(device: device, scale: scale)
    }

    private func pixelAlign(_ value: Float) -> Float {
        let scale = max(Float(self.scale), 1)
        return (value * scale).rounded() / scale
    }

    /// Screen row of the terminal cursor for the current viewport.
    ///
    /// `buffer.y` is viewport-relative and only equals the screen row while
    /// the viewport is pinned to the bottom (`yDisp == yBase`); while the user
    /// is scrolled back the cursor sits below the viewport instead.
    static func cursorScreenRow(buffer: Buffer) -> Int {
        buffer.y + (buffer.yBase - buffer.yDisp)
    }

    /// Build the vertex data of a single row.
    internal func buildRowVertices(
        terminal: Terminal,
        fontSet: FontSet,
        cellDimension: CGSize,
        row: Int
    ) -> CachedRowVertices {
        let buffer = terminal.displayBuffer
        let cols = terminal.cols
        let yDisp = buffer.yDisp
        let cellWidth = Float(cellDimension.width)
        let cellHeight = Float(cellDimension.height)
        let line = buffer.lines[yDisp + row]
        let y = Float(row) * cellHeight
        let defaultBgColor = terminal.backgroundColor.toSIMD4()
        let underlineThickness = decorationThickness(fontSet: fontSet)

        var cached = CachedRowVertices()

        // Background pass. Runs matching the default background are skipped:
        // the drawable is cleared to that exact color, which keeps blank
        // regions (and whole empty screens) vertex-free.
        var col = 0
        while col < cols {
            let charData = line[col]

            let bgColor = resolveCellBackground(charData, line: line, col: col, terminal: terminal)

            var runLength = 1
            while col + runLength < cols {
                let nextChar = line[col + runLength]
                let nextBgColor = resolveCellBackground(nextChar, line: line, col: col + runLength, terminal: terminal)
                if nextBgColor == bgColor && nextChar.attribute.style == charData.attribute.style {
                    runLength += 1
                } else {
                    break
                }
            }

            if bgColor != defaultBgColor {
                let x = Float(col) * cellWidth
                appendQuad(
                    to: &cached.backgroundVertices,
                    x: x,
                    y: y,
                    width: cellWidth * Float(runLength),
                    height: cellHeight,
                    color: bgColor
                )
            }

            col += runLength
        }

        // Glyph + decoration pass
        col = 0
        while col < cols {
            let charData = line[col]

            // Decorations (underline / strikethrough) render on blank cells too
            let hasUnderline = charData.attribute.style.contains(.underline)
            let hasStrikethrough = charData.attribute.style.contains(.crossedOut)
            if hasUnderline || hasStrikethrough {
                let decorationColor = decorationColor(for: charData, terminal: terminal)
                let x = Float(col) * cellWidth
                if hasUnderline {
                    let underlineY = pixelAlign(y + cellHeight - underlineThickness * 2)
                    appendQuad(
                        to: &cached.decorationVertices,
                        x: x,
                        y: underlineY,
                        width: cellWidth * Float(max(1, Int(charData.width))),
                        height: underlineThickness,
                        color: decorationColor
                    )
                }
                if hasStrikethrough {
                    let strikeY = pixelAlign(y + cellHeight * 0.4)
                    appendQuad(
                        to: &cached.decorationVertices,
                        x: x,
                        y: strikeY,
                        width: cellWidth * Float(max(1, Int(charData.width))),
                        height: underlineThickness,
                        color: decorationColor
                    )
                }
            }

            // Skip null characters (empty cells) and wide-character placeholders
            if charData.code == 0 || charData.width == 0 {
                col += 1
                continue
            }

            var fgColor = resolveColor(charData.attribute.fg, terminal: terminal, isFg: true, isBold: charData.attribute.style.contains(.bold))

            if charData.attribute.style.contains(.dim) {
                fgColor = TerminalCellRenderer.dimmed(fgColor)
            }

            var bgColor = resolveColor(charData.attribute.bg, terminal: terminal, isFg: false, isBold: false)
            if charData.attribute.style.contains(.inverse) {
                swap(&fgColor, &bgColor)
            }
            if charData.attribute.style.contains(.invisible) {
                fgColor = SIMD4<Float>(fgColor.x, fgColor.y, fgColor.z, 0.0)
            }

            let font = selectFont(for: charData.attribute.style, from: fontSet)
            let charDataCopy = charData
            if let cachedGlyph = glyphCache.getOrCreateGlyph(code: charData.code, font: font, resolve: { terminal.getCharacter(for: charDataCopy) }) {
                let x = Float(col) * cellWidth
                let glyphX = pixelAlign(x + cachedGlyph.bearing.x)
                let glyphY = pixelAlign(y + cachedGlyph.bearing.y)
                let glyphWidth = max(1 / max(Float(scale), 1), pixelAlign(Float(cachedGlyph.size.x)))
                let glyphHeight = max(1 / max(Float(scale), 1), pixelAlign(Float(cachedGlyph.size.y)))

                cached.glyphBuckets.addQuad(
                    glyph: cachedGlyph,
                    fgColor: fgColor,
                    bgColor: bgColor,
                    x: glyphX,
                    y: glyphY,
                    width: glyphWidth,
                    height: glyphHeight
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
        var vertices: [TerminalVertex] = []
        let buffer = terminal.displayBuffer
        let cols = terminal.cols
        let rows = terminal.rows
        let yDisp = buffer.yDisp
        let cellWidth = Float(cellDimension.width)
        let cellHeight = Float(cellDimension.height)

        let isReversed = Position.compare(selection.start, selection.end) == .after
        let trueStart = isReversed ? selection.end : selection.start
        let trueEnd = isReversed ? selection.start : selection.end
        // `endIsInclusive` selections (drag, shift-click, handles) cover the end cell;
        // word/expression selections store the column one past the last selected cell.
        let lastSelectedCol = selection.endIsInclusive ? trueEnd.col : trueEnd.col - 1

        let startRow = trueStart.row - yDisp
        let endRow = trueEnd.row - yDisp
        let selectionColor = self.selectionColor
        let visibleStartRow = max(0, startRow)
        let visibleEndRowExclusive = min(rows, endRow + 1)

        if visibleStartRow < visibleEndRowExclusive {
            for row in visibleStartRow..<visibleEndRowExclusive {
                let startCol: Int
                let endCol: Int

                if row == startRow && row == endRow {
                    startCol = trueStart.col
                    endCol = lastSelectedCol
                } else if row == startRow {
                    startCol = trueStart.col
                    endCol = cols - 1
                } else if row == endRow {
                    startCol = 0
                    endCol = lastSelectedCol
                } else {
                    startCol = 0
                    endCol = cols - 1
                }

                if startCol < cols && endCol >= 0 {
                    let clampedStart = max(0, startCol)
                    let clampedEnd = min(cols - 1, endCol)
                    guard clampedStart <= clampedEnd else { continue }

                    appendQuad(
                        to: &vertices,
                        x: Float(clampedStart) * cellWidth,
                        y: Float(row) * cellHeight,
                        width: Float(clampedEnd - clampedStart + 1) * cellWidth,
                        height: cellHeight,
                        color: selectionColor,
                        flags: VertexFlags.selection.rawValue
                    )
                }
            }
        }

        return vertices
    }

    /// Build both cursor variants (shown / hidden) for the current cursor
    /// position, or nil when the cursor is hidden or outside the viewport.
    internal func buildCursorOverlay(
        terminal: Terminal,
        fontSet: FontSet,
        cellDimension: CGSize
    ) -> (on: CursorOverlay, off: CursorOverlay)? {
        guard terminal.cursorHidden == false else { return nil }

        let buffer = terminal.displayBuffer
        let cols = terminal.cols
        let rows = terminal.rows
        let cursorX = buffer.x
        let screenRow = Self.cursorScreenRow(buffer: buffer)
        guard screenRow >= 0 && screenRow < rows && cursorX >= 0 && cursorX < cols else { return nil }

        let cellWidth = Float(cellDimension.width)
        let cellHeight = Float(cellDimension.height)
        let x = Float(cursorX) * cellWidth
        let y = Float(screenRow) * cellHeight

        // The cursor may rest on the placeholder cell of a wide character;
        // the overlay then covers the glyph's full span starting at its
        // anchor column so the scissored blink repaint is complete.
        var charData = buffer.lines[buffer.yDisp + screenRow][cursorX]
        if charData.width == 0 && cursorX > 0 {
            charData = buffer.lines[buffer.yDisp + screenRow][cursorX - 1]
        }
        let span = max(1, Int(charData.width))
        let anchorX = x - cellWidth * Float(span - 1)
        let spanWidth = cellWidth * Float(span)
        let cellRect = CGRect(x: CGFloat(anchorX), y: CGFloat(y), width: CGFloat(spanWidth), height: cellDimension.height)

        var fgColor = resolveColor(charData.attribute.fg, terminal: terminal, isFg: true, isBold: charData.attribute.style.contains(.bold))
        if charData.attribute.style.contains(.dim) {
            fgColor = TerminalCellRenderer.dimmed(fgColor)
        }
        var bgColor = resolveColor(charData.attribute.bg, terminal: terminal, isFg: false, isBold: false)
        if charData.attribute.style.contains(.inverse) {
            swap(&fgColor, &bgColor)
        }

        let font = selectFont(for: charData.attribute.style, from: fontSet)
        let style = terminal.options.cursorStyle

        // "Shown" variant: the cursor shape in caretColor. For block cursors
        // the glyph is redrawn in caretTextColor so it stays readable.
        var on = CursorOverlay(cellRect: cellRect)
        switch style {
        case .blinkBlock, .steadyBlock:
            appendQuad(to: &on.quads, x: anchorX, y: y, width: spanWidth, height: cellHeight, color: caretColor, flags: VertexFlags.cursor.rawValue)
        case .blinkUnderline, .steadyUnderline:
            let thickness = max(2.0 / max(Float(scale), 1), 2.0)
            appendQuad(to: &on.quads, x: anchorX, y: y + cellHeight - thickness, width: spanWidth, height: thickness, color: caretColor, flags: VertexFlags.cursor.rawValue)
        case .blinkBar, .steadyBar:
            let barWidth = max(2.0 / max(Float(scale), 1), 2.0)
            appendQuad(to: &on.quads, x: anchorX, y: y, width: barWidth, height: cellHeight, color: caretColor, flags: VertexFlags.cursor.rawValue)
        }

        if charData.code != 0 {
            let onGlyphColor: SIMD4<Float>
            switch style {
            case .blinkBlock, .steadyBlock:
                onGlyphColor = charData.attribute.style.contains(.inverse) ? caretColor : caretTextColor
            case .blinkUnderline, .steadyUnderline, .blinkBar, .steadyBar:
                onGlyphColor = fgColor
            }
            let charDataCopy = charData
            if let cachedGlyph = glyphCache.getOrCreateGlyph(code: charData.code, font: font, resolve: { terminal.getCharacter(for: charDataCopy) }) {
                appendGlyph(
                    to: &on.glyphBuckets,
                    glyph: cachedGlyph,
                    fgColor: onGlyphColor,
                    bgColor: bgColor,
                    cellX: anchorX,
                    cellY: y
                )
            }
        }

        // "Hidden" variant: the plain cell content, used to restore the cell
        // when a blinking cursor turns off. The background quad is emitted
        // unconditionally — blink repaints run with loadAction .load inside a
        // scissor rect, so an empty overlay would leave the cursor visible.
        var off = CursorOverlay(cellRect: cellRect)
        appendQuad(to: &off.quads, x: anchorX, y: y, width: spanWidth, height: cellHeight, color: bgColor)
        if charData.code != 0 {
            let charDataCopy = charData
            if let cachedGlyph = glyphCache.getOrCreateGlyph(code: charData.code, font: font, resolve: { terminal.getCharacter(for: charDataCopy) }) {
                appendGlyph(
                    to: &off.glyphBuckets,
                    glyph: cachedGlyph,
                    fgColor: fgColor,
                    bgColor: bgColor,
                    cellX: anchorX,
                    cellY: y
                )
            }
        }

        return (on, off)
    }

    /// Build the marked-text (IME composition) overlay at the cursor position.
    internal func buildMarkedTextVertices(
        terminal: Terminal,
        fontSet: FontSet,
        cellDimension: CGSize,
        text: String,
        selectedLocation: Int,
        selectedLength: Int
    ) -> CachedRowVertices {
        guard !text.isEmpty else { return CachedRowVertices() }
        guard cellDimension.width > 0, cellDimension.height > 0 else { return CachedRowVertices() }

        let buffer = terminal.displayBuffer
        let cols = terminal.cols
        let rows = terminal.rows
        let cursorX = buffer.x
        let screenRow = Self.cursorScreenRow(buffer: buffer)
        guard screenRow >= 0, screenRow < rows, cursorX >= 0, cursorX < cols else {
            return CachedRowVertices()
        }

        let cellWidth = Float(cellDimension.width)
        let cellHeight = Float(cellDimension.height)
        let originX = Float(cursorX) * cellWidth
        let originY = Float(screenRow) * cellHeight
        let foregroundColor = terminal.foregroundColor.toSIMD4()
        let backgroundColor = terminal.backgroundColor.toSIMD4()
        let font = fontSet.normal
        let thickness = decorationThickness(fontSet: fontSet)

        var cached = CachedRowVertices()
        var columnOffset = 0

        for character in text {
            let characterWidth = Self.markedTextColumnWidth(of: character)
            guard characterWidth > 0 else { continue }
            guard cursorX + columnOffset < cols else { break }

            if let cachedGlyph = glyphCache.getOrCreateGlyph(text: String(character), font: font) {
                let cellX = originX + Float(columnOffset) * cellWidth
                appendGlyph(
                    to: &cached.glyphBuckets,
                    glyph: cachedGlyph,
                    fgColor: foregroundColor,
                    bgColor: backgroundColor,
                    cellX: cellX,
                    cellY: originY
                )
            }

            columnOffset += characterWidth
        }

        let visibleColumns = min(columnOffset, max(0, cols - cursorX))
        guard visibleColumns > 0 else { return cached }

        appendQuad(
            to: &cached.decorationVertices,
            x: originX,
            y: pixelAlign(originY + cellHeight - thickness * 2),
            width: Float(visibleColumns) * cellWidth,
            height: thickness,
            color: foregroundColor
        )

        let selectedStartColumn = min(max(0, Self.markedTextColumnOffset(in: text, upToUTF16Offset: selectedLocation)), visibleColumns)
        let selectedEndColumn = min(
            max(selectedStartColumn, Self.markedTextColumnOffset(in: text, upToUTF16Offset: selectedLocation + selectedLength)),
            visibleColumns
        )

        if selectedEndColumn > selectedStartColumn {
            appendQuad(
                to: &cached.decorationVertices,
                x: originX + Float(selectedStartColumn) * cellWidth,
                y: pixelAlign(originY + cellHeight - thickness * 4),
                width: Float(selectedEndColumn - selectedStartColumn) * cellWidth,
                height: thickness * 2,
                color: foregroundColor
            )
        } else {
            let caretWidth = max(1 / max(Float(scale), 1), 1.0)
            let maxCaretX = Float(cols) * cellWidth - caretWidth
            let caretX = min(originX + Float(selectedStartColumn) * cellWidth, maxCaretX)
            appendQuad(
                to: &cached.decorationVertices,
                x: caretX,
                y: originY + cellHeight * 0.15,
                width: caretWidth,
                height: cellHeight * 0.7,
                color: foregroundColor
            )
        }

        return cached
    }

    /// Column offset (in terminal cells) of a UTF-16 offset within marked text.
    static func markedTextColumnOffset(in text: String, upToUTF16Offset targetOffset: Int) -> Int {
        guard targetOffset > 0 else { return 0 }

        var columns = 0
        var utf16Offset = 0
        for character in text {
            let characterLength = (String(character) as NSString).length
            guard utf16Offset + characterLength <= targetOffset else {
                break
            }
            columns += Self.markedTextColumnWidth(of: character)
            utf16Offset += characterLength
        }
        return columns
    }

    /// Terminal column width of a single grapheme cluster in marked text.
    static func markedTextColumnWidth(of character: Character) -> Int {
        if character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first {
            return max(1, UnicodeUtil.columnWidth(rune: scalar))
        }

        var width = 0
        for scalar in character.unicodeScalars {
            let scalarWidth = UnicodeUtil.columnWidth(rune: scalar)
            if scalarWidth < 0 {
                continue
            }
            width = max(width, scalarWidth)
        }
        return max(1, width)
    }

    // MARK: - Helpers

    /// Resolve the effective background of the cell at `col`, following
    /// wide-character placeholders back to their anchor cell.
    private func resolveCellBackground(_ charData: CharData, line: BufferLine, col: Int, terminal: Terminal) -> SIMD4<Float> {
        if charData.width == 0 && col > 0 {
            let ref = line[col - 1]
            if ref.attribute.style.contains(.inverse) {
                return resolveColor(ref.attribute.fg, terminal: terminal, isFg: true, isBold: ref.attribute.style.contains(.bold))
            }
            return resolveColor(ref.attribute.bg, terminal: terminal, isFg: false, isBold: false)
        }
        if charData.attribute.style.contains(.inverse) {
            return resolveColor(charData.attribute.fg, terminal: terminal, isFg: true, isBold: charData.attribute.style.contains(.bold))
        }
        return resolveColor(charData.attribute.bg, terminal: terminal, isFg: false, isBold: false)
    }

    private func decorationColor(for charData: CharData, terminal: Terminal) -> SIMD4<Float> {
        if let underlineColor = charData.attribute.underlineColor {
            return underlineColor.toSIMD4(
                palette: terminal.ansiColors,
                defaultFg: terminal.foregroundColor,
                defaultBg: terminal.backgroundColor
            )
        }
        return resolveColor(charData.attribute.fg, terminal: terminal, isFg: true, isBold: charData.attribute.style.contains(.bold))
    }

    /// Line thickness for underline / strikethrough marks, derived from the
    /// font metrics and kept at or above one physical pixel.
    private func decorationThickness(fontSet: FontSet) -> Float {
        let minimum = 1 / max(Float(scale), 1)
        let metric = Float(fontSet.underlineThickness())
        return max(minimum, pixelAlign(max(metric, minimum)))
    }

    private static func dimmed(_ color: SIMD4<Float>) -> SIMD4<Float> {
        return SIMD4<Float>(color.x * 0.5, color.y * 0.5, color.z * 0.5, color.w)
    }

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

    private func appendGlyph(
        to buckets: inout GlyphBucketList,
        glyph: CachedGlyph,
        fgColor: SIMD4<Float>,
        bgColor: SIMD4<Float>,
        cellX: Float,
        cellY: Float
    ) {
        buckets.addQuad(
            glyph: glyph,
            fgColor: fgColor,
            bgColor: bgColor,
            x: pixelAlign(cellX + glyph.bearing.x),
            y: pixelAlign(cellY + glyph.bearing.y),
            width: max(1 / max(Float(scale), 1), pixelAlign(Float(glyph.size.x))),
            height: max(1 / max(Float(scale), 1), pixelAlign(Float(glyph.size.y)))
        )
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
