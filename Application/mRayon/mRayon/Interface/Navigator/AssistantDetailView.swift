//
//  AssistantDetailView.swift
//  mRayon
//
//  Created by Claude on 2026/1/27.
//

import MachineStatus
import MachineStatusView
import NSRemoteShell
import RayonModule
import SwiftUI

struct AssistantDetailView: View {
    @StateObject var context: TerminalContext
    @StateObject var assistantManager = AssistantManager.shared

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Terminal View (takes remaining space)
                TerminalView(context: context)
                    .frame(maxWidth: .infinity)

                // Assistant Panel (shows when visible)
                if assistantManager.isVisible {
                    AssistantInspectorView(context: context)
                        .frame(width: 320)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .onAppear {
            assistantManager.setCurrentContext(context)
        }
        .onDisappear {
            assistantManager.clearCurrentContext()
        }
    }
}

// MARK: - Assistant Inspector View
struct AssistantInspectorView: View {
    @StateObject var context: TerminalContext
    @StateObject var assistantManager = AssistantManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control
            Picker("Assistant", selection: $assistantManager.selectedSegment) {
                ForEach(AssistantManager.AssistantSegment.allCases, id: \.self) { segment in
                    Label(segment.displayName, systemImage: segment.icon)
                        .tag(segment)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))

            Divider()

            // Content based on selected segment
            ScrollView {
                Group {
                    switch assistantManager.selectedSegment {
                    case .history:
                        TerminalHistoryView(context: context)
                    case .status:
                        AssistantStatusView(context: context)
                    case .ai:
                        AssistantAIView(context: context)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(
            // Separator on the left
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(width: 0.5),
            alignment: .leading
        )
    }
}

// MARK: - History Segment
struct TerminalHistoryView: View {
    @StateObject var context: TerminalContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if context.inputHistory.isEmpty {
                    Text("No command history yet")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(Array(context.inputHistory.enumerated()), id: \.offset) { index, command in
                        HStack(alignment: .top) {
                            Text("\(index + 1)")
                                .foregroundColor(.secondary)
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)

                            Text(command)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            Spacer()

                            Button(action: {
                                context.insertBuffer(command)
                            }) {
                                Image(systemName: "arrow.up.doc")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Status Segment
struct AssistantStatusView: View {
    @StateObject var context: TerminalContext
    @State private var isMonitoring = false
    @State private var serverStatus: ServerStatus = .init()

    var body: some View {
        Group {
            if isMonitoring {
                // Display server status directly without MonitorView's toolbar
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ServerStatusViews.createBaseStatusView(withContext: serverStatus)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "chart.line.uptrend.xyaxis.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Status Monitor")
                        .font(.headline)

                    Text("View real-time server status including CPU, memory, disk, and network usage.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button(action: {
                        startMonitoring()
                    }) {
                        Label("Start Monitoring", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .padding()
            }
        }
        .onAppear {
            // Auto-start monitoring when this segment appears
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        let machine = context.machine
        guard let aid = machine.associatedIdentity,
              let uid = UUID(uuidString: aid)
        else {
            return
        }
        let identity = RayonStore.shared.identityGroup[uid]
        guard !identity.username.isEmpty else {
            return
        }

        // Create a temporary shell for status check
        let shell = NSRemoteShell()
            .setupConnectionHost(machine.remoteAddress)
            .setupConnectionPort(NSNumber(value: Int(machine.remotePort) ?? 0))
            .setupConnectionTimeout(6)

        DispatchQueue.global(qos: .userInitiated).async {
            shell.requestConnectAndWait()
            identity.callAuthenticationWith(remote: shell)

            if shell.isConnected, shell.isAuthenticated {
                mainActor {
                    self.isMonitoring = true
                    // Update status
                    self.serverStatus.requestInfoAndWait(with: shell)
                    shell.requestDisconnectAndWait()
                }
            }
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
    }
}

// MARK: - AI Segment
struct AssistantAIView: View {
    @StateObject var context: TerminalContext

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("AI Assistant")
                    .font(.headline)

                Text("Get AI-powered help with terminal commands, troubleshooting, and more.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Command explanations", systemImage: "checkmark.circle.fill")
                    Label("Error troubleshooting", systemImage: "checkmark.circle.fill")
                    Label("Script suggestions", systemImage: "checkmark.circle.fill")
                    Label("System optimization tips", systemImage: "checkmark.circle.fill")
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(10)

                Text("Coming soon")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top)

                Spacer()
            }
            .padding()
        }
    }
}
