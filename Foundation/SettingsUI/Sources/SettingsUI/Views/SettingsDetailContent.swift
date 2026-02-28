//
//  SettingsDetailContent.swift
//  SettingsUI
//
//  Created for GoodTerm
//

#if canImport(AppKit)
import AppKit
#endif
import DataSync
import MachineStatus
import Premium
import RayonModule
#if canImport(Speech)
import Speech
#endif
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Detail Content
public struct SettingsDetailContent: View {
    public let item: SettingsItem
    @EnvironmentObject var store: RayonStore
    @ObservedObject var syncManager = AutoSyncManager.shared
    @ObservedObject var premium = PremiumManager.shared
    @ObservedObject private var automation = AutomationManager.shared

    @State private var snapshotReason: String = "manual"
    @State private var taskName: String = ""
    @State private var selectedSnippetId: UUID?
    @State private var selectedMachineIds: Set<UUID> = []
    @State private var scheduleKind: AutomationSchedule.Kind = .manual
    @State private var intervalMinutes: Int = 30
    @State private var dailyHour: Int = 2
    @State private var dailyMinute: Int = 0
    @State private var selectedMachineForMonitor: UUID?
    @State private var cpuThreshold: Double = Double(MonitorThresholdProfile.default.cpuPercent)
    @State private var memoryThreshold: Double = Double(MonitorThresholdProfile.default.memoryPercent)
    @State private var diskThreshold: Double = Double(MonitorThresholdProfile.default.diskPercent)
    @State private var showingThanks = false
    @State private var showingLicense = false

    #if os(iOS)
        @State private var exportDocument: ExportDocument?
        @State private var exportName: String = "monitor-report.csv"
        @State private var exportType: UTType = .commaSeparatedText
        @State private var showingExporter = false
    #endif

    private var snapshots: [SyncSnapshot] {
        store.listSyncSnapshots().sorted { $0.createdAt > $1.createdAt }
    }

    private var machines: [RDMachine] {
        store.machineGroup.machines.filter { $0.isNotPlaceholder() }.sorted { $0.name < $1.name }
    }

    private var snippets: [RDSnippet] {
        store.snippetGroup.snippets.sorted { $0.name < $1.name }
    }

    private var trendSamples: [MonitorTelemetrySample] {
        guard let machineId = selectedMachineForMonitor else { return [] }
        return MonitorTelemetryManager.shared.trend(for: machineId, within: 24)
    }

