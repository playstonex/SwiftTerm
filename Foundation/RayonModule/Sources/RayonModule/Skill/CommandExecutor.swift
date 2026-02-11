//
//  CommandExecutor.swift
//  RayonModule
//
//  Created by Claude on 2026/2/8.
//

import Foundation
import NSRemoteShell

/// Utility for executing commands and capturing exit codes
public class CommandExecutor {
    private static let exitCodeMarker = "TYPE_RAYON_EXIT_CODE:"

    /// Wrap a command to capture its exit code
    public static func wrapCommandWithExitCode(_ command: String) -> String {
        return " \(command); echo \"\n\(exitCodeMarker)$?\""
    }

    /// Parse exit code from command output
    /// - Returns: Tuple of (cleaned output, exit code). Exit code is nil if not found.
    public static func parseExitCode(from output: String) -> (output: String, exitCode: Int?) {
        var cleanOutput = output

        guard let range = output.range(of: exitCodeMarker, options: .backwards) else {
            return (output, nil)
        }

        let exitCodeStr = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let exitCode = Int(exitCodeStr)

        // Remove the exit code marker from output
        // Try to find the newline before the marker to remove it as well
        if range.lowerBound > output.startIndex {
            let beforeIndex = output.index(before: range.lowerBound)
            if output[beforeIndex] == "\n" {
                cleanOutput = String(output[..<beforeIndex])
            } else {
                cleanOutput = String(output[..<range.lowerBound])
            }
        } else {
            cleanOutput = String(output[..<range.lowerBound])
        }

        return (cleanOutput, exitCode)
    }

    /// Execute a command and capture its output and exit code
    public static func execute(
        _ command: String,
        shell: NSRemoteShell,
        timeout: TimeInterval = 30
    ) async throws -> (output: String, exitCode: Int?) {
        var output = ""

        // Wrap command to capture exit code
        let wrappedCommand = wrapCommandWithExitCode(command)

        return try await withCheckedThrowingContinuation { continuation in
            // Track whether we've already resumed to prevent double-resume
            var resumed = false
            let lock = NSLock()

            shell.beginExecute(
                withCommand: wrappedCommand,
                withTimeout: NSNumber(value: timeout),
                withOnCreate: {},
                withOutput: { chunk in
                    output.append(chunk)
                },
                withContinuationHandler: { [capturedContinuation = continuation] in
                    lock.lock()
                    defer { lock.unlock() }

                    guard !resumed else {
                        // Already resumed, return true to indicate termination
                        return true
                    }
                    resumed = true

                    // Parse exit code from output
                    let result = parseExitCode(from: output)

                    capturedContinuation.resume(returning: result)
                    return true
                }
            )
        }
    }
}
