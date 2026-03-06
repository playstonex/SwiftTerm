//
//  NMStateSync.swift
//  NMMoshShell
//
//  Mosh state synchronization protocol implementation.
//
//  Mosh uses a state synchronization protocol (SSP) to keep the terminal
//  display consistent between client and server. The protocol:
//  - Maintains a deterministic terminal emulator
//  - Transmits only changes (deltas)
//  - Acknowledges user input
//

import Foundation

/// Mosh state synchronization manager.
///
/// Implements the client-side of the SSP protocol.
public final class NMStateSync: Sendable {

    // MARK: - Types

    /// Terminal state vector - represents the current display state
    public struct TerminalState: Equatable, Sendable {
        public var rows: Int
        public var cols: Int
        public var cursorRow: Int
        public var cursorCol: Int
        public var cells: [Cell]

        public struct Cell: Equatable, Sendable {
            public var char: Character
            public var bold: Bool
            public var underline: Bool
            public var reverse: Bool
            public var foregroundColor: Color
            public var backgroundColor: Color

            public init(
                char: Character = " ",
                bold: Bool = false,
                underline: Bool = false,
                reverse: Bool = false,
                foregroundColor: Color = .default,
                backgroundColor: Color = .default
            ) {
                self.char = char
                self.bold = bold
                self.underline = underline
                self.reverse = reverse
                self.foregroundColor = foregroundColor
                self.backgroundColor = backgroundColor
            }
        }

        public enum Color: Equatable, Sendable {
            case default_
            case rgb(UInt8, UInt8, UInt8)
            case index(Int)

            public static let `default` = Color.default_
        }

        public init(rows: Int, cols: Int) {
            self.rows = rows
            self.cols = cols
            self.cursorRow = 0
            self.cursorCol = 0
            self.cells = Array(repeating: Cell(), count: rows * cols)
        }

        public func cell(at row: Int, col: Int) -> Cell {
            guard row >= 0, row < rows, col >= 0, col < cols else {
                return Cell()
            }
            return cells[row * cols + col]
        }

        public mutating func setCell(_ cell: Cell, at row: Int, col: Int) {
            guard row >= 0, row < rows, col >= 0, col < cols else { return }
            cells[row * cols + col] = cell
        }

        public mutating func setCursor(row: Int, col: Int) {
            cursorRow = max(0, min(row, rows - 1))
            cursorCol = max(0, min(col, cols - 1))
        }
    }

    /// State difference (delta) for transmission
    public struct StateDiff: Sendable {
        public var sequenceNumber: UInt64
        public var acknowledgments: [UInt64]
        public var displayChanges: [DisplayChange]
        public var timestamp: UInt64

        public init(
            sequenceNumber: UInt64 = 0,
            acknowledgments: [UInt64] = [],
            displayChanges: [DisplayChange] = [],
            timestamp: UInt64 = 0
        ) {
            self.sequenceNumber = sequenceNumber
            self.acknowledgments = acknowledgments
            self.displayChanges = displayChanges
            self.timestamp = timestamp
        }
    }

    /// Display change types
    public enum DisplayChange: Sendable {
        case write(row: Int, col: Int, string: String)
        case clear
        case scrollUp(lines: Int)
        case scrollDown(lines: Int)
        case setCursor(row: Int, col: Int)
        case setAttribute(bold: Bool?, underline: Bool?, reverse: Bool?)
        case setColor(foreground: TerminalState.Color?, background: TerminalState.Color?)
    }

    // MARK: - Properties

    private let lock = NSLock()
    private var currentState: TerminalState
    private var expectedSequenceNumber: UInt64 = 0
    private var lastServerSequence: UInt64 = 0
    private var pendingAcknowledgments: Set<UInt64> = []

    public var terminalState: TerminalState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }

    // MARK: - Initialization

    public init(rows: Int = 24, cols: Int = 80) {
        self.currentState = TerminalState(rows: rows, cols: cols)
    }

    // MARK: - Public Methods

    /// Apply incoming state diff from server
    public func applyDiff(_ diff: StateDiff) {
        lock.lock()
        defer { lock.unlock() }

        // Validate sequence number
        guard diff.sequenceNumber >= lastServerSequence else {
            // Out of order or duplicate, ignore
            return
        }

        lastServerSequence = diff.sequenceNumber

        // Apply changes
        for change in diff.displayChanges {
            applyChange(change)
        }

        // Process acknowledgments
        for ack in diff.acknowledgments {
            pendingAcknowledgments.remove(ack)
        }
    }

    /// Create state diff for local changes (to send to server)
    public func createDiff(for userInput: String) -> StateDiff {
        lock.lock()
        defer { lock.unlock() }

        expectedSequenceNumber += 1
        pendingAcknowledgments.insert(expectedSequenceNumber)

        return StateDiff(
            sequenceNumber: expectedSequenceNumber,
            acknowledgments: Array(pendingAcknowledgments),
            displayChanges: [],
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
        )
    }

    /// Resize terminal
    public func resize(rows: Int, cols: Int) {
        lock.lock()
        defer { lock.unlock() }

        var newState = TerminalState(rows: rows, cols: cols)

        // Copy over existing content where possible
        let minRows = min(currentState.rows, rows)
        let minCols = min(currentState.cols, cols)

        for row in 0..<minRows {
            for col in 0..<minCols {
                newState.setCell(currentState.cell(at: row, col: col), at: row, col: col)
            }
        }

        newState.setCursor(row: currentState.cursorRow, col: currentState.cursorCol)
        currentState = newState
    }

    // MARK: - Private Methods

    private func applyChange(_ change: DisplayChange) {
        switch change {
        case .write(let row, let col, let string):
            applyWrite(at: row, col: col, string: string)
        case .clear:
            currentState = TerminalState(rows: currentState.rows, cols: currentState.cols)
        case .scrollUp(let lines):
            applyScroll(lines: lines, direction: .up)
        case .scrollDown(let lines):
            applyScroll(lines: lines, direction: .down)
        case .setCursor(let row, let col):
            currentState.setCursor(row: row, col: col)
        case .setAttribute, .setColor:
            // TODO: Implement attribute changes
            break
        }
    }

    private func applyWrite(at row: Int, col: Int, string: String) {
        var currentCol = col
        for char in string {
            if currentCol < currentState.cols {
                var cell = currentState.cell(at: row, col: currentCol)
                cell.char = char
                currentState.setCell(cell, at: row, col: currentCol)
                currentCol += 1
            }
        }
    }

    private enum ScrollDirection {
        case up, down
    }

    private func applyScroll(lines: Int, direction: ScrollDirection) {
        let rowCount = currentState.rows
        let colCount = currentState.cols
        var newCells = Array(repeating: TerminalState.Cell(), count: rowCount * colCount)

        for row in 0..<rowCount {
            let sourceRow: Int
            switch direction {
            case .up:
                sourceRow = row + lines
            case .down:
                sourceRow = row - lines
            }

            if sourceRow >= 0, sourceRow < rowCount {
                // Copy row
                for col in 0..<colCount {
                    newCells[row * colCount + col] = currentState.cell(at: sourceRow, col: col)
                }
            }
        }

        currentState.cells = newCells
    }
}
