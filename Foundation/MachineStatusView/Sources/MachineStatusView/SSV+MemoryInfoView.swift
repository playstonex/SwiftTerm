//
//  File.swift
//
//
//  Created by Lakr Aream on 2022/3/2.
//

import MachineStatus
import SwiftUI

public extension ServerStatusViews {
    struct MemoryInfoView: View {
        @EnvironmentObject var info: ServerStatus

        public init() {}

        public var body: some View {
            VStack {
                HStack {
                    Image(systemName: "memorychip")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                    Text(L10n.tr("RAM"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                    Text(memoryFmt(kBytes: info.memory.memTotal))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                }
                Divider()
                VStack(spacing: 2) {
                    HStack {
                        Text(shortDescription())
                        Spacer()
                        Text(percentDescription())
                    }
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    ColorizedProgressView(
                        colors: [
                            .init(color: .yellow, weight: info.memory.memTotal - info.memory.memFree - info.memory.memCached),
                            .init(color: .orange, weight: info.memory.memCached),
                            .init(color: .green, weight: info.memory.memFree),
                        ]
                    )
                }
                Divider()
                LazyVGrid(columns:
                    [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], content: {
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.yellow)
                                .frame(width: 10, height: 10)
                            Text(L10n.tr("USED"))
                                .font(.system(size: 11, weight: .semibold, design: .default))
                            Spacer()
                        }
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.orange)
                                .frame(width: 10, height: 10)
                            Text(L10n.tr("CACHE"))
                                .font(.system(size: 11, weight: .semibold, design: .default))
                            Spacer()
                        }
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.green)
                                .frame(width: 10, height: 10)
                            Text(L10n.tr("FREE"))
                                .font(.system(size: 11, weight: .semibold, design: .default))
                            Spacer()
                        }
                    })
                Divider()
                HStack {
                    Text(L10n.tr("Active & Inactive is not counted as free memory"))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                    Spacer()
                }
                .opacity(0.5)
            }
        }

        func shortDescription() -> String {
            L10n.tr(
                "USED: %@ CACHE %@ FREE %@ SWAP %@",
                memoryFmt(kBytes: info.memory.memTotal - info.memory.memFree),
                memoryFmt(kBytes: info.memory.memCached),
                memoryFmt(kBytes: info.memory.memFree),
                memoryFmt(kBytes: info.memory.swapTotal)
            )
        }

        func percentDescription() -> String {
            Float((1.0 - (info.memory.memFree / info.memory.memTotal)) * 100)
                .string(fractionDigits: 2) + " %"
        }
    }
}
