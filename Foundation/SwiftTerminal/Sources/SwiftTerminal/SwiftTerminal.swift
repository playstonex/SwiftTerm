//
//  SwiftTerminal.swift
//  SwiftTerminal
//
//  Public API exports for SwiftTerminal module
//

// Core adapter
@_exported import struct Foundation.CGSize

// Re-export the main types
public typealias TerminalSize = CGSize

// The main types are defined in their respective files:
// - SwiftTerminalAdapter: The callback-based adapter
// - SwiftTerminalView: Platform-specific terminal view (AppKit/UIKit)
// - STerminalView: SwiftUI wrapper
// - NativeTerminalView: XTerminal-compatible view wrapper
// - ThemeAdapter: Theme color conversion utilities
// - XTerminal: Protocol definition for backward compatibility
