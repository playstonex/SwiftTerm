//
//  SkillRegistry.swift
//  RayonModule
//
//  Created by Claude on 2026/2/7.
//

import Foundation

/// Registry for managing available skills
public class SkillRegistry: ObservableObject {
    public static let shared = SkillRegistry()

    @Published public var skillGroup: SkillGroup = SkillGroup()
    @Published public var activeExecutions: [SkillExecution] = []

    private let userDefaults = UserDefaults.standard
    private let skillsKey = "wiki.qaq.rayon.skills"

    private init() {
        loadSkills()
    }

    // MARK: - Skill Management

    /// Register a new skill
    public func registerSkill(_ skill: Skill) {
        if skill.isBuiltin {
            skillGroup.builtinSkills.append(skill)
        } else {
            skillGroup.customSkills.append(skill)
        }
        saveSkills()
    }

    /// Update an existing skill
    public func updateSkill(_ skill: Skill) {
        if skill.isBuiltin {
            if let index = skillGroup.builtinSkills.firstIndex(where: { $0.id == skill.id }) {
                skillGroup.builtinSkills[index] = skill
            }
        } else {
            if let index = skillGroup.customSkills.firstIndex(where: { $0.id == skill.id }) {
                skillGroup.customSkills[index] = skill
            }
        }
        saveSkills()
    }

    /// Delete a custom skill
    public func deleteSkill(_ skill: Skill) {
        guard !skill.isBuiltin else { return }
        skillGroup.customSkills.removeAll { $0.id == skill.id }
        saveSkills()
    }

    /// Enable or disable a skill
    public func setSkill(_ skill: Skill, enabled: Bool) {
        var updatedSkill = skill
        updatedSkill.enabled = enabled
        updateSkill(updatedSkill)
    }

    // MARK: - Query

    /// Get all enabled skills
    public var allEnabledSkills: [Skill] {
        skillGroup.allEnabledSkills
    }

    /// Get skills by category
    public func skills(in category: SkillCategory) -> [Skill] {
        skillGroup.skills(in: category)
    }

    /// Find skill by ID
    public func skill(id: UUID) -> Skill? {
        skillGroup.skill(id: id)
    }

    /// Search skills by name or description
    public func searchSkills(_ query: String) -> [Skill] {
        let lowercaseQuery = query.lowercased()
        return allEnabledSkills.filter { skill in
            skill.name.lowercased().contains(lowercaseQuery) ||
            skill.description.lowercased().contains(lowercaseQuery)
        }
    }

    // MARK: - Auto-Detection

    /// Detect skills that match the given output
    public func detectSkills(in output: String) -> [SkillSuggestion] {
        let matchingSkills = allEnabledSkills.filter { skill in
            skill.matchesTrigger(in: output)
        }

        return matchingSkills.map { skill in
            SkillSuggestion(
                skill: skill,
                confidence: 0.8,
                reason: "Pattern matched in output",
                detectedIssues: []
            )
        }
    }

    // MARK: - Execution Tracking

    /// Start tracking an execution
    public func startExecution(_ execution: SkillExecution) {
        activeExecutions.append(execution)
    }

    /// Complete an execution
    public func completeExecution(_ execution: SkillExecution) {
        if let index = activeExecutions.firstIndex(where: { $0.id == execution.id }) {
            activeExecutions.remove(at: index)
        }

        // Add to history
        skillGroup.skillExecutionHistory.append(execution.summary())

        // Keep only last 50 executions
        if skillGroup.skillExecutionHistory.count > 50 {
            skillGroup.skillExecutionHistory.removeFirst()
        }

        saveSkills()
    }

    /// Get execution history
    public var executionHistory: [SkillExecution.Summary] {
        skillGroup.skillExecutionHistory
    }

    /// Get recent executions
    public func recentExecutions(limit: Int = 10) -> [SkillExecution.Summary] {
        Array(skillGroup.skillExecutionHistory.suffix(limit).reversed())
    }

    // MARK: - Persistence

    private func saveSkills() {
        if let encoded = try? JSONEncoder().encode(skillGroup) {
            userDefaults.set(encoded, forKey: skillsKey)
        }
    }

