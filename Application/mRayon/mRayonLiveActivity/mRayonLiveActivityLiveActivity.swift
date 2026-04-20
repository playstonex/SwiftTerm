//
//  mRayonLiveActivityLiveActivity.swift
//  mRayonLiveActivity
//
//  Created by lei on 2026/4/18.
//

import ActivityKit
import RayonLiveActivity
import SwiftUI
import WidgetKit

struct TerminalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TerminalSessionAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: context.state.status.systemImageName)
                            .foregroundStyle(colorForStatus(context.state.status))
                        Text(context.attributes.machineName)
                            .font(.caption)
                            .bold()
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let commandStart = context.state.commandStartedAt {
                        Text(commandStart, style: .timer)
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let command = context.state.currentCommand {
                            Text(command)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        }
                        Text(context.state.transport)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } compactLeading: {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(colorForStatus(context.state.status))
            } compactTrailing: {
                if context.state.status == .running,
                   let start = context.state.commandStartedAt
                {
                    Text(start, style: .timer)
                        .font(.caption2)
                        .monospacedDigit()
                } else if context.state.unreadBellCount > 0 {
                    Text("\(context.state.unreadBellCount)")
                        .font(.caption2)
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(colorForStatus(context.state.status))
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(
        context: ActivityViewContext<TerminalSessionAttributes>
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: context.state.status.systemImageName)
                        .foregroundStyle(colorForStatus(context.state.status))
                    Text(context.attributes.machineName)
                        .font(.subheadline)
                        .bold()
                    Text("(\(context.state.transport))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let command = context.state.currentCommand {
                    Text(command)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let snippet = context.state.lastLineSnippet {
                    Text(snippet)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let start = context.state.commandStartedAt {
                Text(start, style: .timer)
                    .font(.title3)
                    .monospacedDigit()
            }
        }
        .padding()
    }

    private func colorForStatus(_ status: TerminalSessionAttributes.ContentState.Status) -> Color {
        switch status {
        case .connected: return .green
        case .reconnecting: return .orange
        case .disconnected: return .red
        case .idle: return .gray
        case .running: return .green
        }
    }
}

extension TerminalSessionAttributes {
    fileprivate static var preview: TerminalSessionAttributes {
        TerminalSessionAttributes(sessionID: UUID(), machineName: "server-01")
    }
}

extension TerminalSessionAttributes.ContentState {
    fileprivate static var connected: TerminalSessionAttributes.ContentState {
        TerminalSessionAttributes.ContentState(
            status: .connected, host: "server-01", transport: "SSH"
        )
    }

    fileprivate static var running: TerminalSessionAttributes.ContentState {
        TerminalSessionAttributes.ContentState(
            status: .running,
            host: "server-01",
            transport: "Mosh",
            currentCommand: "make -j8",
            commandStartedAt: .now
        )
    }
}

#Preview("Notification", as: .content, using: TerminalSessionAttributes.preview) {
    TerminalLiveActivity()
} contentStates: {
    TerminalSessionAttributes.ContentState.connected
    TerminalSessionAttributes.ContentState.running
}
