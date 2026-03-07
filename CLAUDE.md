# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

```bash
# Build the package
swift build

# Run tests
swift test

# Run tests with full esctest compliance suite (clone first)
make clone-esctest
swift test

# Run a specific test
swift test --filter TestClassName

# Run the fuzzer (requires special toolchain, see Makefile)
make build-fuzzer
make run-fuzzer

# Generate documentation
swift package generate-documentation
```

## Project Architecture

SwiftTerm is a VT100/Xterm terminal emulator library with a platform-agnostic engine and platform-specific frontends.

### Core Components

**Engine (Sources/SwiftTerm/)** - Platform-agnostic terminal emulation:
- `Terminal.swift` - Core terminal state machine and escape sequence handling
- `Buffer.swift`, `BufferLine.swift`, `BufferSet.swift` - Terminal buffer management
- `EscapeSequenceParser.swift` - Parses VT100/xterm escape sequences
- `LocalProcess.swift` - Runs local Unix processes in a pseudo-terminal (macOS/Linux only)
- `HeadlessTerminal.swift` - Headless terminal for scripting/testing
- `Pty.swift` - Pseudo-terminal handling
- `SearchService.swift`, `SelectionService.swift` - Search and selection functionality
- `SixelDcsHandler.swift`, `KittyGraphics.swift` - Graphics protocol support

**Platform Frontends** - UI implementations under `Sources/SwiftTerm/`:
- `Mac/` - macOS AppKit NSView implementation (`MacTerminalView.swift`, `MacLocalTerminalView.swift`)
- `iOS/` - iOS UIKit UIView implementation (`iOSTerminalView.swift`, `SwiftUITerminalView.swift`)
- `Apple/` - Shared code between macOS and iOS (`AppleTerminalView.swift`, rendering utilities)

### Key Protocols

- `TerminalViewDelegate` (Apple/TerminalViewDelegate.swift) - Connect `TerminalView` to data sources (local process, SSH, etc.). Implement `send(source:data:)` to write to your backend, and call `terminal.feed(buffer:)` to inject data.

- `LocalProcessDelegate` (LocalProcess.swift) - Receive events from `LocalProcess` for process lifecycle and I/O.

- `TerminalDelegate` - Internal delegate for `Terminal` class events.

### Sample Apps

`TerminalApp/` contains Xcode projects for testing:
- `MacTerminal.xcodeproj` - macOS terminal app with local shell
- `iOSTerminal.xcodeproj` - iOS SSH client demo (uses swift-nio-ssh)

## Platform Compilation

The Package.swift conditionally excludes Apple-specific code on Linux/Windows:
```swift
#if os(Linux) || os(Windows)
let platformExcludes = ["Apple", "Mac", "iOS"]
#endif
```

## Testing

Tests are in `Tests/SwiftTermTests/`. Key test files:
- `ParserTests.swift` - Escape sequence parsing
- `TerminalCoreTests.swift` - Core terminal functionality
- `ReflowTests.swift` - Terminal resize/reflow behavior
- Various protocol-specific tests (Kitty, Sixel, etc.)

For comprehensive terminal compliance testing, clone esctest:
```bash
make clone-esctest
```
