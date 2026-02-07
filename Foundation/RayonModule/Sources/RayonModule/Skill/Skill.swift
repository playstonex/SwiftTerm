//
//  Skill.swift
//  RayonModule
//
//  Created by Claude on 2026/2/7.
//

import Foundation

// MARK: - Skill

/// A reusable troubleshooting or operational skill
public struct Skill: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var category: SkillCategory
    public var description: String
    public var triggers: [SkillTrigger]
    public var steps: [SkillStep]
    public var isBuiltin: Bool
    public var estimatedDuration: TimeInterval
    public var requiredPrivileges: [String]
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        category: SkillCategory,
        description: String,
        triggers: [SkillTrigger] = [],
        steps: [SkillStep],
        isBuiltin: Bool = false,
        estimatedDuration: TimeInterval = 60,
        requiredPrivileges: [String] = [],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.triggers = triggers
        self.steps = steps
        self.isBuiltin = isBuiltin
        self.estimatedDuration = estimatedDuration
        self.requiredPrivileges = requiredPrivileges
        self.enabled = enabled
    }

    /// Check if this skill can be triggered by the given output
    public func matchesTrigger(in output: String) -> Bool {
        return triggers.contains { $0.matches(in: output) }
    }

    /// Get the first step
    public var firstStep: SkillStep? {
        steps.sorted { $0.order < $1.order }.first
    }

    /// Get step by ID
    public func step(id: UUID) -> SkillStep? {
        steps.first { $0.id == id }
    }
}

// MARK: - SkillCategory

public enum SkillCategory: String, CaseIterable, Codable {
    case webServer = "Web Server"
    case container = "Containers"
    case system = "System Operations"
    case network = "Network"
    case database = "Database"
    case security = "Security"
    case monitoring = "Monitoring"
    case custom = "Custom"

    public var icon: String {
        switch self {
        case .webServer: return "server.rack"
        case .container: return "cube.box"
        case .system: return "gearshape.2"
        case .network: return "network"
        case .database: return "cylinder"
        case .security: return "shield"
        case .monitoring: return "chart.line.uptrend.xyaxis"
        case .custom: return "star"
        }
    }

    public var color: String {
        switch self {
        case .webServer: return "blue"
        case .container: return "orange"
        case .system: return "gray"
        case .network: return "purple"
        case .database: return "green"
        case .security: return "red"
        case .monitoring: return "cyan"
        case .custom: return "yellow"
        }
    }
}

// MARK: - SkillTrigger

/// Defines how a skill can be triggered
public enum SkillTrigger: Codable, Hashable {
    case errorPattern(pattern: String)
    case commandPattern(pattern: String)
    case systemState(check: SystemStateCheck)
    case manual

    public var displayName: String {
        switch self {
        case .errorPattern(let pattern):
            return "Error: \(pattern)"
        case .commandPattern(let pattern):
            return "Command: \(pattern)"
        case .systemState(let check):
            return "State: \(check.description)"
        case .manual:
            return "Manual"
        }
    }

    public func matches(in output: String) -> Bool {
        switch self {
        case .errorPattern(let pattern):
            return output.range(of: pattern, options: .regularExpression) != nil
        case .commandPattern(let pattern):
            return output.range(of: pattern, options: .regularExpression) != nil
        case .systemState:
            return false // System state checks require external evaluation
        case .manual:
            return false
        }
    }
}

// MARK: - SystemStateCheck

public enum SystemStateCheck: Codable, Hashable {
    case diskUsageAbove(percent: Int)
    case cpuUsageAbove(percent: Int)
    case memoryUsageAbove(percent: Int)
    case serviceDown(serviceName: String)
    case portNotListening(port: Int)

    public var description: String {
        switch self {
        case .diskUsageAbove(let percent):
            return "Disk usage > \(percent)%"
        case .cpuUsageAbove(let percent):
            return "CPU usage > \(percent)%"
        case .memoryUsageAbove(let percent):
            return "Memory usage > \(percent)%"
        case .serviceDown(let name):
            return "Service \(name) is down"
        case .portNotListening(let port):
            return "Port \(port) not listening"
        }
    }
}

// MARK: - SkillStep

