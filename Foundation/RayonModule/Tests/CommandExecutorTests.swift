//
//  CommandExecutorTests.swift
//  RayonModule Tests
//
//  Created for testing continuation double-resume fix
//

import XCTest
@testable import RayonModule

// Mock NSRemoteShell for testing
class MockNSRemoteShell {
    var callCount = 0
    var continuationCallCount = 0
    var maxContinuationCalls: Int = 3

    func beginExecute(
        withCommand command: String,
        withTimeout: NSNumber,
        withOnCreate: @escaping () -> Void,
        withOutput: @escaping (String) -> Void,
        withContinuationHandler: (() -> Bool)?
    ) {
        withOnCreate()

        // Simulate some output
        withOutput("/usr/bin/sudo\n")
        withOutput("TYPE_RAYON_EXIT_CODE:0\n")

        // Simulate the continuation being called multiple times
        // This mimics what NSRemoteChannel does
        if let handler = withContinuationHandler {
            for _ in 0..<maxContinuationCalls {
                continuationCallCount += 1
                let shouldContinue = handler()
                if !shouldContinue {
                    break
                }
            }
        }
    }
}

// Test to verify continuation is only resumed once
final class CommandExecutorTests: XCTestCase {
    func testContinuationSingleResume() async throws {
        let mockShell = MockNSRemoteShell()
        mockShell.maxContinuationCalls = 5 // Simulate multiple calls

        // This should not crash even though continuation handler is called multiple times
        do {
            let result = try await CommandExecutor.execute(
                "which sudo",
                shell: mockShell,
                timeout: 5
            )

            // Verify we got output
            XCTAssertTrue(result.output.contains("sudo"))
            XCTAssertEqual(result.exitCode, 0)

            // Verify the continuation handler was called multiple times
            // (this simulates the real NSRemoteShell behavior)
            XCTAssertGreaterThan(mockShell.continuationCallCount, 1,
                                "Continuation handler should be called multiple times by NSRemoteShell")
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }

    func testContinuationWithQuickExit() async throws {
        let mockShell = MockNSRemoteShell()
        mockShell.maxContinuationCalls = 1 // Simulate quick exit

        do {
            let result = try await CommandExecutor.execute(
                "echo test",
                shell: mockShell,
                timeout: 5
            )

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertEqual(mockShell.continuationCallCount, 1)
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }

    // Test that verifies the fix prevents double-resume crashes
    // The old code would crash with "SWIFT TASK CONTINUATION MISUSE"
    // The new code should handle multiple calls gracefully
    func testMultipleContinuationCallsDoNotCrash() async {
        let mockShell = MockNSRemoteShell()
        mockShell.maxContinuationCalls = 10 // Many calls

        // This test passes if it doesn't crash
        do {
            _ = try await CommandExecutor.execute(
                "test command",
                shell: mockShell,
                timeout: 5
            )
        } catch {
            // Error is OK, crash is not
        }

        // If we get here without crashing, the fix works
        XCTAssertTrue(true)
    }
}
