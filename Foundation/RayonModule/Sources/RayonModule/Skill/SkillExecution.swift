//
//  SkillExecution.swift
//  RayonModule
//
//  Created by Claude on 2026/2/7.
//

import Foundation

// MARK: - SkillExecution

/// Runtime execution state of a skill
public class SkillExecution: ObservableObject, Identifiable {
    public let id: UUID = UUID()
    @Published public var skill: Skill
    @Published public var status: ExecutionStatus
    @Published public var currentStepIndex: Int
    @Published public var stepResults: [StepResult]
    @Published public var startedAt: Date
    @Published public var completedAt: Date?
    @Published public var error: ExecutionError?

    private var completionHandler: ((Result<Void, ExecutionError>) -> Void)?

    public init(
        skill: Skill,
        status: ExecutionStatus = .pending,
        currentStepIndex: Int = 0,
        stepResults: [StepResult] = [],
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        error: ExecutionError? = nil
    ) {
        self.skill = skill
        self.status = status
        self.currentStepIndex = currentStepIndex
        self.stepResults = stepResults
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.error = error
    }

    /// Get the current step
    public var currentStep: SkillStep? {
        guard currentStepIndex < skill.steps.count else { return nil }
        return skill.steps[currentStepIndex]
    }

    /// Check if execution is complete
    public var isComplete: Bool {
        status == .completed || status == .failed || status == .cancelled
    }

    /// Check if execution can proceed
    public var canProceed: Bool {
        status == .running || status == .pending
    }

    /// Get progress (0.0 to 1.0)
    public var progress: Double {
        guard skill.steps.count > 0 else { return 0 }
        return Double(currentStepIndex) / Double(skill.steps.count)
    }

    /// Start execution
    public func start(completion: ((Result<Void, ExecutionError>) -> Void)? = nil) {
        status = .running
        startedAt = Date()
        completionHandler = completion
    }

    /// Move to next step
    public func advanceToNextStep() {
        currentStepIndex += 1
        if currentStepIndex >= skill.steps.count {
            complete(successfully: true)
        }
    }

    /// Complete execution
    public func complete(successfully: Bool, error: ExecutionError? = nil) {
        status = successfully ? .completed : .failed
        completedAt = Date()
        self.error = error
        completionHandler?(successfully ? .success(()) : .failure(error ?? .unknown))
    }

    /// Cancel execution
    public func cancel() {
        status = .cancelled
        completedAt = Date()
        completionHandler?(.failure(.cancelled))
    }

    /// Add a step result
    public func addStepResult(_ result: StepResult) {
        stepResults.append(result)
    }

    /// Get summary for history
    public func summary() -> Summary {
        Summary(
            id: id,
            skillName: skill.name,
            category: skill.category,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            duration: completedAt?.timeIntervalSince(startedAt) ?? Date().timeIntervalSince(startedAt),
            stepsCompleted: stepResults.count,
            totalSteps: skill.steps.count
        )
    }
}

// MARK: - ExecutionStatus

public enum ExecutionStatus: String, Codable {
    case pending
    case running
    case paused
    case completed
    case failed
    case cancelled

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .running: return "Running"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    public var icon: String {
        switch self {
        case .pending: return "clock"
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    public var color: String {
        switch self {
        case .pending: return "gray"
        case .running: return "blue"
        case .paused: return "orange"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "gray"
        }
    }
}

// MARK: - ExecutionError

public enum ExecutionError: Error, LocalizedError, Codable {
    case timeout
    case commandFailed(exitCode: Int)
    case invalidStep
    case cancelled
    case unknown

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Command execution timed out"
        case .commandFailed(let code):
            return "Command failed with exit code \(code)"
        case .invalidStep:
            return "Invalid step configuration"
        case .cancelled:
            return "Execution was cancelled"
        case .unknown:
            return "Unknown error occurred"
        }
    }
}

// MARK: - StepResult

/// Result of executing a single step
public struct StepResult: Identifiable, Codable {
    public let id: UUID
    public var stepId: UUID
    public var stepTitle: String
    public var status: StepStatus
    public var output: String
    public var exitCode: Int?
    public var executionTime: TimeInterval
    public var executedAt: Date
    public var analysis: AIAnalysis?
    public var error: String?

    public init(
        id: UUID = UUID(),
        stepId: UUID,
        stepTitle: String,
        status: StepStatus,
        output: String = "",
        exitCode: Int? = nil,
        executionTime: TimeInterval = 0,
        executedAt: Date = Date(),
        analysis: AIAnalysis? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.stepId = stepId
        self.stepTitle = stepTitle
        self.status = status
        self.output = output
        self.exitCode = exitCode
        self.executionTime = executionTime
        self.executedAt = executedAt
        self.analysis = analysis
        self.error = error
    }

    /// Check if the step succeeded
    public var isSuccess: Bool {
        status == .success && (exitCode == nil || exitCode == 0)
    }
}

// MARK: - StepStatus

public enum StepStatus: String, Codable {
    case pending
    case running
    case success
    case failed
    case skipped

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .running: return "Running"
        case .success: return "Success"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }
}

// MARK: - AIAnalysis

/// AI analysis of command output
public struct AIAnalysis: Codable {
    public var summary: String
    public var issues: [Issue]
    public var recommendations: [Recommendation]
    public var confidence: Double
    public var suggestedNextSteps: [String]

    public init(
        summary: String,
        issues: [Issue] = [],
        recommendations: [Recommendation] = [],
        confidence: Double = 0.8,
        suggestedNextSteps: [String] = []
    ) {
        self.summary = summary
        self.issues = issues
        self.recommendations = recommendations
        self.confidence = confidence
        self.suggestedNextSteps = suggestedNextSteps
    }
}

// MARK: - Issue

public struct Issue: Identifiable, Codable {
    public let id: UUID
    public var severity: IssueSeverity
    public var title: String
    public var description: String
    public var location: String?

    public init(
        id: UUID = UUID(),
        severity: IssueSeverity,
        title: String,
        description: String,
        location: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.description = description
        self.location = location
    }
}

// MARK: - IssueSeverity

public enum IssueSeverity: String, Codable {
    case info
    case warning
    case error
    case critical

    public var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        case .critical: return "Critical"
        }
    }

    public var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    public var color: String {
        switch self {
        case .info: return "blue"
        case .warning: return "orange"
        case .error: return "red"
        case .critical: return "purple"
        }
    }
}

// MARK: - Recommendation

public struct Recommendation: Identifiable, Codable {
    public let id: UUID
    public var title: String
    public var description: String
    public var command: String?
    public var priority: Priority

    public init(
        id: UUID = UUID(),
        title: String,
        description: String,
        command: String? = nil,
        priority: Priority = .medium
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.command = command
        self.priority = priority
    }
}

// MARK: - Priority

public enum Priority: String, Codable {
    case low
    case medium
    case high
    case urgent

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
}

// MARK: - SkillExecution.Summary

extension SkillExecution {
    /// Summary for history logging
    public struct Summary: Identifiable, Codable {
        public let id: UUID
        public var skillName: String
        public var category: SkillCategory
        public var status: ExecutionStatus
        public var startedAt: Date
        public var completedAt: Date?
        public var duration: TimeInterval
        public var stepsCompleted: Int
        public var totalSteps: Int

        public var durationFormatted: String {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = [.minute, .second]
            return formatter.string(from: duration) ?? "\(duration)s"
        }

        public var successRate: Double {
            guard totalSteps > 0 else { return 0 }
            return Double(stepsCompleted) / Double(totalSteps)
        }
    }
}
