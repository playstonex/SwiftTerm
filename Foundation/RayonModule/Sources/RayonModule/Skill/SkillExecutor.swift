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

    private var executionQueue = DispatchQueue(label: "wiki.qaq.skill.executor", qos: .userInitiated)

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

        execution.start { result in
            DispatchQueue.main.async {
                self.isExecuting = false
                completion(result)
            }
        }

        // Start executing steps
        executeNextStep(in: execution, shell: shell)
    }

    /// Execute the next step in the skill
    private func executeNextStep(in execution: SkillExecution, shell: NSRemoteShell) {
        guard let step = execution.currentStep else {
            execution.complete(successfully: true)
            return
        }

        executionQueue.async { [weak self] in
            guard let self = self else { return }

            switch step.stepType {
            case .executeCommand:
                self.executeCommandStep(step, in: execution, shell: shell)
            case .analyzeOutput:
                self.executeAnalysisStep(step, in: execution)
            case .userChoice:
                self.executeUserChoiceStep(step, in: execution)
            case .manualConfirmation:
                self.executeManualConfirmationStep(step, in: execution)
            }
        }
    }

    /// Execute a command step
    private func executeCommandStep(
        _ step: SkillStep,
        in execution: SkillExecution,
        shell: NSRemoteShell
    ) {
        guard let command = step.commandTemplate else {
            execution.advanceToNextStep()
            return
        }

        let startTime = Date()
        var output = ""
        var exitCode: Int? = 0

        let semaphore = DispatchSemaphore(value: 0)

        shell.beginExecute(
            withCommand: " \(command)",
            withTimeout: NSNumber(value: step.timeout),
            withOnCreate: {},
            withOutput: { chunk in
                output.append(chunk)
            },
            withContinuationHandler: {
                exitCode = 0  // Success
                semaphore.signal()
                return true
            }
        )

        semaphore.wait()

        let executionTime = Date().timeIntervalSince(startTime)

        // Create step result
        let result = StepResult(
            stepId: step.id,
            stepTitle: step.title,
            status: exitCode == 0 ? .success : .failed,
            output: output,
            exitCode: exitCode,
            executionTime: executionTime
        )

        DispatchQueue.main.async {
            execution.addStepResult(result)
            execution.advanceToNextStep()
            self.executeNextStep(in: execution, shell: shell)
        }
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

        executeNextStep(in: execution, shell: shell)
    }

    /// Skip to next step
    public func skipToNextStep() {
        guard let execution = currentExecution else { return }
        guard let shell = shell else { return }

        execution.advanceToNextStep()
        executeNextStep(in: execution, shell: shell)
    }

    /// Execute a single command outside of skill context
    public func executeCommand(
        _ command: String,
        shell: NSRemoteShell,
        timeout: TimeInterval = 30
    ) async throws -> (output: String, exitCode: Int?) {
        return try await withCheckedThrowingContinuation { continuation in
            var output = ""

            shell.beginExecute(
                withCommand: " \(command)",
                withTimeout: NSNumber(value: timeout),
                withOnCreate: {},
                withOutput: { chunk in
                    output.append(chunk)
                },
                withContinuationHandler: {
                    continuation.resume(returning: (output, 0))
                    return true
                }
            )
        }
    }
}
