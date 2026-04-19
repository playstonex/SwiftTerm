//
//  TerminalSessionAttributes.swift
//  RayonLiveActivity
//
//  Shared ActivityAttributes for Dynamic Island terminal session tracking.
//

import ActivityKit
import Foundation

public struct TerminalSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public enum Status: String, Codable, CaseIterable {
            case connected
            case reconnecting
            case disconnected
            case idle
            case running
        }

        public var status: Status
        public var host: String
        public var transport: String
        public var currentCommand: String?
        public var commandStartedAt: Date?
        public var lastLineSnippet: String?
        public var unreadBellCount: Int

        public init(
            status: Status = .idle,
            host: String = "",
            transport: String = "SSH",
            currentCommand: String? = nil,
            commandStartedAt: Date? = nil,
            lastLineSnippet: String? = nil,
            unreadBellCount: Int = 0
        ) {
            self.status = status
            self.host = host
            self.transport = transport
            self.currentCommand = currentCommand
            self.commandStartedAt = commandStartedAt
            self.lastLineSnippet = lastLineSnippet
            self.unreadBellCount = unreadBellCount
        }
    }

    public let sessionID: UUID
    public let machineName: String
    public let openedAt: Date

    public init(sessionID: UUID, machineName: String, openedAt: Date = Date()) {
        self.sessionID = sessionID
        self.machineName = machineName
        self.openedAt = openedAt
    }
}

extension TerminalSessionAttributes.ContentState.Status {
    public var systemImageName: String {
        switch self {
        case .connected: return "terminal.fill"
        case .reconnecting: return "arrow.trianglehead.2.clockwise"
        case .disconnected: return "terminal"
        case .idle: return "terminal"
        case .running: return "terminal.fill"
        }
    }

    public var statusColor: String {
        switch self {
        case .connected: return "green"
        case .reconnecting: return "orange"
        case .disconnected: return "red"
        case .idle: return "gray"
        case .running: return "green"
        }
    }
}
