//
//  NMPrediction.swift
//  NMMoshShell
//
//  Local echo prediction for Mosh client.
//
//  Mosh predicts the result of user input locally to provide
//  instant feedback even on high-latency connections.
//

import Foundation

/// Mosh local echo prediction engine.
public final class NMPrediction: Sendable {

    // MARK: - Types

    public enum Mode: String, Sendable {
        case adaptive = "adaptive"
        case always = "always"
        case never = "never"
        case experimental = "experimental"
    }

    /// Prediction result with confidence
    public struct Prediction {
        public let displayString: String
        public let cursorPosition: (row: Int, col: Int)
        public let confidence: Double // 0.0 to 1.0

        public init(displayString: String, cursorPosition: (Int, Int), confidence: Double) {
            self.displayString = displayString
            self.cursorPosition = cursorPosition
            self.confidence = confidence
        }
    }

    // MARK: - Properties

    private let lock = NSLock()
    private var _mode: Mode = .adaptive
    private var currentState: TerminalState
    private var predictionHistory: [PredictionRecord] = []
    private let maxHistorySize = 100

    // MARK: - Terminal State

    private struct TerminalState {
        var rows: Int
        var cols: Int
        var cursorRow: Int
        var cursorCol: Int
        var buffer: [[Character]]

        func copy() -> TerminalState {
            let newBuffer = buffer.map { $0 }
            return TerminalState(
                rows: rows,
                cols: cols,
                cursorRow: cursorRow,
                cursorCol: cursorCol,
                buffer: newBuffer
            )
        }
    }

    private struct PredictionRecord {
        let input: String
        let predictedState: TerminalState
        let actualState: TerminalState?
        let timestamp: Date
    }

    // MARK: - Initialization

    public init(rows: Int = 24, cols: Int = 80, mode: Mode = .adaptive) {
        self._mode = mode
        self.currentState = TerminalState(
            rows: rows,
            cols: cols,
            cursorRow: 0,
            cursorCol: 0,
            buffer: Array(repeating: Array(repeating: Character(" "), count: cols), count: rows)
        )
    }

    // MARK: - Public Methods

    /// Set prediction mode
    public func setMode(_ mode: Mode) {
        lock.lock()
        defer { lock.unlock() }
        self._mode = mode
    }

    /// Predict the result of user input
    public func predict(input: String) -> Prediction {
        lock.lock()
        let stateCopy = currentState.copy()
        let currentMode = _mode
        lock.unlock()

        // Determine if we should predict
        guard shouldPredict(input: input, mode: currentMode) else {
            return Prediction(
                displayString: "",
                cursorPosition: (stateCopy.cursorRow, stateCopy.cursorCol),
                confidence: 0
            )
        }

        // Apply prediction
        let (predictedString, newPos) = applyPrediction(input: input, to: stateCopy)

        return Prediction(
            displayString: predictedString,
            cursorPosition: newPos,
            confidence: confidenceFor(input: input, mode: currentMode)
        )
    }

    /// Confirm prediction with actual server state
    public func confirmPrediction(
        input: String,
        actualState: String,
        cursorPosition: (Int, Int)
    ) {
        lock.lock()
        defer { lock.unlock() }

        // Record for adaptive learning
        let record = PredictionRecord(
            input: input,
            predictedState: currentState.copy(),
            actualState: currentState.copy(), // TODO: Parse actual state
            timestamp: Date()
        )

        predictionHistory.append(record)
        if predictionHistory.count > maxHistorySize {
            predictionHistory.removeFirst()
        }

        // Update state with actual
        // TODO: Parse and apply actual state
    }

    /// Update current terminal state
    public func updateState(
        display: String,
        cursorRow: Int,
        cursorCol: Int
    ) {
        lock.lock()
        defer { lock.unlock() }

        // TODO: Parse display into buffer
        currentState.cursorRow = cursorRow
        currentState.cursorCol = cursorCol
    }

    /// Resize terminal
    public func resize(rows: Int, cols: Int) {
        lock.lock()
        defer { lock.unlock() }

        currentState.rows = rows
        currentState.cols = cols
        currentState.buffer = Array(
            repeating: Array(repeating: Character(" "), count: cols),
            count: rows
        )
    }

    // MARK: - Private Methods

    private func shouldPredict(input: String, mode: Mode) -> Bool {
        switch mode {
        case .never:
            return false
        case .always:
            return true
        case .experimental:
            return true // More aggressive
        case .adaptive:
            // Based on history accuracy
            return shouldPredictAdaptive(input: input)
        }
    }

    private func shouldPredictAdaptive(input: String) -> Bool {
        // Check prediction history for similar inputs
        let recentAccuracy = calculateRecentAccuracy()

        // Only predict if we've been reasonably accurate
        return recentAccuracy > 0.7
    }

    private func calculateRecentAccuracy() -> Double {
        guard predictionHistory.count > 10 else { return 0.5 }

        let recent = predictionHistory.suffix(20)
        var correct = 0

        for record in recent {
            // Compare predicted vs actual
            if record.actualState != nil {
                // TODO: Implement proper comparison
                correct += 1
            }
        }

        return Double(correct) / Double(recent.count)
    }

    private func applyPrediction(
        input: String,
        to state: TerminalState
    ) -> (String, (Int, Int)) {
        var result = ""
        var row = state.cursorRow
        var col = state.cursorCol
        var buffer = state.buffer

        for char in input {
            // Handle special characters
            if char == "\r" || char == "\n" {
                result += "\r\n"
                row = min(row + 1, state.rows - 1)
                col = 0
            } else if char == "\u{08}" || char == "\u{7F}" {
                // Backspace
                if col > 0 {
                    col -= 1
                    result += "\u{08} \u{08}" // Backspace, space, backspace
                }
            } else if char.isPrintable {
                // Regular printable character
                if col < state.cols {
                    result.append(char)
                    col += 1
                }

                // Update buffer
                if row < state.rows && col < state.cols {
                    buffer[row][col] = char
                }
            }

            // Handle cursor position wrapping
            if col >= state.cols {
                col = 0
                row = min(row + 1, state.rows - 1)
            }
        }

        return (result, (row, col))
    }

    private func confidenceFor(input: String, mode: Mode) -> Double {
        switch mode {
        case .never:
            return 0
        case .always:
            return 0.9
        case .experimental:
            return 0.5 // Lower confidence but more aggressive
        case .adaptive:
            // Base on history
            return min(0.95, calculateRecentAccuracy() + 0.1)
        }
    }
}

extension Character {
    var isPrintable: Bool {
        guard isASCII else { return true } // Allow non-ASCII printable
        let asciiValue = asciiValue
        return asciiValue >= 32 && asciiValue <= 126
    }

    private var asciiValue: UInt32 {
        guard let scalar = unicodeScalars.first else { return 0 }
        return scalar.value
    }

    private var isASCII: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.value < 128
    }
}
