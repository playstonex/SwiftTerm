# AGENTS.md - Developer Guide for Agentic Coding

This file provides guidance for AI agents working on the Rayon (GoodTerm) codebase.

## Build Commands

### Opening the Project
```bash
# Always open the workspace, not individual .xcodeproj files
open App.xcworkspace
```

### Building from Command Line
```bash
# macOS app
xcodebuild -workspace App.xcworkspace -scheme Rayon build

# iOS app
xcodebuild -workspace App.xcworkspace -scheme mRayon build

# visionOS variant
xcodebuild -workspace App.xcworkspace -scheme vRayon build

# Build individual Foundation packages for isolated testing
xcodebuild -workspace App.xcworkspace -scheme RayonModule build
xcodebuild -workspace App.xcworkspace -scheme MachineStatus build
```

### Running Tests
```bash
# Run all tests for a scheme
xcodebuild -workspace App.xcworkspace -scheme RayonModule test

# Run a specific test class
xcodebuild -workspace App.xcworkspace -scheme RayonModule test \
  -only-testing:RayonModuleTests/CommandExecutorTests

# Run a specific test method
xcodebuild -workspace App.xcworkspace -scheme RayonModule test \
  -only-testing:RayonModuleTests/CommandExecutorTests/testContinuationSingleResume

# Run tests with code coverage
xcodebuild -workspace App.xcworkspace -scheme RayonModule test \
  -enableCodeCoverage YES
```

### Code Formatting
```bash
# Format all Swift code (Application/ and Foundation/ directories)
./Workflow/Scripts/fmt.sh
```

### Git Submodules
```bash
# Initialize/update external dependencies
./Workflow/Scripts/submodule.sh
```

## Project Structure

```
Application/           # Platform-specific app targets
├── Rayon/            # macOS menubar app (AppKit + SwiftUI)
└── mRayon/           # iOS/watchOS/visionOS app (SwiftUI)

Foundation/           # Shared Swift packages (business logic)
├── RayonModule/      # Core business logic hub
├── MachineStatus/    # Linux proc filesystem monitoring
├── MachineStatusView/ # Status monitoring UI components
├── DataSync/         # CloudKit synchronization
├── Keychain/         # Secure credential storage
└── ...               # Other shared modules

External/             # Third-party integrations (submodules)
├── NSRemoteShell/    # SSH/Terminal functionality (libssh2)
├── CodeMirrorUI/     # Code editor UI
└── XTerminalUI/      # Terminal interface
```

## Code Style Guidelines

### Swift Version
- **Swift 6.0** with strict concurrency checking enabled
- Use Swift Concurrency (`async`/`await`) over completion handlers where practical

### Naming Conventions
- **Types/Classes/Enums**: `PascalCase` (e.g., `RDMachine`, `ServerStatus`)
- **Functions/Methods**: `camelCase` (e.g., `update(to:)`, `syncAllDataToCloud`)
- **Properties/Variables**: `camelCase` (e.g., `remoteAddress`, `lastConnection`)
- **Constants**: `camelCase` with meaningful names (e.g., `outputSeparator`)
- **File Names**: Match the main type name (e.g., `RDMachine.swift`)

### Import Organization
```swift
import Foundation       // Standard library first
import Combine          //then reactive frameworks
import CloudKit         // then platform frameworks
import DataSync         // then project modules
import NSRemoteShell
```

### Type Declarations
- Use `public` for API that needs to be exposed across modules
- Use `internal` (default) for module-internal types
- Mark `@Published` properties as `public` if needed in views
- Use `final` on classes unless inheritance is required

### Error Handling
- Prefer `throws` for functions that can fail
- Use `try?` for optional error handling when appropriate
- Create custom error enums for domain-specific errors:
```swift
enum AIError: Error {
    case disabled
    case invalidResponse
    case networkError(Error)
}
```

### Concurrency Patterns
- Use `async`/`await` for asynchronous operations
- Use `Task` for spawning background work
- Use `@MainActor` for UI-related code when needed
- Use `DispatchQueue` for legacy async patterns where appropriate
- Always use `await` when calling async functions

### SwiftUI Patterns
- Separate views from view models
- Use `@Observable` (Swift 6) or `@Published` for observable state
- Pass dependencies through initializers
- Use descriptive view modifier chains

### Code Organization
- Group related functionality in extensions
- Use meaningful prefixes (e.g., `RDMachine` for Rayon Domain Machine)
- Keep files focused - one primary type per file is typical

### Documentation
- Use /// for public API documentation
- Add descriptive comments for complex logic
- Document parameters and return values for public methods

## Key Architectural Patterns

1. **MVVM**: SwiftUI views with separated view models
2. **Swift Package Modules**: Each Foundation component is independent
3. **Dependency Injection**: Through Swift Package Manager
4. **Platform-Specific UI**: Share business logic, adapt UI per platform

## Development Workflow

1. **Always open workspace**: `open App.xcworkspace`
2. **Format before commit**: Run `./Workflow/Scripts/fmt.sh`
3. **Build before submitting**: Verify build succeeds
4. **Test changes**: Run relevant tests

## Important Notes

- This project uses git submodules for external dependencies - run submodule script after clone
- The project is archived but accepts minor fixes
- Minimum macOS: 12.0, Minimum iOS: 15.0
- Platform: macOS (menubar app), iOS, watchOS, visionOS
