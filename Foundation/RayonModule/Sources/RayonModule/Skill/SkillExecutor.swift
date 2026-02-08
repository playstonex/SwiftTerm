//
//  SkillExecutor.swift
//  RayonModule
//
//  Created by Claude on 2026/2/7.
//

import Foundation
import NSRemoteShell

/// Executes skill steps and manages command execution
@MainActor
public class SkillExecutor: ObservableObject {
    @Published public var currentExecution: SkillExecution?
    @Published public var isExecuting: Bool = false

    private var shell: NSRemoteShell?

    public init() {}

    /// Execute a skill with a given shell context
    public func execute(
        skill: Skill,
        shell: NSRemoteShell,
        completion: @escaping (Result<Void, ExecutionError>) -> Void
    ) {
        guard !isExecuting else {
            completion(.failure(.unknown))
            return
        }

        let execution = SkillExecution(skill: skill)
        currentExecution = execution
        isExecuting = true
        self.shell = shell

        // Initialize execution with completion handler
        execution.start(completion: completion)

        // Start execution in task
        Task {
            do {
                // Check privileges before starting
                try await checkPrivileges(for: skill, shell: shell)

                // Start executing steps
                await executeNextStep(in: execution, shell: shell)
            } catch {
                execution.complete(successfully: false, error: error as? ExecutionError ?? .unknown)
            }
        }
    }
    
    /// Check if the current shell has the required privileges for the skill
    private func checkPrivileges(for skill: Skill, shell: NSRemoteShell) async throws {
        for privilege in skill.requiredPrivileges {
            if privilege == "sudo" {
                // Check if we can sudo without interaction or if we are already root
                // "sudo -n true" checks if we have a ticket or can run without password
                // However, NSRemoteShell might not support non-interactive sudo well if it prompts.
                // We'll just check if 'sudo' exists for now, as a basic check.
                // A better check would be trying to run a dummy sudo command.

                let result = try await CommandExecutor.execute("which sudo", shell: shell, timeout: 5)
                if result.exitCode != 0 {
                    // Try checking if we are root
                    let idResult = try await CommandExecutor.execute("id -u", shell: shell, timeout: 5)
                    if idResult.exitCode == 0 && idResult.output.trimmingCharacters(in: .whitespacesAndNewlines) == "0" {
                        continue // We are root, so sudo is implied (or not needed)
                    }
                    throw ExecutionError.missingPrivilege("sudo")
                }
            }
        }
    }

    /// Execute the next step in the skill
    private func executeNextStep(in execution: SkillExecution, shell: NSRemoteShell) async {
        guard let step = execution.currentStep else {
            execution.complete(successfully: true)
            return
        }

        switch step.stepType {
        case .executeCommand:
            await executeCommandStep(step, in: execution, shell: shell)
        case .analyzeOutput:
            executeAnalysisStep(step, in: execution)
        case .userChoice:
            executeUserChoiceStep(step, in: execution)
        case .manualConfirmation:
            executeManualConfirmationStep(step, in: execution)
        }
    }

    /// Execute a command step
    private func executeCommandStep(
        _ step: SkillStep,
        in execution: SkillExecution,
        shell: NSRemoteShell
    ) async {
        guard let command = step.commandTemplate else {
            execution.advanceToNextStep()
            await executeNextStep(in: execution, shell: shell)
            return
        }

        let startTime = Date()

        do {
            // Execute command using the shared utility
            let result = try await CommandExecutor.execute(
                command,
                shell: shell,
                timeout: step.timeout
            )

            let executionTime = Date().timeIntervalSince(startTime)

            // Determine success: success if exit code is 0 or nil (unknown)
            let status: StepStatus = (result.exitCode == nil || result.exitCode == 0) ? .success : .failed

            // Create step result
            let stepResult = StepResult(
                stepId: step.id,
                stepTitle: step.title,
                status: status,
                output: result.output,
                exitCode: result.exitCode,
                executionTime: executionTime
            )

            execution.addStepResult(stepResult)
        } catch {
            // Handle execution errors
            let executionTime = Date().timeIntervalSince(startTime)

            let stepResult = StepResult(
                stepId: step.id,
                stepTitle: step.title,
                status: .failed,
                output: "Command execution failed: \(error.localizedDescription)",
                exitCode: nil,
                executionTime: executionTime,
                error: error.localizedDescription
            )

            execution.addStepResult(stepResult)
        }

        execution.advanceToNextStep()
        await self.executeNextStep(in: execution, shell: shell)
    }

    /// Execute an analysis step
    private func executeAnalysisStep(_ step: SkillStep, in execution: SkillExecution) {
        // Analysis steps are handled by AI, mark as pending
        let result = StepResult(
            stepId: step.id,
            stepTitle: step.title,
            status: .pending,
            output: ""
        )

        execution.addStepResult(result)
    }

    /// Execute a user choice step
    private func executeUserChoiceStep(_ step: SkillStep, in execution: SkillExecution) {
        // User choice steps require user interaction
        let result = StepResult(
            stepId: step.id,
            stepTitle: step.title,
            status: .pending,
            output: "Waiting for user input"
        )

        execution.addStepResult(result)
    }

    /// Execute a manual confirmation step
    private func executeManualConfirmationStep(_ step: SkillStep, in execution: SkillExecution) {
        let result = StepResult(
            stepId: step.id,
            stepTitle: step.title,
            status: .pending,
            output: "Waiting for confirmation"
        )

        execution.addStepResult(result)
    }

    /// Cancel current execution
    public func cancelExecution() {
        guard let execution = currentExecution else { return }
        execution.cancel()
        isExecuting = false
    }

    /// Retry current step
    public func retryCurrentStep() {
        guard let execution = currentExecution else { return }
        guard let shell = shell else { return }

        // Remove the last result
        if !execution.stepResults.isEmpty {
            execution.stepResults.removeLast()
        }

        Task {
            await executeNextStep(in: execution, shell: shell)
        }
    }

    /// Skip to next step
    public func skipToNextStep() {
        guard let execution = currentExecution else { return }
        guard let shell = shell else { return }

        execution.advanceToNextStep()
        Task {
            await executeNextStep(in: execution, shell: shell)
        }
    }

    /// Execute a single command outside of skill context
    public func executeCommand(
        _ command: String,
        shell: NSRemoteShell,
        timeout: TimeInterval = 30
    ) async throws -> (output: String, exitCode: Int?) {
        return try await CommandExecutor.execute(command, shell: shell, timeout: timeout)
    }
}
