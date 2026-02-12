//
//  MachineActionView.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2018/3/1.
//

import RayonModule
import SwiftUI

struct MachineActionView: View {
    enum ActionKey: String, CaseIterable, Hashable {
        case edit
        case delete
        case duplicate
        case runCat
        case fileTransfer
        case connect
    }

    let machine: RDMachine.ID
    var onHoverChanged: ((Bool) -> Void)? = nil

    @EnvironmentObject var store: RayonStore

    @State private var openEdit: Bool = false
    @State private var hoveredAction: ActionKey?

    var orderedActions: [ActionKey] { ActionKey.allCases }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                ForEach(Array(orderedActions.enumerated()), id: \.element.rawValue) { index, key in
                    actionButton(key)
                    if index < orderedActions.count - 1 {
                        divider
                    }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial.opacity(0.8))
        )
        .onHover { hovering in
            onHoverChanged?(hovering)
        }
        .sheet(isPresented: $openEdit, onDismiss: nil) {
            MachineEditView(inEditWith: machine)
        }
        .padding(EdgeInsets(top: 3, leading: 8, bottom: 8, trailing: 3))
    }

    var divider: some View {
        Divider()
            .frame(height: 14)
            .padding(.horizontal, 2)
            .opacity(0.5)
    }

    func actionButton(_ key: ActionKey) -> some View {
        let isHovered = hoveredAction == key
        return Button(action: { performAction(for: key) }) {
            label(for: key)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.20) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.white.opacity(0.32) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundColor(isHovered ? .primary : .accentColor)
        .help(help(for: key))
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredAction = key
            } else if hoveredAction == key {
                hoveredAction = nil
            }
        }
    }

    @ViewBuilder
    func label(for key: ActionKey) -> some View {
        switch key {
        case .edit:
            Image(systemName: "pencil")
                .frame(width: 15, height: 15)
        case .delete:
            Image(systemName: "trash")
                .frame(width: 15, height: 15)
        case .duplicate:
            Image(systemName: "plus.square.on.square")
                .frame(width: 15, height: 15)
        case .runCat:
            Image(nsImage: NSImage(named: "cat_frame_0")!)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(-2)
                .frame(width: 15, height: 15)
        case .fileTransfer:
            Image(systemName: "externaldrive.connected.to.line.below.fill")
                .frame(width: 15, height: 15)
        case .connect:
            Image(systemName: "cable.connector.horizontal")
                .frame(width: 15, height: 15)
        }
    }

    func performAction(for key: ActionKey) {
        switch key {
        case .edit:
            openEdit = true
        case .delete:
            deleteButtonTapped()
        case .duplicate:
            duplicateButtonTapped()
        case .runCat:
            MenubarTool.shared.createRuncat(for: machine)
        case .fileTransfer:
            FileTransferManager.shared.begin(for: machine)
        case .connect:
            beingConnect()
        }
    }

    func help(for key: ActionKey) -> String {
        switch key {
        case .edit:
            "Edit"
        case .delete:
            "Delete"
        case .duplicate:
            "Duplicate"
        case .runCat:
            "RunCat"
        case .fileTransfer:
            "File Transfer"
        case .connect:
            "Connect"
        }
    }

    func beingConnect() {
        TerminalManager.shared.createSession(withMachineID: machine)
    }

    func duplicateButtonTapped() {
        UIBridge.requiresConfirmation(
            message: "You are about to duplicate this item"
        ) { confirmed in
            guard confirmed else { return }
            let index = store
                .machineGroup
                .machines
                .firstIndex { $0.id == machine }
            if let index = index {
                var machine = store.machineGroup.machines[index]
                machine.id = UUID()
                store.machineGroup.insert(machine)
            }
        }
    }

    func deleteButtonTapped() {
        UIBridge.requiresConfirmation(
            message: "You are about to delete this item"
        ) { confirmed in
            guard confirmed else { return }
            store.machineGroup.delete(machine)
            store.cleanRecentIfNeeded()
        }
    }
}
