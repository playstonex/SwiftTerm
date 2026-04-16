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
import SettingsUI
import SwiftUI

struct AssistantDetailView: View {
    @StateObject var context: TerminalContext
    @ObservedObject var assistantManager = AssistantManager.shared

    var body: some View {
        ZStack(alignment: .trailing) {
            // Terminal View (takes full space)
            TerminalView(context: context)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Assistant Panel (floating overlay)
            if assistantManager.isVisible {
                AssistantInspectorView(context: context)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: -10, y: 0)
                    .padding(.trailing, 16)
                    .padding(.vertical, 16)
            }
        }
        .id(context.id) // Force view refresh for different contexts
        .onAppear {
            assistantManager.setCurrentContext(context)
        }
        .onDisappear {
            assistantManager.clearCurrentContext()
        }
        #if os(iOS)
        .disableSwipeBack()
        #endif
    }
}

// MARK: - Disable Swipe Back (iOS)

#if os(iOS)
extension View {
    func disableSwipeBack() -> some View {
        background(DisableSwipeBackView())
    }
}

private struct DisableSwipeBackView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.parentViewController?.navigationController?
                .interactivePopGestureRecognizer?.isEnabled = false
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            uiView.parentViewController?.navigationController?
                .interactivePopGestureRecognizer?.isEnabled = false
        }
    }
}

