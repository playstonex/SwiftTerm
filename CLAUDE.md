# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rayon (aka GoodTerm) is a multi-platform server monitoring and remote terminal application for Linux machines. It supports macOS (menubar app), iOS, and watchOS. The project is currently archived but accepts minor fixes.

## Build System

This project uses **Xcode workspaces** with **Swift Package Manager** for modular dependencies. All development should be done through Xcode.

### Build Commands

```bash
# Open the workspace (recommended)
open App.xcworkspace

# Build macOS app from command line
xcodebuild -workspace App.xcworkspace -scheme Rayon build

# Build iOS app from command line
xcodebuild -workspace App.xcworkspace -scheme mRayon build

# Build visionOS variant
xcodebuild -workspace App.xcworkspace -scheme vRayon build

# Build individual Foundation packages for isolated testing
xcodebuild -workspace App.xcworkspace -scheme RayonModule build
xcodebuild -workspace App.xcworkspace -scheme MachineStatus build
```

### Testing

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

External dependencies use git submodules:

```bash
./Workflow/Scripts/submodule.sh
```

## Architecture

### Modular Structure

The project follows a strict modular architecture where each major component is a separate Swift Package:

```
Application/           # Platform-specific app targets
├── Rayon/            # macOS menubar app
└── mRayon/           # iOS/watchOS app (includes visionOS variant)

Foundation/           # Shared Swift packages (business logic)
├── RayonModule/      # Core business logic hub
├── MachineStatus/    # Linux proc filesystem monitoring
├── MachineStatusView/ # Status monitoring UI components
├── DataSync/         # CloudKit synchronization
├── Keychain/         # Secure credential storage
├── XMLCoder/         # XML parsing utilities
├── Colorful/         # Color utilities
├── PropertyWrapper/  # Custom property wrappers
├── SPIndicator/      # Toast notifications
├── StripedTextTable/ # Text table formatting
├── SymbolPicker/     # Symbol picker UI
├── SettingsUI/       # Common settings UI components
└── Premium/          # Premium features and automation

External/             # Third-party integrations
├── NSRemoteShell/    # SSH/Terminal functionality (libssh2)
├── CodeMirrorUI/     # Code editor UI
└── XTerminalUI/      # Terminal interface
```

### Key Architectural Patterns

1. **Swift Package Modules**: Each Foundation component is an independent Swift package with its own `Package.swift`
2. **MVVM**: SwiftUI views with separated view models
3. **Shared Business Logic**: All core functionality lives in Foundation/ packages, shared across platforms
4. **Dependency Injection**: Clear dependency flow through Swift Package Manager
5. **Platform-Specific UI**: Only UI code differs between macOS (AppKit + SwiftUI) and iOS (SwiftUI)

### Core Module: RayonModule

This is the central business logic hub (`Foundation/RayonModule/`). It provides:
- Authentication management
- Machine configuration
- Code snippets
- Terminal session management
- Shared data models

### External Dependencies

- **NSRemoteShell**: Handles SSH connections using libssh2
  - Located in `External/NSRemoteShell/`
  - Includes CSSH submodule for low-level SSH operations
  - Supports port forwarding and file transfers
- **CodeMirrorUI**: Code editor interface
- **XTerminalUI**: Terminal emulation UI

## Workspace Configuration

The `App.xcworkspace` file references all projects and packages. When working on this codebase:

1. Always open `App.xcworkspace`, not individual `.xcodeproj` files
2. The workspace resolves all Swift Package dependencies automatically
3. Each Foundation package has its own scheme for standalone testing

## Platform Support

- **macOS**: Rayon - NSApplicationDelegate-based menubar app
- **iOS**: mRayon - SwiftUI app
- **watchOS**: Companion extension via mRayon
- **visionOS**: vRayon - Variant of iOS app

## Code Style Guidelines

### Swift Version
- **Swift 6.0** with strict concurrency checking enabled
- Use Swift Concurrency (`async`/`await`) over completion handlers where practical

### Naming Conventions
- **Types/Classes/Enums**: `PascalCase` (e.g., `RDMachine`, `ServerStatus`)
- **Functions/Methods**: `camelCase` (e.g., `update(to:)`, `syncAllDataToCloud`)
- **Properties/Variables**: `camelCase` (e.g., `remoteAddress`, `lastConnection`)
- **File Names**: Match the main type name (e.g., `RDMachine.swift`)

### Import Organization
```swift
import Foundation       // Standard library first
import Combine          // then reactive frameworks
import CloudKit         // then platform frameworks
import DataSync         // then project modules
import NSRemoteShell
```

### Error Handling
- Prefer `throws` for functions that can fail
- Use `try?` for optional error handling when appropriate
- Create custom error enums for domain-specific errors

### Concurrency Patterns
- Use `async`/`await` for asynchronous operations
- Use `Task` for spawning background work
- Use `@MainActor` for UI-related code when needed
- Use `@Observable` (Swift 6) or `@Published` for observable state

## Data Persistence

- **Keychain**: Sensitive credentials (SSH keys, passwords)
- **CloudKit**: Machine configurations and snippets sync
- **Local storage**: App preferences and cached data

## Linux System Monitoring

The app monitors Linux servers by reading the proc filesystem:
- CPU, memory, disk usage
- NVIDIA GPU status
- Network information
- Process information

Data collection is implemented in `Foundation/MachineStatus/`.

## Development Notes

- Swift version: 6.0
- Minimum macOS: 12.0
- Minimum iOS: 15.0
- UI framework: SwiftUI (with AppKit for menubar on macOS)
- All apps share the same Foundation modules

## Schemes

The workspace includes schemes for:
- `Rayon` - macOS app
- `mRayon` - iOS app
- `vRayon` - visionOS app
- Individual Foundation packages (for testing components in isolation)