    private func loadSkills() {
        guard let data = userDefaults.data(forKey: skillsKey),
              let decoded = try? JSONDecoder().decode(SkillGroup.self, from: data) else {
            // First load - initialize with built-in skills
            initializeBuiltinSkills()
            return
        }

        skillGroup = decoded

        // Ensure built-in skills exist
        if skillGroup.builtinSkills.isEmpty {
            initializeBuiltinSkills()
        }
    }

    private func initializeBuiltinSkills() {
        skillGroup.builtinSkills = SkillTemplates.builtinSkills
        saveSkills()
    }

    /// Clear all data
    public func clearAllData() {
        skillGroup = SkillGroup()
        activeExecutions.removeAll()
        userDefaults.removeObject(forKey: skillsKey)
        initializeBuiltinSkills()
    }

    /// Export skills as JSON
    public func exportSkills() throws -> Data {
        let exportData: [String: Any] = [
            "version": 1,
            "customSkills": skillGroup.customSkills,
            "exportedAt": ISO8601DateFormatter().string(from: Date())
        ]

        return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    /// Import skills from JSON
    public func importSkills(from data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let skillsArray = json["customSkills"] as? [[String: Any]] else {
            throw SkillImportError.invalidFormat
        }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for skillDict in skillsArray {
            let skillData = try JSONSerialization.data(withJSONObject: skillDict)
            let skill = try decoder.decode(Skill.self, from: skillData)

            // Check if skill already exists
            if skillGroup.customSkills.contains(where: { $0.id == skill.id }) {
                // Generate new ID for imported skill
                var updatedSkill = skill
                updatedSkill.enabled = true
                skillGroup.customSkills.append(updatedSkill)
            } else {
                skillGroup.customSkills.append(skill)
            }
        }

        saveSkills()
    }
}

// MARK: - SkillImportError

public enum SkillImportError: Error, LocalizedError {
    case invalidFormat
    case versionMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid skill file format"
        case .versionMismatch:
            return "Skill file version is not compatible"
        }
    }
}

// MARK: - Skill Templates Registry

public enum SkillTemplates {
    /// Get all built-in skills
    public static var builtinSkills: [Skill] {
        [
            nginxTroubleshooting(),
            apacheTroubleshooting(),
            dockerDebug(),
            kubernetesPodDebug(),
            diskSpaceAnalysis(),
            highCpuAnalysis(),
            highMemoryAnalysis()
        ]
    }

    // MARK: - Nginx Troubleshooting

    public static func nginxTroubleshooting() -> Skill {
        Skill(
            name: "Nginx Troubleshooting",
            category: .webServer,
            description: "Diagnose and fix common Nginx issues",
            triggers: [
                .errorPattern(pattern: "nginx.*error"),
                .errorPattern(pattern: "502 Bad Gateway"),
                .errorPattern(pattern: "504 Gateway Timeout")
            ],
            steps: [
                SkillStep(
                    order: 1,
                    title: "Check Nginx Error Logs",
                    stepType: .executeCommand,
                    commandTemplate: "sudo tail -n 100 /var/log/nginx/error.log",
                    requiresConfirmation: false,
                    expectedOutputPattern: nil,
                    timeout: 10
                ),
                SkillStep(
                    order: 2,
                    title: "Test Nginx Configuration",
                    stepType: .executeCommand,
                    commandTemplate: "sudo nginx -t",
                    requiresConfirmation: true,
                    expectedOutputPattern: "syntax is ok",
                    timeout: 5
                ),
                SkillStep(
                    order: 3,
                    title: "Check Nginx Status",
                    stepType: .executeCommand,
                    commandTemplate: "sudo systemctl status nginx",
                    requiresConfirmation: false,
                    timeout: 5
                ),
                SkillStep(
                    order: 4,
                    title: "Restart Nginx if Needed",
                    stepType: .manualConfirmation,
                    commandTemplate: "sudo systemctl restart nginx",
                    requiresConfirmation: true,
                    timeout: 15
                )
            ],
            isBuiltin: true,
            estimatedDuration: 60,
            requiredPrivileges: ["sudo"]
        )
    }

