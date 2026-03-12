//
//  TerminalManager.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/10.
//

import Combine
import Foundation
import RayonModule

@MainActor
final class TerminalManager: ObservableObject {
    static let shared = TerminalManager()
    private init() {}

    @Published var sessionContexts: [Context] = []

    private func shutdown(_ context: Context) {
        context.processShutdown()
        context.shell.destroyPermanently()
    }

    func createSession(withMachineObject machine: RDMachine, force: Bool = false) {
        let sessionExists = sessionContexts.contains { $0.machine.id == machine.id }
        if sessionExists, !force {
            UIBridge.requiresConfirmation(message: "A session for \(machine.name) is already in place, are you sure to open another?") { confirmed in
                if confirmed {
                    Task { @MainActor in
                        self.createSession(withMachineObject: machine, force: true)
                    }
                }
            }
            return
        }
        let context = Context(machine: machine)
        sessionContexts.append(context)
        RayonStore.shared.storeRecentIfNeeded(from: machine.id)
    }

    func createSession(withMachineID machineId: RDMachine.ID) {
        let machine = RayonStore.shared.machineGroup[machineId]
        guard machine.isNotPlaceholder() else {
            UIBridge.presentError(with: "Malformed application memory")
            return
        }
        createSession(withMachineObject: machine)
    }

    func createSession(withCommand command: SSHCommandReader) {
        let context = Context(command: command)
        sessionContexts.append(context)
        RayonStore.shared.storeRecentIfNeeded(from: command)
    }

    func sessionExists(for machine: RDMachine.ID) -> Bool {
        sessionContexts.contains { $0.machine.id == machine }
    }

    func sessionAlive(forMachine machineId: RDMachine.ID) -> Bool {
        !(
            sessionContexts
                .first { $0.machine.id == machineId }?
                .closed ?? true
        )
    }

    func sessionAlive(forContext contextId: Context.ID) -> Bool {
        !(
            sessionContexts
                .first { $0.id == contextId }?
                .closed ?? true
        )
    }

    func closeSession(withMachineID machineId: RDMachine.ID) {
        guard let index = sessionContexts.firstIndex(where: { $0.machine.id == machineId }) else { return }
        let context = sessionContexts.remove(at: index)
        shutdown(context)
    }

    func closeSession(withContextID contextId: Context.ID) {
        guard let index = sessionContexts.firstIndex(where: { $0.id == contextId }) else { return }
        let context = sessionContexts.remove(at: index)
        shutdown(context)
    }

    func closeAll() {
        for context in sessionContexts {
            shutdown(context)
        }
        sessionContexts = []
    }
}
