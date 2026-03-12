import Foundation
import UserNotifications

public struct TerminalCommandCompletion: Equatable, Sendable {
    public let command: String
    public let exitCode: Int?
    public let startedAt: Date
    public let finishedAt: Date
    public let duration: TimeInterval

    public init(
        command: String,
        exitCode: Int?,
        startedAt: Date,
        finishedAt: Date,
        duration: TimeInterval
    ) {
        self.command = command
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.duration = duration
    }
}

public struct TerminalSemanticUpdate: Sendable {
    public let commandCompletions: [TerminalCommandCompletion]
    public let workingDirectory: String?

    public init(commandCompletions: [TerminalCommandCompletion], workingDirectory: String?) {
        self.commandCompletions = commandCompletions
        self.workingDirectory = workingDirectory
    }
}

public enum TerminalShellKind: String, Sendable {
    case bash
    case zsh
    case fish
    case unknown
}

public actor TerminalCommandMonitor {
    private struct ActiveCommand {
        let command: String
        let startedAt: Date
    }

    private var activeCommand: ActiveCommand?
    private var pendingSubmittedCommand: String?
    private var currentInputLine: String = ""
    private var oscRemainder: String = ""

    public init() {}

    public func registerUserInput(_ text: String) {
        for character in text {
            switch character {
            case "\r", "\n":
                let trimmed = currentInputLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    pendingSubmittedCommand = trimmed
                }
                currentInputLine = ""
            case "\u{08}", "\u{7F}":
                if !currentInputLine.isEmpty {
                    currentInputLine.removeLast()
                }
            case "\u{15}":
                currentInputLine = ""
            default:
                guard !character.isOSC133IgnoredInput else { continue }
                currentInputLine.append(character)
            }
        }
    }

    public func consumeOutput(_ output: String) -> TerminalSemanticUpdate {
        let combined = oscRemainder + output
        let split = combined.splittingTrailingIncompleteOSCSequence()
        oscRemainder = split.trailingFragment

        var completions: [TerminalCommandCompletion] = []
        var workingDirectory: String?
        for token in split.completeText.oscTokens() {
            switch token.kind {
            case .prompt:
                continue
            case .commandStart:
                let command = pendingSubmittedCommand ?? currentInputLine
                let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
                activeCommand = ActiveCommand(
                    command: trimmed.isEmpty ? "Remote command" : trimmed,
                    startedAt: Date()
                )
                pendingSubmittedCommand = nil
            case .commandFinished(let exitCode):
                guard let activeCommand else { continue }
                let finishedAt = Date()
                completions.append(
                    TerminalCommandCompletion(
                        command: activeCommand.command,
                        exitCode: exitCode,
                        startedAt: activeCommand.startedAt,
                        finishedAt: finishedAt,
                        duration: finishedAt.timeIntervalSince(activeCommand.startedAt)
                    )
                )
                self.activeCommand = nil
            case .workingDirectory(let path):
                let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedPath.isEmpty {
                    workingDirectory = trimmedPath
                }
            }
        }
        return TerminalSemanticUpdate(
            commandCompletions: completions,
            workingDirectory: workingDirectory
        )
    }

    public static func shellKind(from shellPath: String?) -> TerminalShellKind {
        guard let shellPath else { return .unknown }
        let component = shellPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .last?
            .lowercased() ?? ""

        if component.contains("zsh") {
            return .zsh
        }
        if component.contains("bash") {
            return .bash
        }
        if component.contains("fish") {
            return .fish
        }
        return .unknown
    }

    public static func shellIntegrationScriptPath(for shellKind: TerminalShellKind) -> String? {
        switch shellKind {
        case .bash:
            return "/tmp/.rayon_osc133.bash"
        case .zsh:
            return "/tmp/.rayon_osc133.zsh"
        case .fish:
            return "/tmp/.rayon_osc133.fish"
        case .unknown:
            return nil
        }
    }

    public static func shellIntegrationSourceCommand(for shellKind: TerminalShellKind) -> String? {
        guard let scriptPath = shellIntegrationScriptPath(for: shellKind) else { return nil }

        switch shellKind {
        case .bash, .zsh:
            return ". \(scriptPath)"
        case .fish:
            return "source \(scriptPath)"
        case .unknown:
            return nil
        }
    }

    public static func shellIntegrationBootstrap(for shellKind: TerminalShellKind) -> String? {
        switch shellKind {
        case .zsh:
            return #"""
            if [ "${RAYON_OSC133_INSTALLED:-0}" != "1" ]; then
              export RAYON_OSC133=1
              export RAYON_OSC133_INSTALLED=1
              __rayon_emit_cwd() { printf '\033]777;cwd=%s\a' "$PWD"; }
              autoload -Uz add-zsh-hook 2>/dev/null || true
              __rayon_precmd() { local ec=$?; printf '\033]133;D;%s\a' "$ec"; __rayon_emit_cwd; printf '\033]133;A\a'; }
              __rayon_preexec() { printf '\033]133;B\a'; }
              add-zsh-hook precmd __rayon_precmd 2>/dev/null || true
              add-zsh-hook preexec __rayon_preexec 2>/dev/null || true
            fi
            __rayon_emit_cwd
            printf '\033]133;A\a'
            """#
        case .bash:
            return #"""
            if [ "${RAYON_OSC133_INSTALLED:-0}" != "1" ]; then
              export RAYON_OSC133=1
              export RAYON_OSC133_INSTALLED=1
              __rayon_emit_cwd() { printf '\033]777;cwd=%s\a' "$PWD"; }
              __rayon_prompt_command() {
                local ec=$?
                printf '\033]133;D;%s\a' "$ec"
                __rayon_emit_cwd
                printf '\033]133;A\a'
              }
              PROMPT_COMMAND="__rayon_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
              PS0=$'\033]133;B\a'
            fi
            __rayon_emit_cwd
            printf '\033]133;A\a'
            """#
        case .fish:
            return #"""
            if not set -q RAYON_OSC133_INSTALLED
                set -gx RAYON_OSC133 1
                set -gx RAYON_OSC133_INSTALLED 1
                functions -e __rayon_emit_cwd 2>/dev/null
                functions -e __rayon_preexec 2>/dev/null
                functions -e __rayon_postexec 2>/dev/null
                function __rayon_emit_cwd
                    printf '\033]777;cwd=%s\a' "$PWD"
                end
                function __rayon_preexec --on-event fish_preexec
                    printf '\033]133;B\a'
                end
                function __rayon_postexec --on-event fish_postexec
                    printf '\033]133;D;%s\a' $status
                end
                if functions -q __rayon_original_fish_prompt
                    functions -e __rayon_original_fish_prompt
                end
                if functions -q fish_prompt
                    functions -c fish_prompt __rayon_original_fish_prompt
                end
                function fish_prompt
                    __rayon_emit_cwd
                    printf '\033]133;A\a'
                    __rayon_original_fish_prompt
                end
            end
            __rayon_emit_cwd
            printf '\033]133;A\a'
            """#
        case .unknown:
            return nil
        }
    }
}

public enum TerminalCommandNotificationCenter {
    private static let permissionRequestedKey = "wiki.qaq.rayon.terminal.commandNotifications.permissionRequested"

    public static func requestAuthorizationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: permissionRequestedKey) else { return }
        UserDefaults.standard.set(true, forKey: permissionRequestedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public static func notify(host: String, completion: TerminalCommandCompletion) {
        let content = UNMutableNotificationContent()
        content.title = "Command finished on \(host)"
        content.body = notificationBody(for: completion)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func notificationBody(for completion: TerminalCommandCompletion) -> String {
        let duration = completion.duration.terminalNotificationDurationLabel
        let status: String
        if let exitCode = completion.exitCode {
            status = exitCode == 0 ? "exit 0" : "exit \(exitCode)"
        } else {
            status = "finished"
        }
        return "\(completion.command) • \(duration) • \(status)"
    }
}

private struct OSCToken {
    enum Kind {
        case prompt
        case commandStart
        case commandFinished(Int?)
        case workingDirectory(String)
    }

    let kind: Kind
}

private extension String {
    func oscTokens() -> [OSCToken] {
        let pattern = #"\u{001B}\]([0-9]+);([^\u{0007}\u{001B}]*)?(?:\u{0007}|\u{001B}\\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)

        return regex.matches(in: self, range: range).compactMap { match in
            guard let codeRange = Range(match.range(at: 1), in: self) else { return nil }
            guard let payloadRange = Range(match.range(at: 2), in: self) else { return nil }
            let code = String(self[codeRange])
            let payload = String(self[payloadRange])
            if code == "133", payload == "A" {
                return OSCToken(kind: .prompt)
            }
            if code == "133", payload == "B" {
                return OSCToken(kind: .commandStart)
            }
            if code == "133", payload.hasPrefix("D") {
                let components = payload.split(separator: ";", omittingEmptySubsequences: false)
                let exitCode = components.count > 1 ? Int(components[1]) : nil
                return OSCToken(kind: .commandFinished(exitCode))
            }
            if code == "777", payload.hasPrefix("cwd=") {
                return OSCToken(kind: .workingDirectory(String(payload.dropFirst(4))))
            }
            return nil
        }
    }

    func splittingTrailingIncompleteOSCSequence() -> (completeText: String, trailingFragment: String) {
        guard let escapeIndex = range(of: "\u{1B}]", options: .backwards)?.lowerBound else {
            return (self, "")
        }

        let tail = String(self[escapeIndex...])
        if tail.contains("\u{07}") || tail.contains("\u{1B}\\") {
            return (self, "")
        }

        return (String(self[..<escapeIndex]), tail)
    }
}

private extension Character {
    var isOSC133IgnoredInput: Bool {
        unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x00...0x07, 0x0B, 0x0C, 0x0E...0x1F:
                return true
            default:
                return false
            }
        }
    }
}

private extension TimeInterval {
    var terminalNotificationDurationLabel: String {
        if self >= 60 {
            let minutes = Int(self) / 60
            let seconds = Int(self) % 60
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        }
        return "\(max(Int(self.rounded()), 1))s"
    }
}