/// An individual step within a skill
public struct SkillStep: Identifiable, Codable, Hashable {
    public let id: UUID
    public var order: Int
    public var title: String
    public var stepType: StepType
    public var commandTemplate: String?
    public var aiAnalysisPrompt: String?
    public var requiresConfirmation: Bool
    public var nextStepSuggestions: [NextStepSuggestion]
    public var expectedOutputPattern: String?
    public var timeout: TimeInterval

    public init(
        id: UUID = UUID(),
        order: Int,
        title: String,
        stepType: StepType,
        commandTemplate: String? = nil,
        aiAnalysisPrompt: String? = nil,
        requiresConfirmation: Bool = true,
        nextStepSuggestions: [NextStepSuggestion] = [],
        expectedOutputPattern: String? = nil,
        timeout: TimeInterval = 30
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.stepType = stepType
        self.commandTemplate = commandTemplate
        self.aiAnalysisPrompt = aiAnalysisPrompt
        self.requiresConfirmation = requiresConfirmation
        self.nextStepSuggestions = nextStepSuggestions
        self.expectedOutputPattern = expectedOutputPattern
        self.timeout = timeout
    }

    /// Check if this step requires a command to be executed
    public var requiresCommand: Bool {
        if case .executeCommand = stepType {
            return true
        }
        return false
    }
}

// MARK: - StepType

public enum StepType: String, Codable {
    case executeCommand
    case analyzeOutput
    case userChoice
    case manualConfirmation

    public var displayName: String {
        switch self {
        case .executeCommand: return "Execute Command"
        case .analyzeOutput: return "Analyze Output"
        case .userChoice: return "User Choice"
        case .manualConfirmation: return "Manual Confirmation"
        }
    }
}

// MARK: - NextStepSuggestion

/// A suggested next step based on analysis
public struct NextStepSuggestion: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var description: String
    public var targetStepId: UUID?
    public var confidence: Double
    public var actionType: SuggestionActionType

    public init(
        id: UUID = UUID(),
        title: String,
        description: String,
        targetStepId: UUID? = nil,
        confidence: Double = 0.8,
        actionType: SuggestionActionType = .gotoStep
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.targetStepId = targetStepId
        self.confidence = confidence
        self.actionType = actionType
    }
}

// MARK: - SuggestionActionType

public enum SuggestionActionType: String, Codable {
    case gotoStep
    case executeCommand
    case skipToEnd
    case retryStep

    public var displayName: String {
        switch self {
        case .gotoStep: return "Go to Step"
        case .executeCommand: return "Execute Command"
        case .skipToEnd: return "Complete"
        case .retryStep: return "Retry"
        }
    }
}

// MARK: - SkillGroup

/// A collection of skills
public struct SkillGroup: Codable {
    public var builtinSkills: [Skill]
    public var customSkills: [Skill]
    public var skillExecutionHistory: [SkillExecution.Summary]

    public init(
        builtinSkills: [Skill] = [],
        customSkills: [Skill] = [],
        skillExecutionHistory: [SkillExecution.Summary] = []
    ) {
        self.builtinSkills = builtinSkills
        self.customSkills = customSkills
        self.skillExecutionHistory = skillExecutionHistory
    }

    /// Get all enabled skills
    public var allEnabledSkills: [Skill] {
        (builtinSkills + customSkills).filter { $0.enabled }
    }

    /// Get skills by category
    public func skills(in category: SkillCategory) -> [Skill] {
        allEnabledSkills.filter { $0.category == category }
    }

    /// Find skill by ID
    public func skill(id: UUID) -> Skill? {
        (builtinSkills + customSkills).first { $0.id == id }
    }
}

// MARK: - SkillSuggestion

/// A suggested skill based on analysis
public struct SkillSuggestion: Identifiable, Codable {
    public let id: UUID
    public var skill: Skill
    public var confidence: Double
    public var reason: String
    public var detectedIssues: [String]

    public init(
        id: UUID = UUID(),
        skill: Skill,
        confidence: Double,
        reason: String,
        detectedIssues: [String] = []
    ) {
        self.id = id
        self.skill = skill
        self.confidence = confidence
        self.reason = reason
        self.detectedIssues = detectedIssues
    }
}
