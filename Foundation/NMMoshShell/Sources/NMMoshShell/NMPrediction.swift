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
public final class NMPrediction: @unchecked Sendable {

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

    private struct TerminalState: Equatable, Sendable {
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

        let predictedState = applyPredictionState(input: input, to: currentState).state
        let actualTerminalState = makeTerminalState(
            from: actualState,
            cursorRow: cursorPosition.0,
            cursorCol: cursorPosition.1,
            rows: currentState.rows,
            cols: currentState.cols
        )

        // Record for adaptive learning
        let record = PredictionRecord(
            input: input,
            predictedState: predictedState,
            actualState: actualTerminalState,
            timestamp: Date()
        )

        predictionHistory.append(record)
        if predictionHistory.count > maxHistorySize {
            predictionHistory.removeFirst()
        }
        currentState = actualTerminalState
    }

    /// Update current terminal state
    public func updateState(
        display: String,
        cursorRow: Int,
        cursorCol: Int
    ) {
        lock.lock()
        defer { lock.unlock() }

        currentState = makeTerminalState(
            from: display,
            cursorRow: cursorRow,
            cursorCol: cursorCol,
            rows: currentState.rows,
            cols: currentState.cols
        )
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

        for record in recent where record.actualState == record.predictedState {
            correct += 1
        }

        return Double(correct) / Double(recent.count)
    }

    private func applyPrediction(
        input: String,
        to state: TerminalState
    ) -> (String, (Int, Int)) {
        let predicted = applyPredictionState(input: input, to: state)
        return (
            predicted.displayString,
            (predicted.state.cursorRow, predicted.state.cursorCol)
        )
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

private extension NMPrediction {
    private func applyPredictionState(
        input: String,
        to state: TerminalState
    ) -> (displayString: String, state: TerminalState) {
        var updatedState = state.copy()
        var rendered = ""

        for char in input {
            switch char {
            case "\r":
                updatedState.cursorCol = 0
                rendered += "\r"
            case "\n":
                updatedState.cursorCol = 0
                if updatedState.cursorRow < updatedState.rows - 1 {
                    updatedState.cursorRow += 1
                }
                rendered += "\n"
            case "\u{08}", "\u{7F}":
                if updatedState.cursorCol > 0 {
                    updatedState.cursorCol -= 1
                    updatedState.buffer[updatedState.cursorRow][updatedState.cursorCol] = " "
                    rendered += "\u{08} \u{08}"
                }
            default:
                guard char.isPrintable else { continue }
                guard updatedState.cursorRow < updatedState.rows else { continue }

                if updatedState.cursorCol >= updatedState.cols {
                    updatedState.cursorCol = 0
                    if updatedState.cursorRow < updatedState.rows - 1 {
                        updatedState.cursorRow += 1
                    }
                }

                guard updatedState.cursorCol < updatedState.cols else { continue }

                updatedState.buffer[updatedState.cursorRow][updatedState.cursorCol] = char
                updatedState.cursorCol += 1
                rendered.append(char)
            }
        }

        return (rendered, updatedState)
    }

    private func makeTerminalState(
        from display: String,
        cursorRow: Int,
        cursorCol: Int,
        rows: Int,
        cols: Int
    ) -> TerminalState {
        var state = TerminalState(
            rows: rows,
            cols: cols,
            cursorRow: 0,
            cursorCol: 0,
            buffer: Array(repeating: Array(repeating: Character(" "), count: cols), count: rows)
        )

        var row = 0
        var col = 0

        for char in display {
            switch char {
            case "\r":
                col = 0
            case "\n":
                col = 0
                if row < rows - 1 {
                    row += 1
                }
            default:
                guard char.isPrintable else { continue }
                guard row < rows else { break }

                if col >= cols {
                    col = 0
                    if row < rows - 1 {
                        row += 1
                    }
                }

                guard col < cols else { continue }
                state.buffer[row][col] = char
                col += 1
            }
        }

        state.cursorRow = max(0, min(cursorRow, rows - 1))
        state.cursorCol = max(0, min(cursorCol, cols - 1))
        return state
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
