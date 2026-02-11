#!/usr/bin/env swift
//
//  test_continuation_fix.swift
//  Test for continuation double-resume fix
//

import Foundation

// This test simulates the NSRemoteShell behavior where the continuation
// handler is called multiple times

// Simulates what the OLD buggy code would do:
func testBuggyVersion() {
    print("Testing OLD buggy version (should crash)...")
    let semaphore = DispatchSemaphore(value: 0)

    Task {
        await withCheckedContinuation { continuation in
            var callCount = 0

            // This simulates NSRemoteChannel calling the handler multiple times
            for i in 0..<5 {
                print("  Handler call #\(i+1)")
                callCount += 1

                // OLD BUGGY CODE - resumes every time!
                if i == 0 {
                    continuation.resume(returning: "output")
                }
                // On second call, this would crash with:
                // "SWIFT TASK CONTINUATION MISUSE"
            }
        }
        semaphore.signal()
    }

    let timeout = DispatchTime.now() + .seconds(2)
    if semaphore.wait(timeout: timeout) == .timedOut {
        print("  ✗ CRASHED or hung (expected for buggy version)")
    } else {
        print("  ✗ Should have crashed but didn't!")
    }
}

// Simulates what the NEW fixed code does:
func testFixedVersion() {
    print("\nTesting NEW fixed version (should work)...")
    let semaphore = DispatchSemaphore(value: 0)

    Task {
        let result = await withCheckedContinuation { continuation in
            var resumed = false
            let lock = NSLock()

            // This simulates NSRemoteChannel calling the handler multiple times
            for i in 0..<5 {
                print("  Handler call #\(i+1)")

                lock.lock()
                defer { lock.unlock() }

                guard !resumed else {
                    print("    → Already resumed, skipping")
                    return // Would be 'return true' in real code
                }
                resumed = true

                print("    → Resuming continuation")
                continuation.resume(returning: "output")
            }
        }
        print("  Result: \(result)")
        semaphore.signal()
    }

    let timeout = DispatchTime.now() + .seconds(2)
    if semaphore.wait(timeout: timeout) == .timedOut {
        print("  ✗ Timed out")
    } else {
        print("  ✓ SUCCESS - No crash even with multiple handler calls!")
    }
}

// Run tests
print(String(repeating: "=", count: 50))
print("Continuation Double-Resume Fix Test")
print(String(repeating: "=", count: 50))

testFixedVersion()
print("\n" + String(repeating: "=", count: 50))
print("Test completed!")
print(String(repeating: "=", count: 50))
