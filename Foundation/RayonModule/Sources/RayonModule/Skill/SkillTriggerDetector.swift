//
//  SkillTriggerDetector.swift
//  RayonModule
//
//  Created by Claude on 2026/2/7.
//

import Foundation

/// Detects when skills should be triggered based on output and system state
public class SkillTriggerDetector {
    private let registry: SkillRegistry

    public init(registry: SkillRegistry) {
        self.registry = registry
    }

    @MainActor
    public convenience init() {
        self.init(registry: .shared)
    }

    /// Analyze terminal output and detect matching skills
    @MainActor
    public func detectSkills(in output: String) -> [SkillSuggestion] {
        let enabledSkills = registry.allEnabledSkills
        var suggestions: [SkillSuggestion] = []

        // Check each skill's triggers
        for skill in enabledSkills {
            if skill.matchesTrigger(in: output) {
                // Extract the matched patterns
                let matchedPatterns = skill.triggers.compactMap { trigger -> String? in
                    switch trigger {
                    case .errorPattern(let pattern):
                        if output.range(of: pattern, options: .regularExpression) != nil {
                            return "Error pattern: \(pattern)"
                        }
                    case .commandPattern(let pattern):
                        if output.range(of: pattern, options: .regularExpression) != nil {
                            return "Command pattern: \(pattern)"
                        }
                    default:
                        return nil
                    }
                    return nil
                }

                suggestions.append(SkillSuggestion(
                    skill: skill,
                    confidence: 0.85,
                    reason: "Detected in terminal output",
                    detectedIssues: matchedPatterns
                ))
            }
        }

        // Check for common error patterns that might not have skills
        let genericIssues = detectGenericIssues(in: output)
        for issue in genericIssues {
            // Create placeholder suggestions for issues without skills
            suggestions.append(SkillSuggestion(
                skill: Skill(
                    name: "Generic Troubleshooting",
                    category: .system,
                    description: issue.description,
                    triggers: [.errorPattern(pattern: issue.pattern)],
                    steps: [],
                    isBuiltin: true,
                    estimatedDuration: 30
                ),
                confidence: issue.severity == .high ? 0.9 : 0.6,
                reason: issue.description,
                detectedIssues: [issue.pattern]
            ))
        }

        return suggestions.sorted { $0.confidence > $1.confidence }
    }

    /// Detect common error patterns
    private func detectGenericIssues(in output: String) -> [(pattern: String, description: String, severity: DetectionSeverity)] {
        var issues: [(pattern: String, description: String, severity: DetectionSeverity)] = []

        let lowercaseOutput = output.lowercased()

        // Nginx errors
        if lowercaseOutput.contains("nginx") && lowercaseOutput.contains("error") {
            issues.append((
                pattern: "nginx.*error",
                description: "Nginx error detected",
                severity: .high
            ))
        }

        // Docker errors
        if lowercaseOutput.contains("docker") && lowercaseOutput.contains("error") {
            issues.append((
                pattern: "docker.*error",
                description: "Docker error detected",
                severity: .high
            ))
        }

        // Disk space errors
        if lowercaseOutput.contains("no space left") || lowercaseOutput.contains("disk full") {
            issues.append((
                pattern: "no space left",
                description: "Disk space issue detected",
                severity: .critical
            ))
        }

        // Memory errors
        if lowercaseOutput.contains("cannot allocate memory") ||
           lowercaseOutput.contains("out of memory") ||
           lowercaseOutput.contains("oom killer") {
            issues.append((
                pattern: "memory.*error",
                description: "Memory issue detected",
                severity: .critical
            ))
        }

        // Connection errors
        if lowercaseOutput.contains("connection refused") || lowercaseOutput.contains("connection timed out") {
            issues.append((
                pattern: "connection.*error",
                description: "Connection issue detected",
                severity: .high
            ))
        }

        // Permission errors
        if lowercaseOutput.contains("permission denied") {
            issues.append((
                pattern: "permission denied",
                description: "Permission issue detected",
                severity: .medium
            ))
        }

        // 502/504 errors
        if lowercaseOutput.contains("502") || lowercaseOutput.contains("504") {
            issues.append((
                pattern: "50[24].*gateway",
                description: "Gateway timeout/error detected",
                severity: .high
            ))
        }

        // Container errors
        if lowercaseOutput.contains("container") && lowercaseOutput.contains("exited") {
            issues.append((
                pattern: "container.*exited",
                description: "Container exited unexpectedly",
                severity: .high
            ))
        }

        // Service not running
        if lowercaseOutput.contains("service") && lowercaseOutput.contains("not running") {
            issues.append((
                pattern: "service.*not running",
                description: "Service not running",
                severity: .high
            ))
        }

        return issues
    }

    /// Check system state conditions
    @MainActor
    public func checkSystemState() -> [SkillSuggestion] {
        var suggestions: [SkillSuggestion] = []

        let enabledSkills = registry.allEnabledSkills

        // Check each skill for system state triggers
        for skill in enabledSkills {
            for trigger in skill.triggers {
                if case .systemState(let check) = trigger {
                    if evaluateSystemState(check: check) {
                        suggestions.append(SkillSuggestion(
                            skill: skill,
                            confidence: 0.9,
                            reason: "System state check: \(check.description)",
                            detectedIssues: [check.description]
                        ))
                    }
                }
            }
        }

        return suggestions
    }

    /// Evaluate a system state check
    private func evaluateSystemState(check: SystemStateCheck) -> Bool {
        // Note: These checks would require actual system monitoring
        // For now, return false - actual implementation would query system stats
        return false
    }
}

// MARK: - DetectionSeverity

enum DetectionSeverity {
    case low
    case medium
    case high
    case critical
}

// MARK: - Common Error Patterns Extension

extension SkillTriggerDetector {
    /// Common error patterns organized by category
    public struct ErrorPatterns {
        public static let webServer: [String] = [
            "nginx.*error",
            "apache.*error",
            "httpd.*error",
            "502 Bad Gateway",
            "504 Gateway Timeout",
            "500 Internal Server Error"
        ]

        public static let containers: [String] = [
            "docker.*error",
            "Container exited",
            "no such container",
            "crashloopbackoff",
            "pod.*not ready",
            "imagepullbackoff"
        ]

        public static let disk: [String] = [
            "no space left",
            "disk full",
            "cannot write",
            "read-only file system"
        ]

        public static let memory: [String] = [
            "cannot allocate memory",
            "out of memory",
            "oom killer",
            "memory exhausted"
        ]

        public static let network: [String] = [
            "connection refused",
            "connection timed out",
            "network unreachable",
            "name resolution failed"
        ]

        public static let permissions: [String] = [
            "permission denied",
            "access denied",
            "unauthorized"
        ]
    }
}