    public var body: some View {
        detailContentForItem
            .onAppear {
                if selectedSnippetId == nil { selectedSnippetId = snippets.first?.id }
                if selectedMachineForMonitor == nil {
                    selectedMachineForMonitor = machines.first?.id
                    loadThresholdForSelectedMachine()
                }
                Task { await premium.refreshSubscriptionStatus() }
            }
            .onChange(of: selectedMachineForMonitor) { _, _ in
                loadThresholdForSelectedMachine()
            }
            .sheet(isPresented: $showingThanks) {
                ThanksView()
                    #if os(macOS)
                    .frame(minWidth: 700, minHeight: 500)
                    #endif
            }
            .sheet(isPresented: $showingLicense) {
                LicenseView()
                    #if os(macOS)
                    .frame(minWidth: 700, minHeight: 500)
                    #endif
            }
            #if os(iOS)
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: exportType,
                defaultFilename: exportName
            ) { _ in
                exportDocument = nil
            }
            #endif
    }

    @ViewBuilder
    private var detailContentForItem: some View {
        switch item {
        // About
        case .appInfo:
            appInfoView
        case .documents:
            documentsView

        // Appearance
        case .appTheme:
            appThemeView
        case .terminalTheme:
            terminalThemeView
        case .effects:
            effectsView

        // Premium
        case .subscriptionStatus:
            subscriptionStatusPlaceholderView
        case .premiumFeatures:
            premiumFeaturesView

        // Sync & Automation
        case .cloudSync:
            cloudSyncView
        case .snapshots:
            snapshotsView
        case .automation:
            automationView
        case .monitoring:
            monitoringView

        // AI
        case .aiConfiguration:
            aiConfigurationView

        // Advanced
        case .applicationSettings:
            applicationSettingsView
        case .connectionSettings:
            connectionSettingsView
        case .fileTransferSettings:
            fileTransferSettingsView
        case .tmuxSettings:
            tmuxSettingsView
        case .voiceSettings:
            voiceSettingsView

        default:
            Text("Coming Soon")
        }
    }

    // MARK: - About Views

    private var appInfoView: some View {
        Section("App") {
            HStack {
                Text("Name")
                Spacer()
                Text("GoodTerm")
            }

            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
            }

            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
            }
        }
    }

    private var documentsView: some View {
        Section("Documents") {
            tappableTextRow("Thanks") { showingThanks = true }
            tappableTextRow("Software License") { showingLicense = true }
        }
    }

    // MARK: - Appearance Views

    private var appThemeView: some View {
        Section("Appearance") {
            HStack {
                Text("Appearance")
                Spacer()
                Picker("Appearance", selection: $store.themePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .labelsHidden()
            }
        }
    }

    private var terminalThemeView: some View {
        Section("Terminal") {
            HStack {
                Text("Terminal Theme")
                Spacer()
                Picker("Terminal Theme", selection: $store.terminalThemeName) {
                    ForEach(TerminalTheme.allThemes, id: \.name) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("Terminal Font")
                Spacer()
                Picker("Terminal Font", selection: $store.terminalFontName) {
                    Text("Menlo").tag("Menlo")
                    Text("Monaco").tag("Monaco")
                    Text("SF Mono").tag("SF Mono")
                    Text("FiraCode Nerd Font Mono").tag("FiraCode Nerd Font Mono")
                    Text("Maple Mono NF CN").tag("Maple Mono NF CN")
                    Text("Cascadia Code NF").tag("Cascadia Code NF")
                    Text("Cascadia Mono NF").tag("Cascadia Mono NF")
                    Text("Hack Nerd Font Mono").tag("Hack Nerd Font Mono")
                    Text("Inconsolata Nerd Font Mono").tag("Inconsolata Nerd Font Mono")
                    Text("JetBrains Mono").tag("JetBrains Mono")
                    Text("Source Code Pro").tag("Source Code Pro")
                }
                .labelsHidden()
            }

            HStack {
                Text("Terminal Font Size")
                Spacer()
                Text("\(store.terminalFontSize)")
                    .foregroundStyle(.secondary)
                Stepper("", value: $store.terminalFontSize, in: 5...30)
                    .labelsHidden()
            }
        }
    }

    private var effectsView: some View {
        Section("Effects") {
            HStack {
                Text("Reduced Effect")
                Spacer()
                Toggle("", isOn: $store.reducedViewEffects)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Premium Views

    private var subscriptionStatusPlaceholderView: some View {
        Section("Subscription Status") {
            Text("Premium subscription management is available in the app.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var premiumFeaturesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeatureRow(icon: "infinity", title: "Unlimited Connections", description: "Connect to unlimited number of servers")
            Divider()
                .padding(.leading, 40)
            FeatureRow(icon: "bolt.fill", title: "Advanced Monitoring", description: "Real-time system status and alerts")
            Divider()
                .padding(.leading, 40)
            FeatureRow(icon: "brain.head.profile", title: "AI Assistant", description: "Smart command suggestions and explanations")
            Divider()
                .padding(.leading, 40)
            FeatureRow(icon: "folder.fill", title: "File Transfer", description: "Enhanced file transfer capabilities")
            Divider()
                .padding(.leading, 40)
            FeatureRow(icon: "moon.fill", title: "Dark Mode Themes", description: "Premium terminal color schemes")
        }
    }

    // MARK: - Sync & Automation Views

    private var cloudSyncView: some View {
        Section("Sync") {
            HStack(spacing: 12) {
                Button {
                    Task { await performSync() }
                } label: {
                    if syncManager.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Sync Now", systemImage: "arrow.counterclockwise.icloud")
                    }
                }
                .disabled(syncManager.isSyncing)

                Text("Last sync: \(lastSyncDateString)")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            if let error = syncManager.syncError {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }

    private var snapshotsView: some View {
        Section("Cloud Backup Snapshots") {
            HStack {
                TextField("Snapshot reason", text: $snapshotReason)
                    #if os(macOS)
                    .textFieldStyle(.plain)
                    #endif
                    .textFieldStyle(.roundedBorder)
                Button("Create Snapshot") {
                    guard premium.isSubscribed else { return }
                    let reason = snapshotReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.createSyncSnapshot(reason: reason.isEmpty ? "manual" : reason)
                }
                .disabled(!premium.isSubscribed)
            }

            ForEach(Array(snapshots.prefix(8)), id: \.id) { snapshot in
                HStack {
                    Text(snapshot.reason).lineLimit(1)
                    Spacer()
                    Text(snapshot.createdAt, style: .date).foregroundColor(.secondary).font(.caption)
                    Button("Rollback") {
                        guard premium.isSubscribed else { return }
                        _ = store.rollbackSyncSnapshot(id: snapshot.id)
                    }
                    .disabled(!premium.isSubscribed)
                }
            }
        }
    }

    private var automationView: some View {
        Group {
            Section("Create Automation Task") {
                HStack {
                    Text("Task name")
                    Spacer()
                    TextField("", text: $taskName)
                        #if os(macOS)
                        .textFieldStyle(.plain)
                        #endif
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Snippet Template")
                    Spacer()
                    Picker("Snippet Template", selection: Binding<UUID>(
                        get: { selectedSnippetId ?? snippets.first?.id ?? UUID() },
                        set: { selectedSnippetId = $0 }
                    )) {
                        ForEach(snippets, id: \.id) { snippet in
                            Text(snippet.name.isEmpty ? snippet.id.uuidString : snippet.name).tag(snippet.id)
                        }
                    }
                    .labelsHidden()
                    .disabled(snippets.isEmpty)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Machines")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ForEach(machines, id: \.id) { machine in
                        HStack {
                            Text(machine.name)
                            Spacer()
                            Toggle("", isOn: Binding<Bool>(
                                get: { selectedMachineIds.contains(machine.id) },
                                set: { enabled in
                                    if enabled { selectedMachineIds.insert(machine.id) }
                                    else { selectedMachineIds.remove(machine.id) }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Text("Schedule")
                    Spacer()
                    Picker("Schedule", selection: $scheduleKind) {
                        Text("Manual").tag(AutomationSchedule.Kind.manual)
                        Text("Interval").tag(AutomationSchedule.Kind.interval)
                        Text("Daily").tag(AutomationSchedule.Kind.daily)
                    }
                    #if os(macOS)
                    .pickerStyle(.segmented)
                    #endif
                    .labelsHidden()
                }

                if scheduleKind == .interval {
                    HStack {
                        Text("Every")
                        Spacer()
                        HStack(spacing: 8) {
                            Text("\(intervalMinutes)")
                                .foregroundStyle(.secondary)
                            Stepper("", value: $intervalMinutes, in: 5...1440, step: 5)
                                .labelsHidden()
                            Text("minutes")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if scheduleKind == .daily {
                    HStack {
                        Text("Hour")
                        Spacer()
                        Text("\(dailyHour)")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $dailyHour, in: 0...23)
                            .labelsHidden()
                    }

                    HStack {
                        Text("Minute")
                        Spacer()
                        Text("\(dailyMinute)")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $dailyMinute, in: 0...59)
                            .labelsHidden()
                    }
                }

                tappableTextRow(
                    "Create Task",
                    isDisabled: !premium.isSubscribed || snippets.isEmpty || machines.isEmpty
                ) {
                    guard premium.isSubscribed else { return }
                    guard let snippetId = selectedSnippetId else { return }
                    guard !taskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    guard !selectedMachineIds.isEmpty else { return }

                    let schedule = AutomationSchedule(kind: scheduleKind, intervalMinutes: intervalMinutes, hour: dailyHour, minute: dailyMinute)
                    automation.upsertTask(
                        AutomationTask(name: taskName, snippetId: snippetId, machineIds: Array(selectedMachineIds), schedule: schedule)
                    )
                    taskName = ""
                }
            }

            Section("Tasks") {
                ForEach(automation.tasks, id: \.id) { task in
                    HStack {
                        Toggle("", isOn: Binding<Bool>(
                            get: { task.enabled },
                            set: { enabled in
                                var updated = task
                                updated.enabled = enabled
                                automation.upsertTask(updated)
                            }
                        ))
                        .labelsHidden()
                        Text(task.name)
                        Spacer()
                        Button("Run") { Task { await automation.runNow(taskId: task.id) } }
                            .disabled(!premium.isSubscribed)
                            .controlSize(.small)
                        Button("Delete") { automation.removeTask(id: task.id) }
                            .disabled(!premium.isSubscribed)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var monitoringView: some View {
        Section("Monitoring Thresholds & Export") {
            HStack {
                Text("Machine")
                Spacer()
                Picker("Machine", selection: Binding<UUID>(
                    get: { selectedMachineForMonitor ?? machines.first?.id ?? UUID() },
                    set: { selectedMachineForMonitor = $0 }
                )) {
                    ForEach(machines, id: \.id) { machine in
                        Text(machine.name).tag(machine.id)
                    }
                }
                .labelsHidden()
                .disabled(machines.isEmpty)
            }

            HStack {
                Text("CPU")
                Spacer()
                Picker("CPU", selection: $cpuThreshold) {
                    Text("70%").tag(70.0)
                    Text("75%").tag(75.0)
                    Text("80%").tag(80.0)
                    Text("85%").tag(85.0)
                    Text("90%").tag(90.0)
                    Text("95%").tag(95.0)
                }
                .labelsHidden()
            }

            HStack {
                Text("Memory")
                Spacer()
                Picker("Memory", selection: $memoryThreshold) {
                    Text("70%").tag(70.0)
                    Text("75%").tag(75.0)
                    Text("80%").tag(80.0)
                    Text("85%").tag(85.0)
                    Text("90%").tag(90.0)
                    Text("95%").tag(95.0)
                }
                .labelsHidden()
            }

            HStack {
                Text("Disk")
                Spacer()
                Picker("Disk", selection: $diskThreshold) {
                    Text("70%").tag(70.0)
                    Text("75%").tag(75.0)
                    Text("80%").tag(80.0)
                    Text("85%").tag(85.0)
                    Text("90%").tag(90.0)
                    Text("95%").tag(95.0)
                }
                .labelsHidden()
            }

            HStack(spacing: 12) {
                Button("Save Thresholds") {
                    guard premium.isSubscribed, let machineId = selectedMachineForMonitor else { return }
                    MonitorTelemetryManager.shared.setThreshold(
                        machineId: machineId,
                        profile: .init(cpuPercent: Float(cpuThreshold), memoryPercent: Float(memoryThreshold), diskPercent: Float(diskThreshold))
                    )
                }
                .disabled(!premium.isSubscribed || selectedMachineForMonitor == nil)

                #if os(macOS)
                Button("Export CSV") { exportTrend(format: .csv) }
                    .disabled(!premium.isSubscribed || selectedMachineForMonitor == nil)
                    .controlSize(.small)
                Button("Export JSON") { exportTrend(format: .json) }
                    .disabled(!premium.isSubscribed || selectedMachineForMonitor == nil)
                    .controlSize(.small)
                #else
                Button("Export CSV Report") {
                    guard premium.isSubscribed, let machineId = selectedMachineForMonitor else { return }
                    let csv = MonitorTelemetryManager.shared.csv(for: machineId)
                    exportDocument = ExportDocument(data: Data(csv.utf8))
                    exportName = "monitor-report.csv"
                    exportType = .commaSeparatedText
                    showingExporter = true
                }
                .disabled(!premium.isSubscribed || selectedMachineForMonitor == nil)

                Button("Export JSON Report") {
                    guard premium.isSubscribed, let machineId = selectedMachineForMonitor else { return }
                    exportDocument = ExportDocument(data: MonitorTelemetryManager.shared.json(for: machineId))
                    exportName = "monitor-report.json"
                    exportType = .json
                    showingExporter = true
                }
                .disabled(!premium.isSubscribed || selectedMachineForMonitor == nil)
                #endif
            }

            if !trendSamples.isEmpty {
                let cpuAvg = trendSamples.map(\.cpuPercent).reduce(0, +) / Float(trendSamples.count)
                let memAvg = trendSamples.map(\.memoryPercent).reduce(0, +) / Float(trendSamples.count)
                let diskAvg = trendSamples.map(\.diskPercent).reduce(0, +) / Float(trendSamples.count)
                Text("24h trends: \(trendSamples.count) points, avg CPU \(Int(cpuAvg))%, avg Memory \(Int(memAvg))%, avg Disk \(Int(diskAvg))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - AI Views

    private var aiConfigurationView: some View {
        AIConfigurationContent()
    }

    private struct AIConfigurationContent: View {
        @ObservedObject private var aiAssistant = AIAssistant.shared
        @State private var isTesting = false
        @State private var testResult: AIAssistant.TestResult?

        var body: some View {
            Group {
                statusSection
                configurationSection
                featuresSection
            }
        }

        private var statusSection: some View {
            Section("Status") {
                Toggle("Enable AI Assistant", isOn: $aiAssistant.isEnabled)
            }
        }

        private var configurationSection: some View {
            Section("Configuration") {
                Picker("AI Provider", selection: $aiAssistant.provider) {
                    ForEach(AIAssistant.AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                SecureField("API Key", text: $aiAssistant.apiKey)

                TextField("Custom Base URL (optional)", text: $aiAssistant.customBaseURL)
                    .disableAutocorrection(true)

                TextField("Custom Model (optional)", text: $aiAssistant.customModel)
                    .disableAutocorrection(true)

                Button(action: {
                    Task {
                        await testAPIConnection()
                    }
                }) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Testing...")
                        } else {
                            Image(systemName: "checkmark.circle")
                            Text("Test Connection")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTesting || aiAssistant.apiKey.isEmpty)

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

                Divider()

                VStack(alignment: .leading, spacing: 4) {
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
            }
        }

        private var featuresSection: some View {
            Section("Features") {
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

    // MARK: - Advanced Views

    private var applicationSettingsView: some View {
        Section("Application") {
            HStack {
                Text("Disable Confirmation")
                Spacer()
                Toggle("", isOn: $store.disableConformation)
                    .labelsHidden()
            }

            HStack {
                Text("Record Recent")
                Spacer()
                Toggle("", isOn: $store.storeRecent)
                    .labelsHidden()
            }

            #if os(iOS)
            HStack {
                Text("Open at Connect")
                Spacer()
                Toggle("", isOn: $store.openInterfaceAutomatically)
                    .labelsHidden()
            }
            #endif
        }
    }

    private var connectionSettingsView: some View {
        Section("Connection") {
            HStack {
                Text("Timeout")
                Spacer()
                Picker("Timeout", selection: $store.timeout) {
                    Text("2s").tag(2)
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("15s").tag(15)
                    Text("20s").tag(20)
                    Text("30s").tag(30)
                }
                .labelsHidden()
            }

            HStack {
                Text("Monitor interval")
                Spacer()
                Picker("Monitor interval", selection: $store.monitorInterval) {
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("45s").tag(45)
                    Text("60s").tag(60)
                }
                .labelsHidden()
            }
        }
    }

    private var fileTransferSettingsView: some View {
        Section("File Transfer") {
            HStack {
                Text("Conflict Policy")
                Spacer()
                Picker("Conflict Policy", selection: $store.fileTransferConflictPolicy) {
                    Text("Rename").tag("rename")
                    Text("Overwrite").tag("overwrite")
                    Text("Skip").tag("skip")
                }
                .labelsHidden()
            }

            HStack {
                Text("Max Concurrent Transfers")
                Spacer()
                Text("\(store.fileTransferMaxConcurrent)")
                    .foregroundStyle(.secondary)
                Stepper("", value: $store.fileTransferMaxConcurrent, in: 1...16)
                    .labelsHidden()
            }

            HStack {
                Text("Rate Limit (KB/s)")
                Spacer()
                Text("\(store.fileTransferRateLimitKBps)")
                    .foregroundStyle(.secondary)
                Stepper("", value: $store.fileTransferRateLimitKBps, in: 0...20000, step: 100)
                    .labelsHidden()
            }

            HStack {
                Text("Enable Resume for Failed Transfers")
                Spacer()
                Toggle("", isOn: $store.fileTransferResumeEnabled)
                    .labelsHidden()
            }
        }
    }

    private var tmuxSettingsView: some View {
        Section("Tmux") {
            HStack {
                Text("Use Tmux Session")
                Spacer()
                Toggle("", isOn: $store.useTmux)
                    .labelsHidden()
            }

            if store.useTmux {
                HStack {
                    Text("Tmux Session Name")
                    Spacer()
                    TextField("", text: $store.tmuxSessionName)
                        #if os(macOS)
                        .textFieldStyle(.plain)
                        #endif
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Auto-create Session")
                    Spacer()
                    Toggle("", isOn: $store.tmuxAutoCreate)
                        .labelsHidden()
                }
            }
        }
    }

    private var voiceSettingsView: some View {
        Section("Voice Input") {
            HStack {
                Text("Engine")
                Spacer()
                Picker("Engine", selection: $store.speechInputEngine) {
                    ForEach(speechEngineOptions, id: \.id) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("Language")
                Spacer()
                Picker("Language", selection: $store.speechInputLocaleIdentifier) {
                    ForEach(speechLanguageOptions, id: \.id) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .labelsHidden()
            }

            Text("Changes apply to terminal voice input immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var speechEngineOptions: [(id: String, name: String)] {
        [
            ("apple", "Apple Speech"),
            ("disabled", "Disabled"),
        ]
    }

    private var speechLanguageOptions: [(id: String, name: String)] {
        var options: [(id: String, name: String)] = [("system", "System Default")]
        #if canImport(Speech)
        let locales = SFSpeechRecognizer.supportedLocales().sorted {
            $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending
        }
        options.append(contentsOf: locales.map { locale in
            let localized = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            return (locale.identifier, localized)
        })
        #endif
        if options.contains(where: { $0.id == store.speechInputLocaleIdentifier }) == false {
            options.append((store.speechInputLocaleIdentifier, store.speechInputLocaleIdentifier))
        }
        return options
    }

    // MARK: - Helper Methods

    private var lastSyncDateString: String {
        guard let date = syncManager.lastSyncDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func tappableTextRow(_ title: String, isDisabled: Bool = false, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(isDisabled ? .secondary : .primary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDisabled else { return }
            action()
        }
    }

    private func performSync() async {
        if #available(macOS 12.0, iOS 15.0, *) {
            await RayonStore.shared.syncAllDataToCloud(reason: "manual")
        }
    }

    private func loadThresholdForSelectedMachine() {
        guard let machineId = selectedMachineForMonitor else { return }
        let profile = MonitorTelemetryManager.shared.threshold(for: machineId)
        cpuThreshold = Double(profile.cpuPercent)
        memoryThreshold = Double(profile.memoryPercent)
        diskThreshold = Double(profile.diskPercent)
    }

    #if os(macOS)
        private enum ExportFormat { case csv, json }

        private func exportTrend(format: ExportFormat) {
            guard let machineId = selectedMachineForMonitor else { return }
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = format == .csv ? "monitor-report.csv" : "monitor-report.json"
            panel.allowedContentTypes = format == .csv ? [.commaSeparatedText] : [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                if format == .csv {
                    try MonitorTelemetryManager.shared.exportCSV(for: machineId, to: url)
                } else {
                    try MonitorTelemetryManager.shared.exportJSON(for: machineId, to: url)
                }
            } catch {
                #if os(macOS)
                // UIBridge is a Rayon app-specific utility
                // For SettingsUI module, we'll use Alert instead
                NSAlert(error: error)
                #else
                print("Export failed: \(error.localizedDescription)")
                #endif
            }
        }
    #endif
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - iOS Export Document
#if os(iOS)
    struct ExportDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.plainText, .json] }
        let data: Data

        init(data: Data) {
            self.data = data
        }

        init(configuration: ReadConfiguration) throws {
            self.data = configuration.file.regularFileContents ?? Data()
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }
#endif

// MARK: - Monitor Models
public struct MonitorThresholdProfile: Codable, Equatable {
    public var cpuPercent: Float
    public var memoryPercent: Float
    public var diskPercent: Float

    public static let `default` = MonitorThresholdProfile(cpuPercent: 85, memoryPercent: 90, diskPercent: 90)

    public init(cpuPercent: Float, memoryPercent: Float, diskPercent: Float) {
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.diskPercent = diskPercent
    }
}

public struct MonitorTelemetrySample: Codable, Identifiable, Equatable {
    public let id: UUID
    public let machineId: UUID
    public let machineName: String
    public let timestamp: Date
    public let cpuPercent: Float
    public let memoryPercent: Float
    public let diskPercent: Float
    public let load1: Float

    public init(
        id: UUID = UUID(),
        machineId: UUID,
        machineName: String,
        timestamp: Date = Date(),
        cpuPercent: Float,
        memoryPercent: Float,
        diskPercent: Float,
        load1: Float
    ) {
        self.id = id
        self.machineId = machineId
        self.machineName = machineName
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.diskPercent = diskPercent
        self.load1 = load1
    }
}

public final class MonitorTelemetryManager {
    public static let shared = MonitorTelemetryManager()

    private let queue = DispatchQueue(label: "wiki.qaq.settingsui.monitor.telemetry", qos: .utility)
    private let sampleStoreKey = "wiki.qaq.settingsui.monitor.samples.v1"
    private let thresholdStoreKey = "wiki.qaq.settingsui.monitor.thresholds.v1"
    private let maxSamples = 5000

    private var samples: [MonitorTelemetrySample] = []
    private var thresholds: [UUID: MonitorThresholdProfile] = [:]

    private init() {
        load()
    }

    public func appendSample(machineId: UUID, machineName: String, status: ServerStatus) {
        let diskPercent = status.fileSystem.elements.map(\.percent).max() ?? 0
        let sample = MonitorTelemetrySample(
            machineId: machineId,
            machineName: machineName,
            cpuPercent: status.processor.summary.sumUsed,
            memoryPercent: status.memory.phyUsed * 100,
            diskPercent: diskPercent,
            load1: status.system.load1
        )

        queue.async {
            self.samples.append(sample)
            if self.samples.count > self.maxSamples {
                self.samples.removeFirst(self.samples.count - self.maxSamples)
            }
            self.persistSamples()
        }
    }

    public func setThreshold(machineId: UUID, profile: MonitorThresholdProfile) {
        queue.async {
            self.thresholds[machineId] = profile
            self.persistThresholds()
        }
    }

    public func threshold(for machineId: UUID) -> MonitorThresholdProfile {
        queue.sync { thresholds[machineId] ?? .default }
    }

    public func trend(for machineId: UUID, within hours: Int) -> [MonitorTelemetrySample] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return queue.sync { samples.filter { $0.machineId == machineId && $0.timestamp >= cutoff } }
    }

    func csv(for machineId: UUID) -> String {
        let rows = queue.sync {
            var lines = ["timestamp,machine,cpu_percent,memory_percent,disk_percent,load1"]
            let formatter = ISO8601DateFormatter()
            let selected = samples.filter { $0.machineId == machineId }.sorted { $0.timestamp < $1.timestamp }
            for item in selected {
                lines.append("\(formatter.string(from: item.timestamp)),\(item.machineName),\(item.cpuPercent),\(item.memoryPercent),\(item.diskPercent),\(item.load1)")
            }
            return lines
        }
        return rows.joined(separator: "\n")
    }

    func json(for machineId: UUID) -> Data {
        let selected = queue.sync { samples.filter { $0.machineId == machineId }.sorted { $0.timestamp < $1.timestamp } }
        return (try? JSONEncoder().encode(selected)) ?? Data()
    }

    #if os(macOS)
        func exportCSV(for machineId: UUID, to url: URL) throws {
            let csv = csv(for: machineId)
            try csv.write(to: url, atomically: true, encoding: .utf8)
        }

        func exportJSON(for machineId: UUID, to url: URL) throws {
            let data = json(for: machineId)
            try data.write(to: url)
        }
    #endif

    private func load() {
        if let data = UserDefaults.standard.data(forKey: sampleStoreKey),
           let decoded = try? JSONDecoder().decode([MonitorTelemetrySample].self, from: data) {
            samples = decoded
        }
        if let data = UserDefaults.standard.data(forKey: thresholdStoreKey),
           let decoded = try? JSONDecoder().decode([UUID: MonitorThresholdProfile].self, from: data) {
            thresholds = decoded
        }
    }

    private func persistSamples() {
        if let data = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(data, forKey: sampleStoreKey)
        }
    }

    private func persistThresholds() {
        if let data = try? JSONEncoder().encode(thresholds) {
            UserDefaults.standard.set(data, forKey: thresholdStoreKey)
        }
    }
}
