//
//  SkillAnalyzer.swift
//  RayonModule
//
//  Created by Claude on 2026/2/7.
//

import Foundation

/// AI-powered analysis for skill execution
@MainActor
public class SkillAnalyzer: ObservableObject {
    @Published public var isAnalyzing: Bool = false

    private let aiAssistant: AIAssistant

    public init(aiAssistant: AIAssistant) {
        self.aiAssistant = aiAssistant
    }

    public convenience init() {
        self.init(aiAssistant: .shared)
    }

    /// Analyze command output in skill context
    public func analyzeStepOutput(
        _ output: String,
        step: SkillStep,
        context: String
    ) async throws -> AIAnalysis {
        guard aiAssistant.isEnabled, !aiAssistant.apiKey.isEmpty else {
            // Return basic analysis if AI is disabled
            return AIAnalysis(
                summary: "Output received. Length: \(output.count) characters",
                issues: [],
                recommendations: [],
                confidence: 0.5
            )
        }

        var prompt = """
        Analyze this command output from a troubleshooting skill:

        Step: \(step.title)
        Command: \(step.commandTemplate ?? "N/A")
        Context: \(context)

        Output:
        \(output)

        Please provide:
        1. A brief summary of what the output shows
        2. Any issues or errors found (with severity)
        3. Actionable recommendations to fix any problems
        4. Suggested next steps

        Format as JSON:
        {
          "summary": "string",
          "issues": [{"severity": "info|warning|error|critical", "title": "string", "description": "string"}],
          "recommendations": [{"title": "string", "description": "string", "command": "string (optional)", "priority": "low|medium|high|urgent"}],
          "suggestedNextSteps": ["step1", "step2"]
        }
        """

        // Add custom analysis prompt if provided
        if let customPrompt = step.aiAnalysisPrompt {
            prompt = customPrompt + "\n\n" + prompt
        }

        let response = try await aiAssistant.sendRawChatRequest(prompt)

        // Parse JSON response
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fallback to text analysis
            return AIAnalysis(
                summary: response,
                issues: [],
                recommendations: [],
                confidence: 0.6
            )
        }

        // Parse issues
        var issues: [Issue] = []
        if let issuesArray = json["issues"] as? [[String: Any]] {
            for issueData in issuesArray {
                if let severityStr = issueData["severity"] as? String,
                   let severity = IssueSeverity(rawValue: severityStr),
                   let title = issueData["title"] as? String,
                   let description = issueData["description"] as? String {
                    issues.append(Issue(
                        severity: severity,
                        title: title,
                        description: description,
                        location: issueData["location"] as? String
                    ))
                }
            }
        }

        // Parse recommendations
        var recommendations: [Recommendation] = []
        if let recsArray = json["recommendations"] as? [[String: Any]] {
            for recData in recsArray {
                if let title = recData["title"] as? String,
                   let description = recData["description"] as? String {
                    recommendations.append(Recommendation(
                        title: title,
                        description: description,
                        command: recData["command"] as? String,
                        priority: Priority(rawValue: recData["priority"] as? String ?? "medium") ?? .medium
                    ))
                }
            }
        }

        // Parse suggested next steps
        let suggestedNextSteps = (json["suggestedNextSteps"] as? [String]) ?? []

