//
//  LiveActivityBridge.swift
//  mRayon
//
//  Bridges TerminalContext events to ActivityKit Live Activity updates.
//

import ActivityKit
import Foundation
import RayonLiveActivity
import UIKit

@MainActor
final class LiveActivityBridge {
    static let shared = LiveActivityBridge()

    private var currentActivity: Activity<TerminalSessionAttributes>?
    private var trackedSessions: [UUID: TrackedSession] = [:]

    private struct TrackedSession {
        var status: TerminalSessionAttributes.ContentState.Status = .idle
        var host: String = ""
        var transport: String = "SSH"
        var currentCommand: String?
        var commandStartedAt: Date?
        var lastLineSnippet: String?
        var unreadBellCount: Int = 0
    }

    private init() {}

    func startTracking(context: TerminalContext) {
        let transport = context.moshModeActive ? "Mosh" : "SSH"
        trackedSessions[context.id] = TrackedSession(
            status: .idle,
            host: context.machine.name.isEmpty ? context.machine.remoteAddress : context.machine.name,
            transport: transport
        )
        updateActivity()
    }

    func stopTracking(sessionId: UUID) {
        trackedSessions.removeValue(forKey: sessionId)
        if trackedSessions.isEmpty {
            endAllActivities()
        } else {
            updateActivity()
        }
    }

    func updateSessionStatus(sessionId: UUID, status: TerminalSessionAttributes.ContentState.Status) {
        guard trackedSessions[sessionId] != nil else { return }
        trackedSessions[sessionId]?.status = status
        updateActivity()
    }

    func updateCommandStarted(sessionId: UUID, command: String) {
        guard trackedSessions[sessionId] != nil else { return }
        trackedSessions[sessionId]?.currentCommand = command
        trackedSessions[sessionId]?.commandStartedAt = Date()
        trackedSessions[sessionId]?.status = .running
        updateActivity()
    }

    func updateCommandFinished(sessionId: UUID) {
        guard trackedSessions[sessionId] != nil else { return }
        trackedSessions[sessionId]?.currentCommand = nil
        trackedSessions[sessionId]?.commandStartedAt = nil
        trackedSessions[sessionId]?.status = .connected
        updateActivity()
    }

    func updateSnippet(sessionId: UUID, snippet: String) {
        guard trackedSessions[sessionId] != nil else { return }
        trackedSessions[sessionId]?.lastLineSnippet = String(snippet.prefix(60))
        updateActivity()
    }

    func incrementBell(sessionId: UUID) {
        guard trackedSessions[sessionId] != nil else { return }
        trackedSessions[sessionId]?.unreadBellCount += 1
        updateActivity()
    }

    func endAllActivities() {
        Task {
            await currentActivity?.end(
                using: nil,
                dismissalPolicy: .immediate
            )
            currentActivity = nil
        }
    }

    private func updateActivity() {
        guard !trackedSessions.isEmpty else {
            endAllActivities()
            return
        }

        let primary = selectPrimarySession()
        guard let session = trackedSessions[primary.id] else { return }

        let contentState = TerminalSessionAttributes.ContentState(
            status: session.status,
            host: session.host,
            transport: session.transport,
            currentCommand: session.currentCommand,
            commandStartedAt: session.commandStartedAt,
            lastLineSnippet: session.lastLineSnippet,
            unreadBellCount: trackedSessions.values.reduce(0) { $0 + $1.unreadBellCount }
        )

        if let activity = currentActivity {
            Task {
                await activity.update(
                    ActivityContent(
                        state: contentState,
                        staleDate: nil
                    )
                )
            }
        } else {
            requestActivity(
                sessionId: primary.id,
                machineName: primary.name,
                contentState: contentState
            )
        }
    }

    private func requestActivity(
        sessionId: UUID,
        machineName: String,
        contentState: TerminalSessionAttributes.ContentState
    ) {
        let attributes = TerminalSessionAttributes(
            sessionID: sessionId,
            machineName: machineName
        )
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: contentState, staleDate: nil)
            )
            currentActivity = activity
            debugPrint("[LiveActivityBridge] started activity \(activity.id)")
        } catch {
            debugPrint("[LiveActivityBridge] failed to request activity: \(error)")
        }
    }

    private func selectPrimarySession() -> (id: UUID, name: String) {
        let priorityOrder: [TerminalSessionAttributes.ContentState.Status] = [
            .running, .connected, .reconnecting, .idle, .disconnected,
        ]
        for status in priorityOrder {
            for (id, session) in trackedSessions where session.status == status {
                return (id, session.host)
            }
        }
        let first = trackedSessions.first!
        return (first.key, first.value.host)
    }
}
