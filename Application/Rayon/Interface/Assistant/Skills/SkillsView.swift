//
//  SkillsView.swift
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

// MARK: - Main Skills View

struct SkillsView: View {
    @StateObject var context: TerminalManager.Context
    @ObservedObject var skillRegistry = SkillRegistry.shared
    @State private var selectedTab: SkillsTab = .skills
    @State private var searchText = ""
    @State private var selectedSkill: Skill?
    @State private var showingSkillDetail = false
    @State private var showingCreateSkill = false

    enum SkillsTab: String, CaseIterable {
        case skills = "Browse"
        case executing = "Running"
        case history = "History"
    }

    var filteredSkills: [Skill] {
        if searchText.isEmpty {
            return skillRegistry.allEnabledSkills
        }
        return skillRegistry.searchSkills(searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("", selection: $selectedTab) {
                ForEach(SkillsTab.allCases, id: \.self) { tab in
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
                    case .skills:
                        skillsBrowserView
                    case .executing:
                        activeExecutionsView
                    case .history:
                        executionHistoryView
                    }
                }
            }
        }
        .sheet(isPresented: $showingSkillDetail) {
            if let skill = selectedSkill {
                SkillDetailView(skill: skill, context: context)
            }
        }
        .sheet(isPresented: $showingCreateSkill) {
            SkillCreationView(context: context)
        }
    }

    // MARK: - Skills Browser

    private var skillsBrowserView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search skills...", text: $searchText)
                    .textFieldStyle(.plain)
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

            // Skill suggestions based on terminal output
            SkillSuggestionsView(context: context)

            Divider()

            // Skills by category
            if filteredSkills.isEmpty {
                emptyStateView
            } else {
                skillsByCategory
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(searchText.isEmpty ? "No Skills Available" : "No Skills Found")
                .font(.headline)

            Text(searchText.isEmpty ?
                 "Skills help you troubleshoot and fix common issues" :
                 "Try a different search term")
                .font(.caption)
                .foregroundColor(.secondary)

            if searchText.isEmpty {
                Button("Create Custom Skill") {
                    showingCreateSkill = true
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    private var skillsByCategory: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(SkillCategory.allCases, id: \.self) { category in
                let skillsInCategory = filteredSkills.filter { $0.category == category }
                if !skillsInCategory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        // Category header
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundColor(Color(category.color))
                            Text(category.rawValue)
                                .font(.headline)
                            Text("(\(skillsInCategory.count))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        // Skill cards
                        ForEach(skillsInCategory) { skill in
                            SkillCard(
                                skill: skill,
                                onTap: {
                                    selectedSkill = skill
                                    showingSkillDetail = true
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(.vertical)
    }

    // MARK: - Active Executions

    private var activeExecutionsView: some View {
        Group {
            if skillRegistry.activeExecutions.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "play.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Active Executions")
                        .font(.headline)

                    Text("Skills you run will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(skillRegistry.activeExecutions) { execution in
                        ActiveExecutionCard(execution: execution, context: context)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Execution History

    private var executionHistoryView: some View {
        Group {
            if skillRegistry.executionHistory.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No History")
                        .font(.headline)

                    Text("Completed skill executions will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(skillRegistry.recentExecutions()) { summary in
                        ExecutionHistoryCard(summary: summary)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Skill Card

struct SkillCard: View {
    let skill: Skill
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: skill.category.icon)
                    .foregroundColor(Color(skill.category.color))
                    .font(.system(size: 24))
                    .frame(width: 32)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(skill.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    // Metadata
                    HStack(spacing: 8) {
                        Label("\(skill.steps.count) steps", systemImage: "list.bullet")
                            .font(.caption2)

                        Label(formatDuration(skill.estimatedDuration), systemImage: "clock")
                            .font(.caption2)

                        if !skill.requiredPrivileges.isEmpty {
                            Label("sudo", systemImage: "lock.shield")
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .second]
        return formatter.string(from: duration) ?? "\(duration)s"
    }
}

// MARK: - Active Execution Card

struct ActiveExecutionCard: View {
    @ObservedObject var execution: SkillExecution
    let context: TerminalManager.Context

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: execution.status.icon)
                    .foregroundColor(Color(execution.status.color))

                Text(execution.skill.name)
                    .font(.headline)

                Spacer()

                Text("\(Int(execution.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: execution.progress)

            HStack {
                Text("Step \(execution.currentStepIndex + 1) of \(execution.skill.steps.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Cancel") {
                    execution.cancel()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Execution History Card

struct ExecutionHistoryCard: View {
    let summary: SkillExecution.Summary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: summary.status.icon)
                .foregroundColor(Color(summary.status.color))
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.skillName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(summary.status.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(summary.durationFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(summary.stepsCompleted)/\(summary.totalSteps) steps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Skill Suggestions View

struct SkillSuggestionsView: View {
    @StateObject var context: TerminalManager.Context
    @State private var suggestions: [SkillSuggestion] = []
    @State private var isAnalyzing = false

    var body: some View {
        Group {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)

                        Text("Suggested Skills")
                            .font(.headline)

                        Spacer()

                        Button("Dismiss") {
                            suggestions = []
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)

                    ForEach(suggestions.prefix(3)) { suggestion in
                        SuggestionCard(suggestion: suggestion, context: context)
                    }
                }
                .padding(.vertical)
                .background(Color.yellow.opacity(0.1))
            }
        }
        .onAppear {
            analyzeOutput()
        }
    }

    private func analyzeOutput() {
        isAnalyzing = true

        Task {
            let detector = SkillTriggerDetector()
            let output = context.getOutputHistoryStrippedANSI()

            if output.count > 100 {
                let lastOutput = String(output.suffix(5000))
                suggestions = detector.detectSkills(in: lastOutput)
            }

            isAnalyzing = false
        }
    }
}

// MARK: - Suggestion Card

struct SuggestionCard: View {
    let suggestion: SkillSuggestion
    let context: TerminalManager.Context
    @State private var isRunning = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.skill.category.icon)
                .foregroundColor(Color(suggestion.skill.category.color))
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.skill.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isRunning {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("Run") {
                    runSkill()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func runSkill() {
        isRunning = true

        Task {
            let executor = SkillExecutor()
            await executor.execute(skill: suggestion.skill, shell: context.shell) { result in
                DispatchQueue.main.async {
                    isRunning = false
                }
            }
        }
    }
}
