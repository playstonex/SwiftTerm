import Foundation
import NSRemoteShell

public struct AutomationSchedule: Codable, Equatable {
    public enum Kind: String, Codable {
        case manual
        case interval
        case daily
    }

    public init(kind: Kind, intervalMinutes: Int = 0, hour: Int = 0, minute: Int = 0) {
        self.kind = kind
        self.intervalMinutes = max(0, intervalMinutes)
        self.hour = hour
        self.minute = minute
    }

    public var kind: Kind
    public var intervalMinutes: Int
    public var hour: Int
    public var minute: Int

    public static let manual = AutomationSchedule(kind: .manual)

    func isDue(now: Date, lastRunAt: Date?) -> Bool {
        switch kind {
        case .manual:
            return false
        case .interval:
            guard intervalMinutes > 0 else { return false }
            guard let lastRunAt else { return true }
            return now.timeIntervalSince(lastRunAt) >= Double(intervalMinutes * 60)
        case .daily:
            let calendar = Calendar.current
            let target = calendar.dateComponents([.year, .month, .day], from: now)
            guard let scheduled = calendar.date(
                from: DateComponents(
                    year: target.year,
                    month: target.month,
                    day: target.day,
                    hour: hour,
                    minute: minute,
                    second: 0
                )
            ) else {
                return false
            }
            guard now >= scheduled else { return false }
            guard let lastRunAt else { return true }
            return !calendar.isDate(lastRunAt, inSameDayAs: now)
        }
    }
}

public struct AutomationTask: Codable, Identifiable, Equatable {
    public init(
        id: UUID = UUID(),
        name: String,
        snippetId: UUID,
        machineIds: [UUID],
        schedule: AutomationSchedule,
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.snippetId = snippetId
        self.machineIds = machineIds
        self.schedule = schedule
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunAt = lastRunAt
    }

    public var id: UUID
    public var name: String
    public var snippetId: UUID
    public var machineIds: [UUID]
    public var schedule: AutomationSchedule
    public var enabled: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var lastRunAt: Date?
}

public struct AutomationMachineResult: Codable, Equatable {
    public init(machineId: UUID, machineName: String, success: Bool, message: String, duration: TimeInterval) {
        self.machineId = machineId
        self.machineName = machineName
        self.success = success
        self.message = message
        self.duration = duration
    }

    public var machineId: UUID
    public var machineName: String
    public var success: Bool
    public var message: String
    public var duration: TimeInterval
}

public struct AutomationExecutionRecord: Codable, Identifiable, Equatable {
    public init(
        id: UUID = UUID(),
        taskId: UUID,
        taskName: String,
        startedAt: Date,
        endedAt: Date,
        triggeredBy: String,
        success: Bool,
        results: [AutomationMachineResult]
    ) {
        self.id = id
        self.taskId = taskId
        self.taskName = taskName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.triggeredBy = triggeredBy
        self.success = success
        self.results = results
    }

    public var id: UUID
    public var taskId: UUID
    public var taskName: String
    public var startedAt: Date
    public var endedAt: Date
    public var triggeredBy: String
    public var success: Bool
    public var results: [AutomationMachineResult]
}

@MainActor
public final class AutomationManager: ObservableObject {
    public static let shared = AutomationManager()

    @Published public private(set) var tasks: [AutomationTask] = []
    @Published public private(set) var executionHistory: [AutomationExecutionRecord] = []
    @Published public private(set) var activeRuns: Set<UUID> = []

    private let taskStoreKey = "wiki.qaq.rayon.automation.tasks.v1"
    private let historyStoreKey = "wiki.qaq.rayon.automation.history.v1"
    private let maxHistoryCount = 300
    private var tickTimer: Timer?

    private init() {
        loadPersistedData()
    }

