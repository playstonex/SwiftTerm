//
//  SessionLifecycleCoordinator.swift
//  mRayon
//
//  Created by OpenCode on 2026/4/18.
//

import BackgroundTasks
import Foundation
import SwiftUI
import UIKit

@MainActor
final class SessionLifecycleCoordinator: ObservableObject {
    static let shared = SessionLifecycleCoordinator()

    private var activeBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundEnteredAt: Date?
    private let terminalManager = TerminalManager.shared
    private var backgroundObservers: [NSObjectProtocol] = []
    private var shutdownGuardTask: Task<Void, Never>?

    static let refreshTaskID = "com.playstone.mRayon.refresh"
    static let processingTaskID = "com.playstone.mRayon.processing"

    private init() {
        let center = NotificationCenter.default
        backgroundObservers = [
            center.addObserver(
                forName: UIScene.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleDidEnterBackground()
            },
            center.addObserver(
                forName: UIScene.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleWillEnterForeground()
            },
            center.addObserver(
                forName: UIScene.didActivateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleDidActivate()
            }
        ]

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskID,
            using: nil
        ) { task in
            Task { @MainActor [weak self] in
                self?.handleAppRefresh(task as! BGAppRefreshTask)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskID,
            using: nil
        ) { task in
            Task { @MainActor [weak self] in
                self?.handleProcessing(task as! BGProcessingTask)
            }
        }
    }

    private func handleDidEnterBackground() {
        debugPrint("\(self) \(#function)")
        backgroundEnteredAt = Date()
        shutdownGuardTask?.cancel()

        if activeBackgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(activeBackgroundTaskID)
        }

        activeBackgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "com.playstone.mRayon.sessionKeepalive"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.beginGracefulShutdown()
                self?.endBackgroundTaskIfNeeded()
            }
        }

        for context in terminalManager.terminals where !context.closed {
            context.preserveForBackground()
        }

        let remaining = UIApplication.shared.backgroundTimeRemaining
        let guardDelay = max(remaining - 5, 0)
        shutdownGuardTask = Task { [weak self] in
            guard guardDelay.isFinite, guardDelay > 0 else { return }
            let cappedDelay = min(guardDelay, 600.0)
            try? await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.beginGracefulShutdown()
            }
        }
    }

    private func handleWillEnterForeground() {
        debugPrint("\(self) \(#function)")
        shutdownGuardTask?.cancel()
        shutdownGuardTask = nil
        endBackgroundTaskIfNeeded()

        let backgroundDuration = backgroundEnteredAt.map { Date().timeIntervalSince($0) } ?? 0

        for context in terminalManager.terminals where context.closed {
            if backgroundDuration < 30 {
                context.shell.explicitRequestStatusPickup()
                continue
            }

            if context.machine.connectionType == .mosh {
                debugPrint("\(self) waiting for mosh auto reconnect \(context.id)")
            } else {
                context.reconnectInBackground()
            }
        }

        backgroundEnteredAt = nil
    }

    private func handleDidActivate() {
        debugPrint("\(self) \(#function) pending Live Activity updates placeholder")
    }

    private func beginGracefulShutdown() {
        debugPrint("\(self) \(#function)")
        for context in terminalManager.terminals where !context.closed {
            context.processShutdown(exitFromShell: false)
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard activeBackgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(activeBackgroundTaskID)
        activeBackgroundTaskID = .invalid
    }

    // MARK: - BGTaskScheduler

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleNextAppRefresh()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        let activeTerminals = terminalManager.terminals.filter { !$0.closed }
        guard !activeTerminals.isEmpty else {
            task.setTaskCompleted(success: true)
            return
        }

        Task { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: true)
                return
            }

            for context in self.terminalManager.terminals {
                if context.closed {
                    let sid = context.id
                    Task { @MainActor in
                        LiveActivityBridge.shared.updateSessionStatus(
                            sessionId: sid,
                            status: .disconnected
                        )
                    }
                    if !context.moshModeActive {
                        context.reconnectInBackground()
                    }
                } else {
                    context.shell.explicitRequestStatusPickup()
                    let sid = context.id
                    Task { @MainActor in
                        LiveActivityBridge.shared.updateSessionStatus(
                            sessionId: sid,
                            status: .connected
                        )
                    }
                }
            }

            try? await Task.sleep(nanoseconds: 5_000_000_000)
            task.setTaskCompleted(success: true)
        }
    }

    private func handleProcessing(_ task: BGProcessingTask) {
        scheduleNextProcessingTask()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: true)
                return
            }

            for context in self.terminalManager.terminals where !context.closed {
                context.preserveForBackground()
            }

            try? await Task.sleep(nanoseconds: 10_000_000_000)
            task.setTaskCompleted(success: true)
        }
    }

    func scheduleNextAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            debugPrint("[SessionLifecycle] failed to schedule app refresh: \(error)")
        }
    }

    private func scheduleNextProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            debugPrint("[SessionLifecycle] failed to schedule processing task: \(error)")
        }
    }

    deinit {
        shutdownGuardTask?.cancel()
        backgroundObservers.forEach(NotificationCenter.default.removeObserver)
        if activeBackgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(activeBackgroundTaskID)
            activeBackgroundTaskID = .invalid
        }
    }
}
