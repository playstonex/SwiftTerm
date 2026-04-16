//
//  EditServerSheet.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/10.
//

import RayonModule
import SwiftUI

struct MachineEditView: View {
    let inEditWith: RDMachine.ID

    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var store: RayonStore

    @State var remoteAddress = ""
    @State var remotePort = ""
    @State var name = ""
    @State var group = ""
    @State var comment = ""
    @State var associatedIdentity: UUID? = nil

    @State var openIdentityPicker: Bool = false

    @State var sftpLoginPath: String = "/"
    @State var connectionType: RDMachine.ConnectionType = .ssh
    @State var moshPredictionMode: RDMachine.MoshPredictionMode = .adaptive

    var identityDescription: String {
        if let aid = associatedIdentity {
            return store.identityGroup[aid].shortDescription()
        }
        return "None"
    }

    var body: some View {
        SheetTemplate.makeSheet(
            title: "Edit Machine",
            body: AnyView(sheetBody)
        ) { confirmed in
            var shouldDismiss = false
            defer { if shouldDismiss { presentationMode.wrappedValue.dismiss() } }
            if !confirmed {
                shouldDismiss = true
                return
            }
            var generator = store.machineGroup[inEditWith]
            generator.remoteAddress = remoteAddress
            generator.remotePort = remotePort
            generator.name = name
            generator.group = group
            generator.comment = comment
            generator.associatedIdentity = associatedIdentity?.uuidString
            generator.fileTransferLoginPath = sftpLoginPath
            generator.connectionType = connectionType
            if connectionType == .mosh {
                generator.moshPredictionMode = moshPredictionMode
            }
            generator.lastModifiedDate = Date()
            store.machineGroup.insert(generator)
            shouldDismiss = true
        }
        .onAppear {
            let read = store.machineGroup[inEditWith]
            remoteAddress = read.remoteAddress
            remotePort = read.remotePort
            name = read.name
            group = read.group
            comment = read.comment
            sftpLoginPath = read.fileTransferLoginPath
            connectionType = read.connectionType
            moshPredictionMode = read.moshPredictionMode
            if let aid = read.associatedIdentity,
               let auid = UUID(uuidString: aid)
            {
                associatedIdentity = auid
            }
        }
        .sheet(isPresented: $openIdentityPicker, onDismiss: nil, content: {
            IdentityPickerSheetView { rid in
                associatedIdentity = rid
            }
        })
        .frame(width: 600)
    }

    var sheetBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            // General
            sectionHeader("General")
            settingsCard {
                settingsRow("Name") {
                    TextField("Name (Optional)", text: $name)
                        .textFieldStyle(.plain)
                }
                settingsDivider
                settingsRow("Group") {
                    TextField("Default (Optional)", text: $group)
                        .textFieldStyle(.plain)
                }
                settingsDivider
                settingsRow("Address") {
                    HStack(spacing: 4) {
                        TextField("Host Address", text: $remoteAddress)
                            .textFieldStyle(.plain)
                        Text(":")
                            .foregroundStyle(.secondary)
                        TextField("Port", text: $remotePort)
                            .textFieldStyle(.plain)
                            .frame(width: 60)
                    }
                }
            }

            // Authentication
            sectionHeader("Authentication")
            settingsCard {
                settingsRow("Identity") {
                    Button {
                        openIdentityPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(identityDescription)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Connection
            sectionHeader("Connection")
            settingsCard {
                settingsRow("Type") {
                    Picker("", selection: $connectionType) {
                        Text("SSH").tag(RDMachine.ConnectionType.ssh)
                        Text("Mosh").tag(RDMachine.ConnectionType.mosh)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
                if connectionType == .mosh {
                    settingsDivider
                    settingsRow("Prediction") {
                        Picker("", selection: $moshPredictionMode) {
                            Text("Adaptive").tag(RDMachine.MoshPredictionMode.adaptive)
                            Text("Always").tag(RDMachine.MoshPredictionMode.always)
                            Text("Never").tag(RDMachine.MoshPredictionMode.never)
                            Text("Experimental").tag(RDMachine.MoshPredictionMode.experimental)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            }

            // File Transfer
            sectionHeader("File Transfer")
            settingsCard {
                settingsRow("SFTP Path") {
                    TextField("/", text: $sftpLoginPath)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                }
                settingsDivider
                settingsRow("Comment") {
                    TextField("Comment (Optional)", text: $comment)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                }
            }

            sheetFoot
        }
    }

    var sheetFoot: some View {
        Text("ID: \(inEditWith.uuidString)")
            .font(.system(size: 10, weight: .light, design: .monospaced))
            .foregroundStyle(.tertiary)
    }

    // MARK: - Layout Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func settingsRow<Content: View>(_ title: String,
                                             @ViewBuilder content: () -> Content) -> some View
    {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
            Spacer()
            content()
        }
        .padding(.vertical, 8)
    }

    private var settingsDivider: some View {
        Divider().padding(.horizontal, 8)
    }
}
