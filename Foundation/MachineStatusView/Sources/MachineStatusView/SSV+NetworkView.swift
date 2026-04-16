//
//  SwiftUIView.swift
//
//
//  Created by Lakr Aream on 2022/3/2.
//

import MachineStatus
import SwiftUI

public extension ServerStatusViews {
    struct NetworkView: View {
        @EnvironmentObject var info: ServerStatus

        public init() {}

        var elements: [ServerStatus.NetworkInfo.NetworkInfoElement] {
            info.network.elements
        }

        var totalRxByte: Int {
            var result = 0
            info.network.elements.map(\.rxBytesPerSec).forEach { value in
                result &+= value
            }
            return result
        }

        var totalTxByte: Int {
            var result = 0
            info.network.elements.map(\.txBytesPerSec).forEach { value in
                result &+= value
            }
            return result
        }

        public var body: some View {
            VStack {
                HStack {
                    Image(systemName: "network")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                    Text(L10n.tr("NET"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                }
                Divider()
                VStack(spacing: 12) {
                    if elements.count > 0 {
                        ForEach(elements) { network in
                            VStack(spacing: 12) {
                                HStack {
                                    Spacer().frame(width: 2.5, height: 0)
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.orange)
                                    Text(network.device)
                                    Spacer()
                                }
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                ], content: {
                                    HStack {
                                        Image(systemName: "arrow.down")
                                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                                            .foregroundColor(.purple)
                                        Text(L10n.tr("RX"))
                                            .foregroundColor(.purple)
                                        Spacer()
                                        Text(bytesFmt(bytes: network.rxBytesPerSec))
                                        Spacer().frame(width: 5)
                                    }
                                    HStack {
                                        Spacer().frame(width: 5)
                                        Image(systemName: "arrow.up").font(.system(size: 14, weight: .heavy, design: .rounded))
                                            .foregroundColor(.blue)
                                        Text(L10n.tr("TX"))
                                            .foregroundColor(.blue)
                                        Spacer()
                                        Text(bytesFmt(bytes: network.txBytesPerSec))
                                    }
                                })
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            }
                        }
                    } else {
                        Text(L10n.tr("No Data Available"))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    }
                }
                HStack {
                    Text(L10n.tr("Displaying network speed, measured each second"))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                    Spacer()
                }
                .opacity(0.5)
                Divider()
                HStack {
                    Text(L10n.tr("RX"))
                    Text(bytesFmt(bytes: totalRxByte))
                    Text(L10n.tr("TX"))
                    Text(bytesFmt(bytes: totalTxByte))
                    Spacer()
                    Text(L10n.tr("BYTES"))
                }
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
            }
        }
    }
}
