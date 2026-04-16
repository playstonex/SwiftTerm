//
//  ProcessorInfoSummaryView.swift
//
//
//  Created by Lakr Aream on 2022/3/2.
//

import MachineStatus
import SwiftUI

public extension ServerStatusViews {
    struct ProcessorInfoSummaryView: View {
        @EnvironmentObject var info: ServerStatus

        public init() {}

        public var body: some View {
            VStack {
                HStack {
                    Image(systemName: "cpu")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                    Text(L10n.tr("CPU"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                    Text(
                        info.processor.cores.count > 1
                            ? L10n.tr("%d CORES", info.processor.cores.count)
                            : L10n.tr("%d CORE", info.processor.cores.count)
                    )
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                }
                Divider()
                ProcessorInfoView(title: L10n.tr("All Core"), info: info.processor.summary)
                Divider()
                if info.processor.cores.count > 0 {
                    ForEach(info.processor.cores) { core in
                        ProcessorInfoView(title: core.name, info: core)
                    }
                } else {
                    Text(L10n.tr("No Data Available"))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                }
                Divider()
                LazyVGrid(columns:
                    [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], content: {
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.yellow)
                                .frame(width: 10, height: 10)
                            Text(L10n.tr("USER"))
                                .font(.system(size: 11, weight: .semibold, design: .default))
                            Spacer()
                        }
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.red)
                                .frame(width: 10, height: 10)
                            Text(L10n.tr("SYS"))
                                .font(.system(size: 11, weight: .semibold, design: .default))
                            Spacer()
                        }
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.orange)
                                .frame(width: 10, height: 10)
                            Text(L10n.tr("IO"))
                                .font(.system(size: 11, weight: .semibold, design: .default))
                            Spacer()
                        }
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.blue)
                                .frame(width: 10, height: 10)
                            Text(L10n.tr("NICE"))
                                .font(.system(size: 11, weight: .semibold, design: .default))
                            Spacer()
                        }
                    })
            }
        }
    }
}
