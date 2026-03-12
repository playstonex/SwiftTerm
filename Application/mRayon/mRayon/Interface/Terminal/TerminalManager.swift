//
//  TerminalTabView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import Combine
import RayonModule
import SwiftUI

@MainActor
final class TerminalManager: ObservableObject {
    static let shared = TerminalManager()

    private init() {}

    @Published var terminals: [TerminalContext] = []

    private func shutdown(_ terminal: TerminalContext) {
        terminal.processShutdown()
        terminal.destroyedSession = true
    }

    func begin(for machineId: RDMachine.ID, force: Bool = false) {
        debugPrint("\(self) \(#function) \(machineId)")
        if !force {
            for terminal in terminals where terminal.machine.id == machineId {
                UIBridge.requiresConfirmation(
                    message: "Another terminal for this machine is already running"
                ) { confirmed in
                    guard confirmed else {
                        return
                    }
                    Task { @MainActor in
                        self.begin(for: machineId, force: true)
                    }
                }
                return
            }
        }
        let machine = RayonStore.shared.machineGroup[machineId]
        guard machine.isNotPlaceholder() else {
            UIBridge.presentError(with: "Unknown Bad Data")
            return
        }
        let object = TerminalContext(machine: machine)
        RayonStore.shared.storeRecentIfNeeded(from: machineId)
        terminals.append(object)
    }

    func begin(for command: SSHCommandReader, force: Bool = false) {
        debugPrint("\(self) \(#function) \(command.command)")
        if !force {
            for terminal in terminals where terminal.command == command {
                UIBridge.requiresConfirmation(
                    message: "Another terminal for this command is already running"
                ) { confirmed in
                    guard confirmed else {
                        return
                    }
                    Task { @MainActor in
                        self.begin(for: command, force: true)
                    }
                }
                return
            }
        }
        let object = TerminalContext(command: command)
        RayonStore.shared.storeRecentIfNeeded(from: command)
        terminals.append(object)
    }

    func end(for contextId: UUID) {
        debugPrint("\(self) \(#function) \(contextId)")
        guard let index = terminals.firstIndex(where: { $0.id == contextId }) else { return }
        let term = terminals.remove(at: index)
        shutdown(term)
    }
}