    // MARK: - Apache Troubleshooting

    public static func apacheTroubleshooting() -> Skill {
        Skill(
            name: "Apache Troubleshooting",
            category: .webServer,
            description: "Diagnose and fix common Apache issues",
            triggers: [
                .errorPattern(pattern: "apache.*error"),
                .errorPattern(pattern: "500 Internal Server Error"),
                .errorPattern(pattern: "httpd.*error")
            ],
            steps: [
                SkillStep(
                    order: 1,
                    title: "Check Apache Error Logs",
                    stepType: .executeCommand,
                    commandTemplate: "sudo tail -n 100 /var/log/apache2/error.log",
                    requiresConfirmation: false,
                    timeout: 10
                ),
                SkillStep(
                    order: 2,
                    title: "Test Apache Configuration",
                    stepType: .executeCommand,
                    commandTemplate: "sudo apache2ctl configtest",
                    requiresConfirmation: true,
                    timeout: 5
                ),
                SkillStep(
                    order: 3,
                    title: "Check Apache Status",
                    stepType: .executeCommand,
                    commandTemplate: "sudo systemctl status apache2",
                    requiresConfirmation: false,
                    timeout: 5
                ),
                SkillStep(
                    order: 4,
                    title: "Restart Apache if Needed",
                    stepType: .manualConfirmation,
                    commandTemplate: "sudo systemctl restart apache2",
                    requiresConfirmation: true,
                    timeout: 15
                )
            ],
            isBuiltin: true,
            estimatedDuration: 60,
            requiredPrivileges: ["sudo"]
        )
    }

    // MARK: - Docker Debug

    public static func dockerDebug() -> Skill {
        Skill(
            name: "Docker Container Debug",
            category: .container,
            description: "Debug Docker container issues",
            triggers: [
                .errorPattern(pattern: "docker.*error"),
                .errorPattern(pattern: "Container exited"),
                .errorPattern(pattern: "no such container")
            ],
            steps: [
                SkillStep(
                    order: 1,
                    title: "List All Containers",
                    stepType: .executeCommand,
                    commandTemplate: "docker ps -a",
                    requiresConfirmation: false,
                    timeout: 5
                ),
                SkillStep(
                    order: 2,
                    title: "View Container Logs",
                    stepType: .userChoice,
                    requiresConfirmation: false
                ),
                SkillStep(
                    order: 3,
                    title: "Inspect Container",
                    stepType: .userChoice,
                    requiresConfirmation: false
                ),
                SkillStep(
                    order: 4,
                    title: "Restart Container",
                    stepType: .manualConfirmation,
                    commandTemplate: "docker restart {{container_id}}",
                    requiresConfirmation: true,
                    timeout: 30
                )
            ],
            isBuiltin: true,
            estimatedDuration: 90,
            requiredPrivileges: []
        )
    }

    // MARK: - Kubernetes Pod Debug

    public static func kubernetesPodDebug() -> Skill {
        Skill(
            name: "Kubernetes Pod Debug",
            category: .container,
            description: "Debug Kubernetes pod issues",
            triggers: [
                .errorPattern(pattern: "kubectl.*error"),
                .errorPattern(pattern: "pod.*not ready"),
                .errorPattern(pattern: "crashloopbackoff")
            ],
            steps: [
                SkillStep(
                    order: 1,
                    title: "Get All Pods",
                    stepType: .executeCommand,
                    commandTemplate: "kubectl get pods -A",
                    requiresConfirmation: false,
                    timeout: 10
                ),
                SkillStep(
                    order: 2,
                    title: "Describe Pod",
                    stepType: .userChoice,
                    requiresConfirmation: false
                ),
                SkillStep(
                    order: 3,
                    title: "View Pod Logs",
                    stepType: .userChoice,
                    requiresConfirmation: false
                ),
                SkillStep(
                    order: 4,
                    title: "Check Events",
                    stepType: .executeCommand,
                    commandTemplate: "kubectl get events --sort-by=.metadata.creationTimestamp",
                    requiresConfirmation: false,
                    timeout: 10
                )
            ],
            isBuiltin: true,
            estimatedDuration: 120,
            requiredPrivileges: []
        )
    }