    public func startScheduler() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tickScheduler()
            }
        }
    }

    public func stopScheduler() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    public func upsertTask(_ task: AutomationTask) {
        var incoming = task
        incoming.updatedAt = Date()
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = incoming
        } else {
            tasks.append(incoming)
        }
        persistTasks()
    }

    public func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        persistTasks()
    }

    public func runNow(taskId: UUID) async {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }
        await runTask(task, triggeredBy: "manual")
    }

    public func recentExecutionHistory(limit: Int = 50) -> [AutomationExecutionRecord] {
        Array(executionHistory.suffix(limit).reversed())
    }

    private func tickScheduler() async {
        let now = Date()
        for task in tasks where task.enabled {
            if task.schedule.isDue(now: now, lastRunAt: task.lastRunAt) {
                await runTask(task, triggeredBy: "schedule")
            }
        }
    }

    private func runTask(_ task: AutomationTask, triggeredBy: String) async {
        guard !activeRuns.contains(task.id) else { return }
        guard let snippet = RayonStore.shared.snippetGroup.snippets.first(where: { $0.id == task.snippetId }) else { return }

        activeRuns.insert(task.id)
        defer { activeRuns.remove(task.id) }

        var currentTask = task
        currentTask.lastRunAt = Date()
        currentTask.updatedAt = Date()
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = currentTask
        }
        persistTasks()

        let startedAt = Date()
        var results: [AutomationMachineResult] = []

        for machineId in currentTask.machineIds {
            let result = await executeSnippet(snippet.code, on: machineId)
            results.append(result)
        }

        let success = results.allSatisfy(\.success)
        let record = AutomationExecutionRecord(
            taskId: currentTask.id,
            taskName: currentTask.name,
            startedAt: startedAt,
            endedAt: Date(),
            triggeredBy: triggeredBy,
            success: success,
            results: results
        )
        executionHistory.append(record)
        if executionHistory.count > maxHistoryCount {
            executionHistory.removeFirst(executionHistory.count - maxHistoryCount)
        }
        persistHistory()
    }

    private func executeSnippet(_ command: String, on machineId: UUID) async -> AutomationMachineResult {
        let started = Date()
        let machine = RayonStore.shared.machineGroup[machineId]
        guard machine.isNotPlaceholder() else {
            return AutomationMachineResult(
                machineId: machineId,
                machineName: "Unknown",
                success: false,
                message: "Machine not found",
                duration: Date().timeIntervalSince(started)
            )
        }

        guard let identityId = machine.associatedIdentity,
              let uuid = UUID(uuidString: identityId)
        else {
            return AutomationMachineResult(
                machineId: machineId,
                machineName: machine.name,
                success: false,
                message: "No identity bound",
                duration: Date().timeIntervalSince(started)
            )
        }

        let identity = RayonStore.shared.identityGroup[uuid]
        guard !identity.username.isEmpty else {
            return AutomationMachineResult(
                machineId: machineId,
                machineName: machine.name,
                success: false,
                message: "Identity missing",
                duration: Date().timeIntervalSince(started)
            )
        }

        let shell = NSRemoteShell()
            .setupConnectionHost(machine.remoteAddress)
            .setupConnectionPort(NSNumber(value: Int(machine.remotePort) ?? 22))
            .setupConnectionTimeout(RayonStore.shared.timeoutNumber)

        shell.requestConnectAndWait()
        guard shell.isConnected else {
            return AutomationMachineResult(
                machineId: machineId,
                machineName: machine.name,
                success: false,
                message: "Connection failed",
                duration: Date().timeIntervalSince(started)
            )
        }

        identity.callAuthenticationWith(remote: shell)
        guard shell.isAuthenticated else {
            shell.requestDisconnectAndWait()
            return AutomationMachineResult(
                machineId: machineId,
                machineName: machine.name,
                success: false,
                message: "Authentication failed",
                duration: Date().timeIntervalSince(started)
            )
        }

        var output = ""
        shell.beginExecute(
            withCommand: command,
            withTimeout: NSNumber(value: 0),
            withOnCreate: {},
            withOutput: { chunk in
                output.append(chunk)
            },
            withContinuationHandler: nil
        )
        shell.requestDisconnectAndWait()

        return AutomationMachineResult(
            machineId: machineId,
            machineName: machine.name,
            success: true,
            message: output.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: Date().timeIntervalSince(started)
        )
    }

    private func persistTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: taskStoreKey)
        }
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(executionHistory) {
            UserDefaults.standard.set(data, forKey: historyStoreKey)
        }
    }

    private func loadPersistedData() {
        if let taskData = UserDefaults.standard.data(forKey: taskStoreKey),
           let decodedTasks = try? JSONDecoder().decode([AutomationTask].self, from: taskData)
        {
            tasks = decodedTasks
        }

        if let historyData = UserDefaults.standard.data(forKey: historyStoreKey),
           let decodedHistory = try? JSONDecoder().decode([AutomationExecutionRecord].self, from: historyData)
        {
            executionHistory = decodedHistory
        }
    }
}
