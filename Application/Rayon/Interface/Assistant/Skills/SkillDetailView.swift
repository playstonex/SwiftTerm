//
//  SkillDetailView.swift
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

// MARK: - Skill Detail View

struct SkillDetailView: View {
    let skill: Skill
    let context: TerminalManager.Context
    @Environment(\.dismiss) var dismiss
    @State private var isRunning = false
    @State private var execution: SkillExecution?
    @State private var showingExecution = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerView

                    Divider()

                    // Description
                    descriptionView

                    // Metadata
                    metadataView

                    Divider()

                    // Steps
                    stepsView

                    Divider()

                    // Actions
                    actionsView
                }
                .padding()
            }
            .navigationTitle(skill.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingExecution) {
                if let execution = execution {
                    SkillExecutionView(execution: execution, context: context)
                }
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: skill.category.icon)
                .foregroundColor(Color(skill.category.color))
                .font(.system(size: 48))

            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(skill.category.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if !skill.isBuiltin {
                    Text("Custom Skill")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
            }

            Spacer()
        }
    }

    private var descriptionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)

            Text(skill.description)
                .font(.body)
        }
    }

    private var metadataView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            HStack {
                Label("\(skill.steps.count) steps", systemImage: "list.bullet")
                Spacer()
                Label(formatDuration(skill.estimatedDuration), systemImage: "clock")
            }
            .font(.subheadline)

            if !skill.requiredPrivileges.isEmpty {
                HStack {
                    Label(skill.requiredPrivileges.joined(separator: ", "), systemImage: "lock.shield")
                        .foregroundColor(.orange)
                }
                .font(.caption)
            }

            if !skill.triggers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Triggers:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(skill.triggers.indices, id: \.self) { index in
                        let trigger = skill.triggers[index]
                        Text("• \(trigger.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var stepsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steps")
                .font(.headline)

            ForEach(Array(skill.steps.sorted(by: { $0.order < $1.order }))) { step in
                StepDetailCard(step: step)
            }
        }
    }

    private var actionsView: some View {
        VStack(spacing: 12) {
            if isRunning {
                HStack {
                    ProgressView()
                    Text("Running skill...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: runSkill) {
                    Label("Run Skill", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            HStack(spacing: 12) {
                Button(action: {}) {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !skill.isBuiltin {
                    Button(action: {}) {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .second]
        return formatter.string(from: duration) ?? "\(duration)s"
    }

    private func runSkill() {
        isRunning = true

        let execution = SkillExecution(skill: skill)
        self.execution = execution

        let executor = SkillExecutor()
        Task {
            await executor.execute(skill: skill, shell: context.shell) { result in
                DispatchQueue.main.async {
                    isRunning = false
                    showingExecution = true
                }
            }
        }
    }
}

// MARK: - Step Detail Card

struct StepDetailCard: View {
    let step: SkillStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(step.order)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.blue)
                    .clipShape(Circle())

                Text(step.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(step.stepType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }

            if let command = step.commandTemplate {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
            }

            if step.requiresConfirmation {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Requires confirmation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Skill Execution View

struct SkillExecutionView: View {
    @ObservedObject var execution: SkillExecution
    let context: TerminalManager.Context
    @Environment(\.dismiss) var dismiss
    @State private var selectedStepIndex: Int?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress bar
                ProgressView(value: execution.progress)
                    .padding()

                Divider()

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Status header
                        statusHeader

                        // Current step
                        if let currentStep = execution.currentStep {
                            currentStepView(currentStep)
                        }

                        Divider()

                        // Step results
                        stepResultsList
                    }
                    .padding()
                }
            }
            .navigationTitle("Running Skill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        execution.cancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(execution.isComplete ? "Done" : "Pause") {
                        if execution.isComplete {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: execution.status.icon)
                .foregroundColor(Color(execution.status.color))
                .font(.system(size: 32))

            VStack(alignment: .leading, spacing: 4) {
                Text(execution.skill.name)
                    .font(.headline)

                Text(execution.status.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Step \(execution.currentStepIndex + 1) of \(execution.skill.steps.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private func currentStepView(_ step: SkillStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Step")
                .font(.headline)

            StepExecutionCard(
                step: step,
                execution: execution,
                context: context
            )
        }
    }

    private var stepResultsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completed Steps")
                .font(.headline)

            if execution.stepResults.isEmpty {
                Text("No steps completed yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(execution.stepResults) { result in
                    StepResultCard(result: result)
                }
            }
        }
    }
}

// MARK: - Step Execution Card

struct StepExecutionCard: View {
    let step: SkillStep
    @ObservedObject var execution: SkillExecution
    let context: TerminalManager.Context
    @State private var isExecuting = false
    @State private var output: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(step.order)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.blue)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(step.stepType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            if step.requiresConfirmation && !isExecuting {
                Button(action: executeStep) {
                    Label("Execute Step", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if !output.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ScrollView {
                        Text(output)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
            }

            if isExecuting {
                HStack {
                    ProgressView()
                    Text("Executing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private func executeStep() {
        isExecuting = true

        Task {
            if let command = step.commandTemplate {
                do {
                    let result = try await context.executeCommandForSkill(command, timeout: Int(step.timeout))
                    output = result.output

                    DispatchQueue.main.async {
                        isExecuting = false

                        // Add result to execution
                        let stepResult = StepResult(
                            stepId: step.id,
                            stepTitle: step.title,
                            status: result.exitCode == 0 ? .success : .failed,
                            output: result.output,
                            exitCode: result.exitCode
                        )
                        execution.addStepResult(stepResult)
                        execution.advanceToNextStep()
                    }
                } catch {
                    output = "Error: \(error.localizedDescription)"
                    isExecuting = false
                }
            }
        }
    }
}

// MARK: - Step Result Card

struct StepResultCard: View {
    let result: StepResult
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: result.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.status == .success ? .green : .red)

                    Text(result.stepTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if !result.output.isEmpty {
                        Text("Output:")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Text(result.output)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if let analysis = result.analysis {
                        Divider()

                        Text("AI Analysis:")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Text(analysis.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
