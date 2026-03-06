//
//  SkillCreationView.swift
//  Rayon (macOS)
//
//  Created by Claude on 2026/2/7.
//

import MachineStatus
import MachineStatusView
import NSRemoteShell
import RayonModule
import SwiftUI
import SwiftTerminal

// MARK: - Skill Creation View

struct SkillCreationView: View {
    let context: TerminalManager.Context
    @Environment(\.dismiss) var dismiss
    @ObservedObject var skillRegistry = SkillRegistry.shared

    @State private var skillName = ""
    @State private var skillDescription = ""
    @State private var selectedCategory: SkillCategory = .system
    @State private var steps: [SkillStep] = []
    @State private var triggers: [SkillTrigger] = []
    @State private var currentStepTitle = ""
    @State private var currentStepCommand = ""
    @State private var currentStepRequiresConfirmation = true
    @State private var currentTriggerPattern = ""

    @State private var selectedTab: CreationTab = .basic
    @State private var showingHistoryPicker = false

    enum CreationTab: String, CaseIterable {
        case basic = "Basic Info"
        case steps = "Steps"
        case triggers = "Triggers"
        case preview = "Preview"
    }

    var body: some View {
        NavigationView {
            Form {
                // Tab picker
                Picker("", selection: $selectedTab) {
                    ForEach(CreationTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())

                Divider()

                // Tab content
                switch selectedTab {
                case .basic:
                    basicInfoSection
                case .steps:
                    stepsSection
                case .triggers:
                    triggersSection
                case .preview:
                    previewSection
                }
            }
            .navigationTitle("Create Skill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSkill()
                    }
                    .disabled(skillName.isEmpty || steps.isEmpty)
                }
            }
            .sheet(isPresented: $showingHistoryPicker) {
                CommandHistoryPicker(context: context) { command in
                    currentStepCommand = command
                    showingHistoryPicker = false
                }
            }
        }
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        Group {
            Section {
                TextField("Skill Name", text: $skillName)
                TextField("Description", text: $skillDescription)

                Picker("Category", selection: $selectedCategory) {
                    ForEach(SkillCategory.allCases, id: \.self) { category in
                        Label(category.rawValue, systemImage: category.icon)
                            .tag(category)
                    }
                }
            } header: {
                Text("Basic Information")
            } footer: {
                Text("Give your skill a descriptive name and explain what it does.")
            }
        }
    }

    // MARK: - Steps Section

    private var stepsSection: some View {
        Group {
            // Add new step
            Section {
                TextField("Step Title", text: $currentStepTitle)

                HStack {
                    TextField("Command", text: $currentStepCommand)
                    Button("History") {
                        showingHistoryPicker = true
                    }
                    .buttonStyle(.bordered)
                }

                Toggle("Requires Confirmation", isOn: $currentStepRequiresConfirmation)

                Button(action: addStep) {
                    Label("Add Step", systemImage: "plus.circle.fill")
                }
                .disabled(currentStepTitle.isEmpty || currentStepCommand.isEmpty)
            } header: {
                Text("Add New Step")
            }

            // Existing steps
            Section {
                if steps.isEmpty {
                    Text("No steps added yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack {
                            Text("\(step.order)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.blue)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title)
                                    .font(.subheadline)

                                if let command = step.commandTemplate {
                                    Text(command)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button(action: { removeStep(step) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            } header: {
                Text("Steps (\(steps.count))")
            }
        }
    }

    // MARK: - Triggers Section

    private var triggersSection: some View {
        Group {
            Section {
                TextField("Error Pattern (regex)", text: $currentTriggerPattern)
                    .help("Enter a regex pattern that will trigger this skill")

                Button(action: addTrigger) {
                    Label("Add Trigger", systemImage: "plus.circle.fill")
                }
                .disabled(currentTriggerPattern.isEmpty)
            } header: {
                Text("Add Error Pattern Trigger")
            } footer: {
                Text("When this pattern is detected in terminal output, this skill will be suggested.")
            }

            Section {
                if triggers.isEmpty {
                    Text("No triggers added yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(triggers.enumerated()), id: \.self) { index, trigger in
                        if case .errorPattern(let pattern) = trigger {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)

                                Text(pattern)
                                    .font(.system(.caption, design: .monospaced))

                                Spacer()

                                Button(action: { removeTrigger(at: index) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            } header: {
                Text("Triggers (\(triggers.count))")
            }
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack {
                        Image(systemName: selectedCategory.icon)
                            .foregroundColor(Color(selectedCategory.color))
                            .font(.system(size: 32))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(skillName.isEmpty ? "Untitled Skill" : skillName)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(selectedCategory.rawValue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("Custom Skill")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }

                        Spacer()
                    }

                    Divider()

                    // Description
                    if !skillDescription.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.headline)
                            Text(skillDescription)
                                .font(.body)
                        }
                    }

                    // Metadata
                    HStack {
                        Label("\(steps.count) steps", systemImage: "list.bullet")
                        if !triggers.isEmpty {
                            Label("\(triggers.count) triggers", systemImage: "exclamationmark.triangle")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    // Steps preview
                    if !steps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Steps")
                                .font(.headline)

                            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                                HStack {
                                    Text("\(step.order)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .frame(width: 20, height: 20)
                                        .background(Color.blue)
                                        .clipShape(Circle())

                                    Text(step.title)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Actions

    private func addStep() {
        let newStep = SkillStep(
            order: steps.count + 1,
            title: currentStepTitle,
            stepType: .executeCommand,
            commandTemplate: currentStepCommand,
            requiresConfirmation: currentStepRequiresConfirmation
        )

        steps.append(newStep)

        // Clear form
        currentStepTitle = ""
        currentStepCommand = ""
        currentStepRequiresConfirmation = true
    }

    private func removeStep(_ step: SkillStep) {
        steps.removeAll { $0.id == step.id }

        // Reorder remaining steps
        for (index, _) in steps.enumerated() {
            steps[index].order = index + 1
        }
    }

    private func addTrigger() {
        triggers.append(.errorPattern(pattern: currentTriggerPattern))
        currentTriggerPattern = ""
    }

    private func removeTrigger(at index: Int) {
        triggers.remove(at: index)
    }

    private func saveSkill() {
        let newSkill = Skill(
            name: skillName,
            category: selectedCategory,
            description: skillDescription,
            triggers: triggers,
            steps: steps,
            isBuiltin: false,
            estimatedDuration: TimeInterval(steps.count * 30)
        )

        skillRegistry.registerSkill(newSkill)
        dismiss()
    }
}

// MARK: - Command History Picker

struct CommandHistoryPicker: View {
    let context: TerminalManager.Context
    let onCommandSelected: (String) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var history: [String] = []
    @State private var isLoading = false
    @State private var searchText = ""

    var filteredHistory: [String] {
        if searchText.isEmpty {
            return history
        }
        return history.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search commands...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()

                Divider()

                // Command list
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Loading history...")
                        Spacer()
                    }
                } else if filteredHistory.isEmpty {
                    VStack {
                        Spacer()
                        Text("No commands found")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List(filteredHistory, id: \.self) { command in
                        Button(action: {
                            onCommandSelected(command)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "terminal")
                                    .foregroundColor(.secondary)

                                Text(command)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(2)

                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Command")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadHistory()
            }
        }
    }

    private func loadHistory() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let history = context.getOutputHistoryStrippedANSI()

            // Extract commands from history
            let commands = extractCommands(from: history)

            DispatchQueue.main.async {
                self.history = commands
                self.isLoading = false
            }
        }
    }

    private func extractCommands(from history: String) -> [String] {
        var commands: [String] = []
        let lines = history.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines and prompts
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("$"),
                  !trimmed.hasPrefix(">"),
                  !trimmed.hasPrefix("Last login:") else {
                continue
            }

            // Simple heuristic: lines starting with common commands
            let commandPrefixes = ["sudo", "apt", "yum", "docker", "kubectl", "nginx", "systemctl", "tail", "grep", "find", "ls", "cd", "cat", "vi", "vim", "nano"]

            if commandPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
                if !commands.contains(trimmed) {
                    commands.append(trimmed)
                }
            }
        }

        return Array(commands.suffix(100)) // Last 100 commands
    }
}
