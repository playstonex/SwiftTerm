//
//  MachineView.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/10.
//

import RayonModule
import SwiftUI

struct MachineView: View {
    let machine: RDMachine.ID
    var forceHighlight: Bool = false

    @EnvironmentObject var store: RayonStore

    @State var openEditSheet: Bool = false
    @State var hoverd: Bool = false

    let redactedColor: Color = .accentColor

    var body: some View {
        contentView
            .contextMenu {
                Button {
                    store.machineGroup.delete(machine)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(DesignTokens.shadowOpacity),
                            radius: (hoverd || forceHighlight) ? DesignTokens.shadowRadius + 4 : DesignTokens.shadowRadius,
                            x: 0, y: DesignTokens.shadowY)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium)
                    .stroke(Color.accentColor.opacity((hoverd || forceHighlight) ? 0.3 : 0.1), lineWidth: 1)
            )
            .sheet(isPresented: $openEditSheet) {
                MachineEditView(inEditWith: machine)
            }
            .onTapGesture(count: 2) {
                TerminalManager.shared.createSession(withMachineID: machine)
            }.onHover(perform: { hovering in
                withAnimation(.spring(response: DesignTokens.springResponse, dampingFraction: DesignTokens.springDamping)) {
                    hoverd = hovering
                }
            })
    }

    var contentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.machineGroup[machine].name)
                .font(.system(.headline, design: .rounded))
                .overlay(
                    Rectangle()
                        .cornerRadius(2)
                        .foregroundColor(redactedColor)
                        .expended()
                        .opacity(store.machineRedacted.rawValue > 1 ? 1 : 0)
                )

            HStack {
                Text(store.machineGroup[machine].remoteAddress)
                Spacer()
                Text(store.machineGroup[machine].remotePort)
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.secondary)
            .overlay(
                Rectangle()
                    .cornerRadius(2)
                    .foregroundColor(redactedColor)
                    .expended()
                    .opacity(store.machineRedacted.rawValue > 0 ? 1 : 0)
            )

            Divider()

            HStack(spacing: 4) {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("Activity:")
                        .lineLimit(1)
                    Text("Banner:")
                        .lineLimit(1)
                    Text("Comment:")
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        store.machineGroup[machine]
                            .lastConnection
                            .formatted(date: .abbreviated, time: .omitted)
                    )
                    .lineLimit(1)
                    Text(
                        store.machineGroup[machine]
                            .lastBanner
                            .count > 0 ?
                            store.machineGroup[machine].lastBanner
                            : "Not Identified"
                    )
                    .lineLimit(1)
                    Text(store.machineGroup[machine].comment)
                }
            }
            .font(.system(.caption, design: .rounded))
            .overlay(
                Rectangle()
                    .cornerRadius(2)
                    .foregroundColor(redactedColor)
                    .expended()
                    .opacity(store.machineRedacted.rawValue > 1 ? 1 : 0)
            )

            Divider()

            Text(machine.uuidString)
                .textSelection(.enabled)
                .font(.system(size: 9, weight: .light, design: .monospaced))
        }
        .animation(.interactiveSpring(), value: store.machineRedacted)
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.paddingStandard)
    }
}