        return AIAnalysis(
            summary: json["summary"] as? String ?? "",
            issues: issues,
            recommendations: recommendations,
            confidence: 0.8,
            suggestedNextSteps: suggestedNextSteps
        )
    }

    /// Suggest next steps based on current result
    public func suggestNextSteps(
        for currentStep: SkillStep,
        output: String,
        availableSteps: [SkillStep]
    ) async throws -> [NextStepSuggestion] {
        guard aiAssistant.isEnabled, !aiAssistant.apiKey.isEmpty else {
            return []
        }

        let stepsList = availableSteps.map { step in
            "\(step.order). \(step.title) - \(step.stepType.displayName)"
        }.joined(separator: "\n")

        let prompt = """
        Based on this command output, suggest what should happen next:

        Current step: \(currentStep.title)
        Output:
        \(output)

        Available steps:
        \(stepsList)

        Return a JSON array of suggestions:
        [
          {
            "title": "string",
            "description": "string",
            "targetStepId": "step order number (integer)",
            "confidence": 0.0-1.0,
            "actionType": "gotoStep|executeCommand|skipToEnd|retryStep"
          }
        ]
        """

        let response = try await aiAssistant.sendRawChatRequest(prompt)

        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var suggestions: [NextStepSuggestion] = []
        for sugData in json {
            guard let title = sugData["title"] as? String,
                  let description = sugData["description"] as? String else {
                continue
            }

            let confidence = sugData["confidence"] as? Double ?? 0.8
            let actionTypeStr = sugData["actionType"] as? String ?? "gotoStep"
            let actionType = SuggestionActionType(rawValue: actionTypeStr) ?? .gotoStep

            // Find target step by order
            var targetStepId: UUID?
            if let order = sugData["targetStepId"] as? Int,
               let step = availableSteps.first(where: { $0.order == order }) {
                targetStepId = step.id
            }

            suggestions.append(NextStepSuggestion(
                title: title,
                description: description,
                targetStepId: targetStepId,
                confidence: confidence,
                actionType: actionType
            ))
        }

        return suggestions.sorted { $0.confidence > $1.confidence }
    }

    /// Detect which skills might be relevant
    public func detectSkillsFromOutput(
        _ output: String,
        availableSkills: [Skill]
    ) async throws -> [SkillSuggestion] {
        guard aiAssistant.isEnabled, !aiAssistant.apiKey.isEmpty else {
            // Fall back to pattern matching
            return availableSkills.compactMap { skill in
                if skill.matchesTrigger(in: output) {
                    return SkillSuggestion(
                        skill: skill,
                        confidence: 0.7,
                        reason: "Pattern match: \(skill.triggers.first?.displayName ?? "")"
                    )
                }
                return nil
            }
        }

        let skillsList = availableSkills.map { skill in
            "\(skill.name) - \(skill.description)"
        }.joined(separator: "\n")

        let prompt = """
        Based on this terminal output, identify which troubleshooting skills might be relevant:

        Output:
        \(output)

        Available skills:
        \(skillsList)

        Return a JSON array of suggestions:
        [
          {
            "skillName": "exact name from list above",
            "confidence": 0.0-1.0,
            "reason": "why this skill is relevant",
            "detectedIssues": ["issue1", "issue2"]
          }
        ]

        Only include skills with confidence > 0.5
        """

        let response = try await aiAssistant.sendRawChatRequest(prompt)

        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var suggestions: [SkillSuggestion] = []
        for sugData in json {
            guard let skillName = sugData["skillName"] as? String,
                  let skill = availableSkills.first(where: { $0.name == skillName }) else {
                continue
            }

            let confidence = sugData["confidence"] as? Double ?? 0.5
            guard confidence > 0.5 else { continue }

            let reason = sugData["reason"] as? String ?? ""
            let detectedIssues = (sugData["detectedIssues"] as? [String]) ?? []

            suggestions.append(SkillSuggestion(
                skill: skill,
                confidence: confidence,
                reason: reason,
                detectedIssues: detectedIssues
            ))
        }

        return suggestions.sorted { $0.confidence > $1.confidence }
    }

    /// Generate skill from recorded execution
    public func generateSkillFromExecution(
        _ execution: SkillExecution,
        name: String,
        description: String
    ) async throws -> Skill {
        guard aiAssistant.isEnabled, !aiAssistant.apiKey.isEmpty else {
            throw AIError.disabled
        }

        let stepsSummary = execution.stepResults.map { result in
            """
            Step: \(result.stepTitle)
            Status: \(result.status.displayName)
            Output: \(result.output.prefix(500))
            """
        }.joined(separator: "\n---\n")

        let prompt = """
        Based on this skill execution, create a reusable skill template:

        Name: \(name)
        Description: \(description)

        Execution Summary:
        \(stepsSummary)

        Create a skill template that:
        1. Identifies the key steps needed
        2. Provides command templates with variables
        3. Includes triggers for auto-detection
        4. Suggests confirmation points

        Return as JSON matching this structure:
        {
          "triggers": [{"type": "errorPattern", "pattern": "regex"}],
          "steps": [
            {
              "order": 1,
              "title": "step title",
              "stepType": "executeCommand",
              "commandTemplate": "command with {{variables}}",
              "requiresConfirmation": true,
              "expectedOutputPattern": "optional regex"
            }
          ]
        }
        """

        let response = try await aiAssistant.sendRawChatRequest(prompt)

        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse
        }

        // Parse triggers
        var triggers: [SkillTrigger] = []
        if let triggersArray = json["triggers"] as? [[String: Any]] {
            for trigData in triggersArray {
                if let type = trigData["type"] as? String,
                   type == "errorPattern",
                   let pattern = trigData["pattern"] as? String {
                    triggers.append(.errorPattern(pattern: pattern))
                }
            }
        }

        // Parse steps
        var steps: [SkillStep] = []
        if let stepsArray = json["steps"] as? [[String: Any]] {
            for stepData in stepsArray {
                let order = stepData["order"] as? Int ?? 0
                let title = stepData["title"] as? String ?? ""
                let stepTypeStr = stepData["stepType"] as? String ?? "executeCommand"
                let stepType = StepType(rawValue: stepTypeStr) ?? .executeCommand
                let commandTemplate = stepData["commandTemplate"] as? String
                let requiresConfirmation = stepData["requiresConfirmation"] as? Bool ?? true
                let expectedOutputPattern = stepData["expectedOutputPattern"] as? String

                steps.append(SkillStep(
                    order: order,
                    title: title,
                    stepType: stepType,
                    commandTemplate: commandTemplate,
                    requiresConfirmation: requiresConfirmation,
                    expectedOutputPattern: expectedOutputPattern
                ))
            }
        }

        return Skill(
            name: name,
            category: .custom,
            description: description,
            triggers: triggers,
            steps: steps,
            isBuiltin: false,
            estimatedDuration: execution.completedAt?.timeIntervalSince(execution.startedAt) ?? 60
        )
    }
}
