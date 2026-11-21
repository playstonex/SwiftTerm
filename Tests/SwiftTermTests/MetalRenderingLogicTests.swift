import CoreGraphics
import Testing
@testable import SwiftTerm

#if os(macOS) || os(iOS) || os(visionOS)

/// Unit tests for the pure logic of the Metal rendering layer: atlas shelf
/// packing, cursor row math, marked-text column widths and the update-range
/// contract that drives incremental redraws. None of these require a GPU.
@Suite
struct MetalRenderingLogicTests {
    // MARK: - ShelfAllocator

    @Test func testShelfAllocatorPlacesGlyphsWithPadding() {
        var allocator = ShelfAllocator(size: 64, padding: 1)

        let first = allocator.allocate(width: 10, height: 8)
        #expect(first == ShelfAllocator.Allocation(x: 1, y: 1))

        // Same shelf: advances by width + 2*padding, plus one padding inset.
        let second = allocator.allocate(width: 4, height: 6)
        #expect(second == ShelfAllocator.Allocation(x: 13, y: 1))

        // Tall glyph forces a new shelf below the first one (height 8 + 2).
        let tall = allocator.allocate(width: 4, height: 20)
        #expect(tall == ShelfAllocator.Allocation(x: 1, y: 11))
    }

    @Test func testShelfAllocatorRejectsGlyphsLargerThanAtlas() {
        var allocator = ShelfAllocator(size: 32, padding: 1)
        #expect(allocator.allocate(width: 32, height: 8) == nil)
        #expect(allocator.allocate(width: 8, height: 40) == nil)
        // The failed allocations must not have consumed any space; a glyph
        // that fits only with its padding still succeeds afterwards.
        #expect(allocator.allocate(width: 30, height: 30) != nil)
    }

    @Test func testShelfAllocatorReportsExhaustion() {
        var allocator = ShelfAllocator(size: 16, padding: 1)
        // Shelves of height 6 (4 + 2*1): two fit into 16, each holding two
        // 4-texel glyphs (4 + 2*1 + 4 + 2*1 = 12 <= 16).
        #expect(allocator.allocate(width: 4, height: 4) != nil)
        #expect(allocator.allocate(width: 4, height: 4) != nil)
        #expect(allocator.allocate(width: 4, height: 4) != nil)
        #expect(allocator.allocate(width: 4, height: 4) != nil)
        #expect(allocator.allocate(width: 4, height: 4) == nil)
    }

    @Test func testShelfAllocatorResetRestoresSpace() {
        var allocator = ShelfAllocator(size: 16, padding: 1)
        for _ in 0..<4 {
            _ = allocator.allocate(width: 4, height: 4)
        }
        #expect(allocator.allocate(width: 4, height: 4) == nil)

        allocator.removeAll()

        let afterReset = allocator.allocate(width: 4, height: 4)
        #expect(afterReset == ShelfAllocator.Allocation(x: 1, y: 1))
    }

    // MARK: - Cursor screen row

    @Test func testCursorScreenRowPinnedToBottom() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 4, scrollback: 100)
        terminal.feed(text: "hello")
        let buffer = terminal.buffer
        // yDisp == yBase: viewport-relative and screen rows coincide.
        #expect(buffer.yDisp == buffer.yBase)
        #expect(TerminalCellRenderer.cursorScreenRow(buffer: buffer) == buffer.y)
    }

    @Test func testCursorScreenRowShiftsBelowViewportWhenScrolledBack() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 4, scrollback: 100)
        terminal.feed(text: "1\r\n2\r\n3\r\n4\r\n5\r\n6\r\n7")
        let buffer = terminal.buffer
        buffer.yDisp = 0 // user scrolled to the top of scrollback

        let screenRow = TerminalCellRenderer.cursorScreenRow(buffer: buffer)
        #expect(screenRow == buffer.y + buffer.yBase)
        // While scrolled back the cursor must be below the viewport.
        #expect(screenRow >= terminal.rows)
    }

    @Test func testCursorScreenRowInAlternateBuffer() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 4, scrollback: 100)
        terminal.feed(text: "scrollback\r\nlines\r\n")
        terminal.feed(text: "\u{1b}[?1049h") // enter alt screen
        terminal.feed(text: "vim")
        let buffer = terminal.buffer
        #expect(buffer === terminal.altBuffer)
        #expect(TerminalCellRenderer.cursorScreenRow(buffer: buffer) == buffer.y)
    }

    // MARK: - Marked text columns

    @Test func testMarkedTextColumnWidths() {
        #expect(TerminalCellRenderer.markedTextColumnWidth(of: "a") == 1)
        #expect(TerminalCellRenderer.markedTextColumnWidth(of: "中") == 2)
        // ZWJ family emoji is a single grapheme cluster occupying two columns.
        #expect(TerminalCellRenderer.markedTextColumnWidth(of: "👨‍👩‍👧‍👦") == 2)
        // Combining mark cluster: width of the base character.
        #expect(TerminalCellRenderer.markedTextColumnWidth(of: "e\u{301}") == 1)
    }

    @Test func testMarkedTextColumnOffsetCountsGraphemes() {
        let text = "a中b"
        // UTF-16 offsets: a=0, 中=1 (BMP), b=2; columns: a=1, 中=2, b=1.
        #expect(TerminalCellRenderer.markedTextColumnOffset(in: text, upToUTF16Offset: 0) == 0)
        #expect(TerminalCellRenderer.markedTextColumnOffset(in: text, upToUTF16Offset: 1) == 1)
        #expect(TerminalCellRenderer.markedTextColumnOffset(in: text, upToUTF16Offset: 2) == 3)
        #expect(TerminalCellRenderer.markedTextColumnOffset(in: text, upToUTF16Offset: 3) == 4)
        #expect(TerminalCellRenderer.markedTextColumnOffset(in: text, upToUTF16Offset: 99) == 4)
    }

    // MARK: - Update range contract (drives processPendingUpdates)

    @Test func testUpdateRangeAccumulatesFedRows() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 40, rows: 6, scrollback: 50)
        terminal.clearUpdateRange()
        #expect(terminal.getUpdateRange() == nil)

        terminal.feed(text: "hello world")
        let range = terminal.getUpdateRange()
        #expect(range != nil)
        #expect(range!.startY == 0)
        #expect(range!.endY == 0)

        terminal.clearUpdateRange()
        #expect(terminal.getUpdateRange() == nil)
    }

    @Test func testUpdateRangeSpansMultipleRows() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 40, rows: 6, scrollback: 50)
        terminal.clearUpdateRange()
        terminal.feed(text: "one\r\ntwo\r\nthree\r\nfour")
        let range = terminal.getUpdateRange()
        #expect(range != nil)
        #expect(range!.startY == 0)
        #expect(range!.endY >= 2)
        terminal.clearUpdateRange()
    }

    // MARK: - Grid fitting

    @Test func testCellCountRoundTripsStretchedCells() {
        // Cells are stretched to exactly length / count; dividing back must
        // yield the same count, or the grid loses a column/row.
        for length in stride(from: CGFloat(100), through: 3000, by: 0.5) {
            for cell in [CGFloat(7.5), 8, 8.5, 9, 13.5, 17] {
                let count = MetalTerminalView.cellCount(length, cell: cell)
                let stretched = length / CGFloat(count)
                #expect(MetalTerminalView.cellCount(length, cell: stretched) == count)
            }
        }
        #expect(MetalTerminalView.cellCount(400, cell: 400 / 44) == 44)
    }
}

#endif