    // MARK: - Disk Space Analysis

    public static func diskSpaceAnalysis() -> Skill {
        Skill(
            name: "Disk Space Analysis",
            category: .system,
            description: "Analyze and clean up disk space",
            triggers: [
                .errorPattern(pattern: "no space left"),
                .errorPattern(pattern: "disk full"),
                .systemState(check: .diskUsageAbove(percent: 90))
            ],
            steps: [
                SkillStep(
                    order: 1,
                    title: "Check Disk Usage",
                    stepType: .executeCommand,
                    commandTemplate: "df -h",
                    requiresConfirmation: false,
                    timeout: 5
                ),
                SkillStep(
                    order: 2,
                    title: "Find Large Files",
                    stepType: .executeCommand,
                    commandTemplate: "sudo du -sh /* 2>/dev/null | sort -hr | head -20",
                    requiresConfirmation: false,
                    timeout: 30
                ),
                SkillStep(
                    order: 3,
                    title: "Clean Temporary Files",
                    stepType: .manualConfirmation,
                    commandTemplate: "sudo rm -rf /tmp/*",
                    requiresConfirmation: true,
                    timeout: 30
                ),
                SkillStep(
                    order: 4,
                    title: "Clean Package Cache",
                    stepType: .manualConfirmation,
                    commandTemplate: "sudo apt clean || sudo yum clean all || true",
                    requiresConfirmation: true,
                    timeout: 15
                )
            ],
            isBuiltin: true,
            estimatedDuration: 90,
            requiredPrivileges: ["sudo"]
        )
    }

    // MARK: - High CPU Analysis

    public static func highCpuAnalysis() -> Skill {
        Skill(
            name: "High CPU Analysis",
            category: .monitoring,
            description: "Identify and manage high CPU usage",
            triggers: [
                .systemState(check: .cpuUsageAbove(percent: 90))
            ],
            steps: [
                SkillStep(
                    order: 1,
                    title: "Show Top Processes",
                    stepType: .executeCommand,
                    commandTemplate: "top -b -n 1 | head -20",
                    requiresConfirmation: false,
                    timeout: 5
                ),
                SkillStep(
                    order: 2,
                    title: "Show Process Tree",
                    stepType: .executeCommand,
                    commandTemplate: "ps auxf",
                    requiresConfirmation: false,
                    timeout: 5
                ),
                SkillStep(
                    order: 3,
                    title: "Kill Process if Needed",
                    stepType: .manualConfirmation,
                    commandTemplate: "sudo kill -9 {{pid}}",
                    requiresConfirmation: true,
                    timeout: 5
                )
            ],
            isBuiltin: true,
            estimatedDuration: 30,
            requiredPrivileges: ["sudo"]
        )
    }

    // MARK: - High Memory Analysis

    public static func highMemoryAnalysis() -> Skill {
        Skill(
            name: "High Memory Analysis",
            category: .monitoring,
            description: "Identify and manage high memory usage",
            triggers: [
                .systemState(check: .memoryUsageAbove(percent: 90))
            ],
            steps: [
                SkillStep(
                    order: 1,
                    title: "Check Memory Usage",
                    stepType: .executeCommand,
                    commandTemplate: "free -h",
                    requiresConfirmation: false,
                    timeout: 5
                ),
                SkillStep(
                    order: 2,
                    title: "Show Memory by Process",
                    stepType: .executeCommand,
                    commandTemplate: "ps aux --sort=-%mem | head -20",
                    requiresConfirmation: false,
                    timeout: 5
                ),
                SkillStep(
                    order: 3,
                    title: "Clear Page Cache",
                    stepType: .manualConfirmation,
                    commandTemplate: "sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'",
                    requiresConfirmation: true,
                    timeout: 5
                )
            ],
            isBuiltin: true,
            estimatedDuration: 30,
            requiredPrivileges: ["sudo"]
        )
    }
}