private extension UIView {
    var parentViewController: UIViewController? {
        sequence(first: self) { $0.superview }
            .compactMap(\.next as? UIViewController)
            .first
    }
}
#endif

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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
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

            // Display history
            if systemHistory.isEmpty {
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

        // Use the existing shell connection
        guard context.shell.isConnected, context.shell.isAuthenticated else {
            errorMessage = "Terminal not connected"
            isLoading = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
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

            self.context.shell.beginExecute(
                withCommand: " \(command)",  // Leading space to avoid storing in history
                withTimeout: NSNumber(value: 15),
                withOnCreate: {},
                withOutput: { chunk in
                    output.append(chunk)
                },
                withContinuationHandler: nil
            )

            // Parse the output
            let parsed = self.parseHistoryOutput(output)

            DispatchQueue.main.async {
                self.systemHistory = parsed
                self.isLoading = false
                if parsed.isEmpty {
                    self.errorMessage = "No commands found in history"
                }
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
                // Update status on background thread, then update UI on main thread
                self.serverStatus.requestInfoAndWait(with: shell)
                MonitorTelemetryManager.shared.appendSample(
                    machineId: machine.id,
                    machineName: machine.name,
                    status: self.serverStatus
                )
                shell.requestDisconnectAndWait()

                // Update UI on main thread after status is fetched
                DispatchQueue.main.async {
                    self.isMonitoring = true
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
    @ObservedObject var aiAssistant = AIAssistant.shared
    @State private var searchText = ""
    @State private var analyzedCommands: [CommandAnalysis] = []
    @State private var isAnalyzing = false
    @State private var selectedCommand: CommandAnalysis?
    @State private var showingCommandDetail = false
    @State private var selectedTab: AITab = .commands
    @State private var nlInput = ""
    @State private var isProcessing = false
    @State private var aiResponse = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var showingSettings = false

    enum AITab: String, CaseIterable {
        case commands = "Commands"
        case explain = "Explain"
        case suggest = "Suggest"
        case diagnose = "Diagnose"
        case nl2cmd = "AI Chat"
    }

    var filteredCommands: [CommandAnalysis] {
        if searchText.isEmpty {
            return analyzedCommands
        }
        return analyzedCommands.filter { command in
            command.text.localizedCaseInsensitiveContains(searchText) ||
            command.category.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // AI Provider Status
            if !aiAssistant.isEnabled || aiAssistant.apiKey.isEmpty {
                AIProviderBanner(onTap: { showingSettings = true })
            }

            // Tab selector
            Picker("", selection: $selectedTab) {
                ForEach(AITab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Tab content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .commands:
                        commandHistoryView
                    case .explain:
                        explainView
                    case .suggest:
                        suggestView
                    case .diagnose:
                        diagnoseView
                    case .nl2cmd:
                        nl2cmdView
                    }
                }
            }
        }
        .sheet(isPresented: $showingCommandDetail) {
            if let command = selectedCommand {
                CommandDetailView(analysis: command, context: context)
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationView {
                AISettingsView()
            }
            #if os(iOS)
            .navigationViewStyle(.stack)
            #else
            .frame(minWidth: 500, minHeight: 400)
            #endif
        }
    }

    // MARK: - Command History View

    private var commandHistoryView: some View {
        VStack(spacing: 0) {
            if isAnalyzing {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                    Text("Analyzing command history...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            } else if analyzedCommands.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Commands Analyzed")
                        .font(.headline)

                    Text("Type commands to see AI-powered insights")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Analyze History") {
                        analyzeCommandHistory()
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search commands...", text: $searchText)
                            .textFieldStyle(.plain)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()

                    // Statistics
                    CommandStatsView(commands: analyzedCommands)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))

                    Divider()

                    // Command list
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCommands) { command in
                            CommandAnalysisRow(
                                analysis: command,
                                onTap: {
                                    selectedCommand = command
                                    showingCommandDetail = true
                                },
                                onExecute: {
                                    executeCommand(command.text)
                                }
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            if analyzedCommands.isEmpty {
                analyzeCommandHistory()
            }
        }
    }

    // MARK: - Explain View

    private var explainView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Command Explainer")
                        .font(.headline)
                    Spacer()
                }

                Text("Enter a command to get a detailed explanation of what it does.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            VStack(spacing: 12) {
                TextField("e.g., find . -name '*.log'", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Button(action: {
                    Task {
                        await explainCommand()
                    }
                }) {
                    if isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Analyzing...")
                        }
                    } else {
                        Text("Explain")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchText.isEmpty || isProcessing)

                if !aiResponse.isEmpty {
                    ScrollView {
                        Text(aiResponse)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Suggest View

    private var suggestView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lightbulb")
                        .foregroundColor(.yellow)
                    Text("Smart Suggestions")
                        .font(.headline)
                    Spacer()
                }

                Text("AI-powered command suggestions based on your context.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await getSuggestions()
                    }
                }) {
                    if isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Getting suggestions...")
                        }
                    } else {
                        Label("Get Suggestions", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)

                if !aiResponse.isEmpty {
                    ScrollView {
                        let suggestions = aiResponse.components(separatedBy: "\n")
                            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                                Button(action: {
                                    executeCommand(suggestion.trimmingCharacters(in: .whitespaces))
                                }) {
                                    HStack {
                                        Text("\(index + 1).")
                                            .foregroundColor(.secondary)
                                            .font(.system(.caption, design: .monospaced))
                                        Text(suggestion)
                                            .font(.system(.body, design: .monospaced))
                                            .lineLimit(2)
                                        Spacer()
                                        Image(systemName: "play.circle")
                                            .foregroundColor(.accentColor)
                                    }
                                    .padding(.vertical, 6)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }
    }

    // MARK: - Diagnose View

    private var diagnoseView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Error Diagnosis")
                        .font(.headline)
                    Spacer()
                }

                Text("Paste an error message to get help fixing it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            VStack(spacing: 12) {
                if errorMessage.isEmpty {
                    Text("Paste error message here:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $errorMessage)
                        .frame(minHeight: 80)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(8)
                } else {
                    HStack {
                        Text("Error message:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear") {
                            errorMessage = ""
                        }
                        .font(.caption)
                    }

                    TextEditor(text: $errorMessage)
                        .frame(minHeight: 80)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(8)
                }

                Button(action: {
                    Task {
                        await diagnoseError()
                    }
                }) {
                    if isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Analyzing...")
                        }
                    } else {
                        Label("Diagnose", systemImage: "stethoscope")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(errorMessage.isEmpty || isProcessing)

                if !aiResponse.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI Diagnosis:")
                                .font(.headline)

                            Text(aiResponse)
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Natural Language to Command View

    private var nl2cmdView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundColor(.green)
                    Text("AI Chat - Natural Language to Command")
                        .font(.headline)
                    Spacer()
                }

                Text("Describe what you want to do in plain English, and AI will convert it to a command.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            VStack(spacing: 12) {
                TextField("e.g., Find files larger than 100MB", text: $nlInput)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit {
                        Task {
                            await convertToCommand()
                        }
                    }

                Button(action: {
                    Task {
                        await convertToCommand()
                    }
                }) {
                    if isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Converting...")
                        }
                    } else {
                        Label("Convert to Command", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(nlInput.isEmpty || isProcessing)

                if !aiResponse.isEmpty {
                    HStack(spacing: 12) {
                        Text(aiResponse)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()

                        Button("Execute") {
                            executeCommand(aiResponse)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Copy") {
                            UIPasteboard.general.string = aiResponse
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(10)
                }
            }
            .padding()
        }
    }

    // MARK: - Helper Methods

    private func analyzeCommandHistory() {
        isAnalyzing = true

        DispatchQueue.global(qos: .userInitiated).async {
            let history = context.getOutputHistoryStrippedANSI()
            let commands = Self.extractAndAnalyzeCommands(from: history)

            DispatchQueue.main.async {
                self.analyzedCommands = commands
                self.isAnalyzing = false
            }
        }
    }

    private func executeCommand(_ command: String) {
        context.insertBuffer(command + "\n")
    }

    private func explainCommand() async {
        isProcessing = true
        aiResponse = ""

        do {
            let response = try await aiAssistant.explainCommand(
                searchText,
                sessionId: context.machine.id.uuidString
            )
            aiResponse = response
        } catch {
            aiResponse = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    private func getSuggestions() async {
        isProcessing = true
        aiResponse = ""

        do {
            let suggestions = try await aiAssistant.getSuggestions(
                currentDirectory: nil,
                recentCommands: analyzedCommands.prefix(5).map { $0.text },
                sessionId: context.machine.id.uuidString
            )
            aiResponse = suggestions.joined(separator: "\n")
        } catch {
            aiResponse = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    private func diagnoseError() async {
        isProcessing = true
        aiResponse = ""

        do {
            let response = try await aiAssistant.diagnoseError(
                errorMessage,
                sessionId: context.machine.id.uuidString
            )
            aiResponse = response
        } catch {
            aiResponse = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    private func convertToCommand() async {
        isProcessing = true
        aiResponse = ""

        do {
            let command = try await aiAssistant.naturalLanguageToCommand(
                nlInput,
                context: "Current directory: user's home directory",
                sessionId: context.machine.id.uuidString
            )
            aiResponse = command
        } catch {
            aiResponse = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    private static func extractAndAnalyzeCommands(from history: String) -> [CommandAnalysis] {
        var commandCounts: [String: Int] = [:]
        var commandCategories: [String: CommandCategory] = [:]
        let lines = history.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("$"),
                  !trimmed.hasPrefix(">"),
                  !trimmed.hasPrefix("Last login:") else {
                continue
            }

            guard trimmed.range(of: "^[a-zA-Z/~\\-\\$]", options: .regularExpression) != nil else {
                continue
            }

            let components = trimmed.components(separatedBy: .whitespacesAndNewlines)
            guard let baseCommand = components.first else { continue }

            commandCounts[trimmed, default: 0] += 1

            if commandCategories[trimmed] == nil {
                commandCategories[trimmed] = Self.categorizeCommand(baseCommand)
            }
        }

        let analyses = commandCounts.map { (command, count) -> CommandAnalysis in
            CommandAnalysis(
                text: command,
                count: count,
                category: commandCategories[command] ?? .other,
                lastUsed: Date()
            )
        }

        return analyses.sorted { $0.count > $1.count }
    }

    private static func categorizeCommand(_ baseCommand: String) -> CommandCategory {
        switch baseCommand {
        case "ls", "ll", "la", "dir", "tree", "find", "locate":
            return .fileOps
        case "top", "htop", "ps", "uptime", "df", "du", "free":
            return .systemInfo
        case "ping", "netstat", "ss", "curl", "wget", "ssh", "scp", "rsync":
            return .network
        case "git":
            return .git
        case "vim", "vi", "nano", "emacs", "cat", "less", "more", "head", "tail":
            return .textEditor
        case "apt", "apt-get", "yum", "dnf", "pacman", "brew", "npm", "pip":
            return .packageMgr
        case "systemctl", "service", "chkconfig", "reboot", "shutdown":
            return .systemCtl
        case "useradd", "userdel", "usermod", "passwd", "who", "w":
            return .userMgmt
        default:
            return .other
        }
    }
}

// MARK: - AI Provider Banner

struct AIProviderBanner: View {
    let onTap: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("AI Assistant is disabled")
                    .font(.headline)

                Text("Configure your API key in settings to enable AI features")
                    .font(.caption)
            }

            Spacer()

            Button("Settings") {
                onTap()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - AI Settings View

struct AISettingsView: View {
    @ObservedObject var aiAssistant = AIAssistant.shared
    @Environment(\.dismiss) var dismiss
    @State private var isTesting = false
    @State private var testResult: AIAssistant.TestResult?

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI Assistant", isOn: $aiAssistant.isEnabled)
            } header: {
                Text("Status")
            }

            Section {
                Picker("AI Provider", selection: $aiAssistant.provider) {
                    ForEach(AIAssistant.AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                SecureField("API Key", text: $aiAssistant.apiKey)
                    .textContentType(.password)

                TextField("Custom Base URL (optional)", text: $aiAssistant.customBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Custom Model (optional)", text: $aiAssistant.customModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                // Test Connection Button
                Button(action: {
                    Task {
                        await testAPIConnection()
                    }
                }) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Testing...")
                        } else {
                            Image(systemName: "checkmark.circle")
                            Text("Test Connection")
                        }
                    }
                }
                .disabled(isTesting || aiAssistant.apiKey.isEmpty)

                // Test Result
                if let result = testResult {
                    HStack(spacing: 12) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? .green : .red)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.message)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if let details = result.details {
                                Text(details)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background((result.success ? Color.green : Color.red).opacity(0.1))
                    .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Leave custom fields empty to use defaults.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Your API key is stored locally and never sent to our servers.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        Text("Get OpenAI API Key →")
                            .font(.caption)
                    }
                }
            } header: {
                Text("Configuration")
            } footer: {
                Text("AI features require an API key. Your key is stored securely on your device.\n\nCustom base URL and model name allow you to use compatible OpenAI API endpoints or self-hosted models.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Supported Features:")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Command explanation", systemImage: "info.circle")
                        Label("Smart suggestions", systemImage: "lightbulb")
                        Label("Error diagnosis", systemImage: "stethoscope")
                        Label("Natural language to command", systemImage: "wand.and.stars")
                        Label("Command history analysis", systemImage: "chart.bar")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } header: {
                Text("Features")
            }
        }
        .navigationTitle("AI Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func testAPIConnection() async {
        isTesting = true
        testResult = nil

        let result = await aiAssistant.testConnection()

        DispatchQueue.main.async {
            self.testResult = result
            self.isTesting = false
        }
    }
}

// MARK: - Command Analysis Models
struct CommandAnalysis: Identifiable {
    let id = UUID()
    let text: String
    let count: Int
    let category: CommandCategory
    var lastUsed: Date
}

enum CommandCategory: String {
    case fileOps = "File Operations"
    case systemInfo = "System Info"
    case network = "Network"
    case git = "Git"
    case textEditor = "Text Editor"
    case packageMgr = "Package Manager"
    case systemCtl = "System Control"
    case userMgmt = "User Management"
    case other = "Other"

    var icon: String {
        switch self {
        case .fileOps: return "doc.text"
        case .systemInfo: return "chart.bar"
        case .network: return "network"
        case .git: return "branch"
        case .textEditor: return "text.alignleft"
        case .packageMgr: return "cube.box"
        case .systemCtl: return "gearshape"
        case .userMgmt: return "person.2"
        case .other: return "terminal"
        }
    }

    var color: Color {
        switch self {
        case .fileOps: return .blue
        case .systemInfo: return .green
        case .network: return .purple
        case .git: return .orange
        case .textEditor: return .cyan
        case .packageMgr: return .pink
        case .systemCtl: return .red
        case .userMgmt: return .indigo
        case .other: return .gray
        }
    }
}

// MARK: - Command Stats View
struct CommandStatsView: View {
    let commands: [CommandAnalysis]

    var totalCommands: Int {
        commands.reduce(0) { $0 + $1.count }
    }

    var uniqueCommands: Int {
        commands.count
    }

    var topCategory: (category: CommandCategory, count: Int)? {
        var categoryCounts: [CommandCategory: Int] = [:]
        for cmd in commands {
            categoryCounts[cmd.category, default: 0] += cmd.count
        }
        guard let max = categoryCounts.max(by: { $0.value < $1.value }) else {
            return nil
        }
        return (category: max.key, count: max.value)
    }

    var body: some View {
        HStack(spacing: 16) {
            StatItem(icon: "number", label: "\(uniqueCommands)", subtitle: "Unique")

            Divider()
                .frame(height: 30)

            StatItem(icon: "arrow.clockwise", label: "\(totalCommands)", subtitle: "Total")

            if let top = topCategory {
                Divider()
                    .frame(height: 30)

                HStack(spacing: 4) {
                    Image(systemName: top.category.icon)
                        .foregroundColor(top.category.color)
                    Text("\(top.category.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .font(.system(.body, design: .rounded))
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(label)
                .font(.headline)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Command Analysis Row
struct CommandAnalysisRow: View {
    let analysis: CommandAnalysis
    let onTap: () -> Void
    let onExecute: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Category icon
                Image(systemName: analysis.category.icon)
                    .foregroundColor(analysis.category.color)
                    .frame(width: 20)

                // Command text
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.text)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        // Category badge
                        Text(analysis.category.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(analysis.category.color.opacity(0.15))
                            .foregroundStyle(analysis.category.color)
                            .cornerRadius(4)

                        // Frequency
                        Text("×\(analysis.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Quick execute button
                Button(action: onExecute) {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Command Detail View
struct CommandDetailView: View {
    let analysis: CommandAnalysis
    let context: TerminalContext
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Command header
                    VStack(alignment: .leading, spacing: 8) {
                        Label(analysis.category.rawValue, systemImage: analysis.category.icon)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(analysis.category.color.opacity(0.15))
                            .foregroundStyle(analysis.category.color)
                            .cornerRadius(6)

                        Text(analysis.text)
                            .font(.system(.title2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(10)

                    // Statistics
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Usage Statistics")
                            .font(.headline)

                        HStack {
                            Label("Used \(analysis.count) times", systemImage: "arrow.clockwise")
                            Spacer()
                        }

                        HStack {
                            Label("Category: \(analysis.category.rawValue)", systemImage: analysis.category.icon)
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(10)

                    // Quick actions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick Actions")
                            .font(.headline)

                        Button(action: {
                            context.insertBuffer(analysis.text + "\n")
                            dismiss()
                        }) {
                            Label("Execute Command", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: {
                            UIPasteboard.general.string = analysis.text
                        }) {
                            Label("Copy to Clipboard", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(10)

                    // Command explanation (future enhancement)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About This Command")
                            .font(.headline)

                        Text("Command explanations and AI-powered suggestions will be available in future updates.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Command Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
