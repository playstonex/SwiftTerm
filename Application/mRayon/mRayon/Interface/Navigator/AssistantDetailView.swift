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
    @ObservedObject var assistantManager = AssistantManager.shared

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
        .id(context.id) // Force view refresh for different contexts
        .onAppear {
            debugPrint("[iOS AssistantDetailView] appeared for context: \(context.machine.name)")
            DispatchQueue.main.async {
                assistantManager.setCurrentContext(context)
            }
        }
        .onDisappear {
            debugPrint("[iOS AssistantDetailView] disappeared for context: \(context.machine.name)")
            DispatchQueue.main.async {
                assistantManager.clearCurrentContext()
            }
        }
    }
}

// MARK: - Assistant Inspector View
struct AssistantInspectorView: View {
    @StateObject var context: TerminalContext
    @ObservedObject var assistantManager = AssistantManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control
            Picker("", selection: $assistantManager.selectedSegment) {
                ForEach(AssistantManager.AssistantSegment.allCases, id: \.self) { segment in
                    Label(segment.displayName, systemImage: segment.icon)
                        .tag(segment)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
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
    @State private var systemHistory: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with refresh button
            HStack {
                Text("Command History")
                    .font(.headline)
                    .padding(.horizontal)

                Spacer()

                Button(action: {
                    fetchSystemHistory()
                }) {
                    HStack(spacing: 4) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            // Display combined history
            if systemHistory.isEmpty && context.inputHistory.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No command history yet")
                        .foregroundColor(.secondary)

                    Text("Tap Refresh to load command history from the server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Load History") {
                        fetchSystemHistory()
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        // System history
                        if !systemHistory.isEmpty {
                            ForEach(Array(systemHistory.enumerated()), id: \.offset) { index, command in
                                HistoryRow(
                                    index: index + 1,
                                    command: command,
                                    isSystemHistory: true,
                                    action: {
                                        context.insertBuffer(command + "\n")
                                    }
                                )
                            }

                            if !context.inputHistory.isEmpty {
                                Divider()
                                    .padding(.vertical, 8)
                            }
                        }

                        // Session history
                        if !context.inputHistory.isEmpty {
                            ForEach(Array(context.inputHistory.enumerated()), id: \.offset) { index, command in
                                HistoryRow(
                                    index: systemHistory.count + index + 1,
                                    command: command,
                                    isSystemHistory: false,
                                    action: {
                                        context.insertBuffer(command + "\n")
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .onAppear {
            // Auto-fetch history when view appears
            if systemHistory.isEmpty {
                fetchSystemHistory()
            }
        }
    }

    private func fetchSystemHistory() {
        isLoading = true
        errorMessage = nil

        debugPrint("[History] Fetching system history...")
        debugPrint("[History] Shell connected: \(context.shell.isConnected)")
        debugPrint("[History] Shell authenticated: \(context.shell.isAuthenticated)")

        // Use the existing shell connection
        guard context.shell.isConnected, context.shell.isAuthenticated else {
            debugPrint("[History] No active shell connection")
            errorMessage = "Terminal not connected"
            isLoading = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            debugPrint("[History] Executing history command...")

            // Detect shell and read appropriate history file
            // Supports: bash, zsh, fish, tcsh, and others
            let command = """
            SHELL=$(echo $SHELL); \
            if [ "$SHELL" = "/bin/zsh" ] || [ "$SHELL" = "/usr/bin/zsh" ] || [ "$SHELL" = "/usr/local/bin/zsh" ]; then \
                [ -f ~/.zsh_history ] && tail -n 100 ~/.zsh_history | sed 's/^: [0-9]*:[0-9]*;//' | sed 's/^\\[//;s/\\]$//'; \
            elif [ "$SHELL" = "/bin/bash" ] || [ "$SHELL" = "/usr/bin/bash" ] || [ "$SHELL" = "/usr/local/bin/bash" ]; then \
                [ -f ~/.bash_history ] && tail -n 100 ~/.bash_history; \
            elif [ "$SHELL" = "/bin/fish" ] || [ "$SHELL" = "/usr/bin/fish" ] || [ "$SHELL" = "/usr/local/bin/fish" ]; then \
                [ -f ~/.local/share/fish/fish_history ] && tail -n 200 ~/.local/share/fish/fish_history | grep -v 'cmd' | sed 's/^.*"- "//;s/"$//' | sed 's/\\\\"/"/g'; \
            elif [ "$SHELL" = "/bin/tcsh" ] || [ "$SHELL" = "/usr/bin/tcsh" ] || [ "$SHELL" = "/bin/csh" ]; then \
                [ -f ~/.history ] && tail -n 100 ~/.history; \
            else \
                ( [ -f ~/.bash_history ] && tail -n 100 ~/.bash_history ) || \
                ( [ -f ~/.zsh_history ] && tail -n 100 ~/.zsh_history | sed 's/^: [0-9]*:[0-9]*;//' ) || \
                ( [ -f ~/.local/share/fish/fish_history ] && tail -n 200 ~/.local/share/fish/fish_history | grep -v 'cmd' | sed 's/^.*"- "//;s/"$//' ) || \
                ( [ -f ~/.history ] && tail -n 100 ~/.history ) || \
                echo "No history file found"; \
            fi
            """

            var output = ""

            let result = self.context.shell.beginExecute(
                withCommand: " \(command)",  // Leading space to avoid storing in history
                withTimeout: NSNumber(value: 15),
                withOnCreate: {
                    debugPrint("[History] Command execution started")
                },
                withOutput: { chunk in
                    if chunk.count > 100 {
                        debugPrint("[History] Received large chunk: \(chunk.prefix(50))...")
                    } else {
                        debugPrint("[History] Received chunk: \(chunk)")
                    }
                    output.append(chunk)
                },
                withContinuationHandler: nil
            )

            debugPrint("[History] Command result: \(result)")
            debugPrint("[History] Total output length: \(output.count)")
            debugPrint("[History] Raw output (first 500 chars): \n\(output.prefix(500))")

            // Parse the output
            let parsed = self.parseHistoryOutput(output)
            debugPrint("[History] Parsed \(parsed.count) commands")

            DispatchQueue.main.async {
                self.systemHistory = parsed
                self.isLoading = false
                if parsed.isEmpty {
                    self.errorMessage = "No commands found in history"
                }
                debugPrint("[History] Updated UI with \(parsed.count) commands")
            }
        }
    }

    private func parseHistoryOutput(_ output: String) -> [String] {
        var commands: [String] = []

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines and error messages
            if trimmed.isEmpty ||
               trimmed.contains("No history file found") ||
               trimmed.contains("No such file or directory") ||
               trimmed.contains("command not found") {
                continue
            }

            // Skip bash/zsh internal commands that start with special chars
            if trimmed.hasPrefix("#") || trimmed.hasPrefix(":") {
                // Parse zsh history format: ": timestamp:duration;command"
                if trimmed.hasPrefix(":") && trimmed.contains(";") {
                    if let semicolonRange = trimmed.range(of: ";") {
                        let command = String(trimmed[semicolonRange.upperBound...])
                        if !command.isEmpty {
                            commands.append(command)
                        }
                    }
                }
                continue
            }

            // Skip lines that are just numbers (bash history indexes)
            if trimmed.range(of: "^\\d+$", options: .regularExpression) != nil {
                continue
            }

            // Add the command (skip export commands, etc.)
            if !trimmed.hasPrefix("export ") &&
               !trimmed.hasPrefix("unset ") &&
               !trimmed.isEmpty {
                commands.append(trimmed)
            }
        }

        // Remove duplicates while preserving order
        var seen = Set<String>()
        var uniqueCommands: [String] = []
        for cmd in commands {
            if !seen.contains(cmd) {
                seen.insert(cmd)
                uniqueCommands.append(cmd)
            }
        }

        return uniqueCommands
    }
}

// MARK: - History Row Component
struct HistoryRow: View {
    let index: Int
    let command: String
    let isSystemHistory: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Index
            Text("\(index)")
                .foregroundColor(.secondary)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 40, alignment: .trailing)

            // Command
            Text(command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)

            Spacer()

            // Insert button
            Button(action: action) {
                Image(systemName: "arrow.up.doc")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())

            // Badge
            if isSystemHistory {
                Image(systemName: "server.rack")
                    .font(.system(size: 10))
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
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
            debugPrint("[Status] No associated identity found")
            return
        }
        let identity = RayonStore.shared.identityGroup[uid]
        guard !identity.username.isEmpty else {
            debugPrint("[Status] Identity username is empty")
            return
        }

        debugPrint("[Status] Starting monitoring for \(machine.remoteAddress)")

        // Create a temporary shell for status check
        let shell = NSRemoteShell()
            .setupConnectionHost(machine.remoteAddress)
            .setupConnectionPort(NSNumber(value: Int(machine.remotePort) ?? 0))
            .setupConnectionTimeout(6)

        DispatchQueue.global(qos: .userInitiated).async {
            debugPrint("[Status] Connecting to server...")
            shell.requestConnectAndWait()
            identity.callAuthenticationWith(remote: shell)

            if shell.isConnected, shell.isAuthenticated {
                debugPrint("[Status] Connected and authenticated, requesting status...")
                // Update status on background thread, then update UI on main thread
                self.serverStatus.requestInfoAndWait(with: shell)

                debugPrint("[Status] Status received, disconnecting...")
                shell.requestDisconnectAndWait()

                // Update UI on main thread after status is fetched
                DispatchQueue.main.async {
                    debugPrint("[Status] Updating UI")
                    self.isMonitoring = true
                }
            } else {
                debugPrint("[Status] Failed to connect or authenticate")
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
