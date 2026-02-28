import Foundation

public struct SyncSnapshot: Codable, Identifiable {
    public struct Settings: Codable, Equatable {
        public var timeout: Int
        public var monitorInterval: Int
        public var reducedViewEffects: Bool
        public var disableConformation: Bool
        public var storeRecent: Bool
        public var saveTemporarySession: Bool
        public var terminalFontSize: Int
        public var terminalFontName: String
        public var themePreference: String
        public var terminalThemeName: String
        public var useTmux: Bool
        public var tmuxSessionName: String
        public var tmuxAutoCreate: Bool
        public var speechInputEngine: String
        public var speechInputLocaleIdentifier: String
        public var openInterfaceAutomatically: Bool
        public var fileTransferConflictPolicy: String
        public var fileTransferMaxConcurrent: Int
        public var fileTransferRateLimitKBps: Int
        public var fileTransferResumeEnabled: Bool

        enum CodingKeys: String, CodingKey {
            case timeout
            case monitorInterval
            case reducedViewEffects
            case disableConformation
            case storeRecent
            case saveTemporarySession
            case terminalFontSize
            case terminalFontName
            case themePreference
            case terminalThemeName
            case useTmux
            case tmuxSessionName
            case tmuxAutoCreate
            case speechInputEngine
            case speechInputLocaleIdentifier
            case openInterfaceAutomatically
            case fileTransferConflictPolicy
            case fileTransferMaxConcurrent
            case fileTransferRateLimitKBps
            case fileTransferResumeEnabled
        }

        public init(
            timeout: Int,
            monitorInterval: Int,
            reducedViewEffects: Bool,
            disableConformation: Bool,
            storeRecent: Bool,
            saveTemporarySession: Bool,
            terminalFontSize: Int,
            terminalFontName: String,
            themePreference: String,
            terminalThemeName: String,
            useTmux: Bool,
            tmuxSessionName: String,
            tmuxAutoCreate: Bool,
            speechInputEngine: String,
            speechInputLocaleIdentifier: String,
            openInterfaceAutomatically: Bool,
            fileTransferConflictPolicy: String,
            fileTransferMaxConcurrent: Int,
            fileTransferRateLimitKBps: Int,
            fileTransferResumeEnabled: Bool
        ) {
            self.timeout = timeout
            self.monitorInterval = monitorInterval
            self.reducedViewEffects = reducedViewEffects
            self.disableConformation = disableConformation
            self.storeRecent = storeRecent
            self.saveTemporarySession = saveTemporarySession
            self.terminalFontSize = terminalFontSize
            self.terminalFontName = terminalFontName
            self.themePreference = themePreference
            self.terminalThemeName = terminalThemeName
            self.useTmux = useTmux
            self.tmuxSessionName = tmuxSessionName
            self.tmuxAutoCreate = tmuxAutoCreate
            self.speechInputEngine = speechInputEngine
            self.speechInputLocaleIdentifier = speechInputLocaleIdentifier
            self.openInterfaceAutomatically = openInterfaceAutomatically
            self.fileTransferConflictPolicy = fileTransferConflictPolicy
            self.fileTransferMaxConcurrent = fileTransferMaxConcurrent
            self.fileTransferRateLimitKBps = fileTransferRateLimitKBps
            self.fileTransferResumeEnabled = fileTransferResumeEnabled
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timeout = try container.decode(Int.self, forKey: .timeout)
            monitorInterval = try container.decode(Int.self, forKey: .monitorInterval)
            reducedViewEffects = try container.decode(Bool.self, forKey: .reducedViewEffects)
            disableConformation = try container.decode(Bool.self, forKey: .disableConformation)
            storeRecent = try container.decode(Bool.self, forKey: .storeRecent)
            saveTemporarySession = try container.decode(Bool.self, forKey: .saveTemporarySession)
            terminalFontSize = try container.decode(Int.self, forKey: .terminalFontSize)
            terminalFontName = try container.decode(String.self, forKey: .terminalFontName)
            themePreference = try container.decode(String.self, forKey: .themePreference)
            terminalThemeName = try container.decode(String.self, forKey: .terminalThemeName)
            useTmux = try container.decode(Bool.self, forKey: .useTmux)
            tmuxSessionName = try container.decode(String.self, forKey: .tmuxSessionName)
            tmuxAutoCreate = try container.decode(Bool.self, forKey: .tmuxAutoCreate)
            speechInputEngine = try container.decodeIfPresent(String.self, forKey: .speechInputEngine) ?? "apple"
            speechInputLocaleIdentifier = try container.decodeIfPresent(String.self, forKey: .speechInputLocaleIdentifier) ?? "system"
            openInterfaceAutomatically = try container.decode(Bool.self, forKey: .openInterfaceAutomatically)
            fileTransferConflictPolicy = try container.decode(String.self, forKey: .fileTransferConflictPolicy)
            fileTransferMaxConcurrent = try container.decode(Int.self, forKey: .fileTransferMaxConcurrent)
            fileTransferRateLimitKBps = try container.decode(Int.self, forKey: .fileTransferRateLimitKBps)
            fileTransferResumeEnabled = try container.decode(Bool.self, forKey: .fileTransferResumeEnabled)
        }
    }

    public let id: UUID
    public let createdAt: Date
    public let reason: String
    public let machineGroup: RDMachineGroup
    public let identityGroup: RDIdentityGroup
    public let snippetGroup: RDSnippetGroup
    public let portForwardGroup: RDPortForwardGroup
    public let settings: Settings

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        reason: String,
        machineGroup: RDMachineGroup,
        identityGroup: RDIdentityGroup,
        snippetGroup: RDSnippetGroup,
        portForwardGroup: RDPortForwardGroup,
        settings: Settings
    ) {
        self.id = id
        self.createdAt = createdAt
        self.reason = reason
        self.machineGroup = machineGroup
        self.identityGroup = identityGroup
        self.snippetGroup = snippetGroup
        self.portForwardGroup = portForwardGroup
        self.settings = settings
    }
}

public extension RayonStore {
    private static let maxSyncSnapshotCount = 30

    public func createSyncSnapshot(reason: String) {
        let settings = SyncSnapshot.Settings(
            timeout: timeout,
            monitorInterval: monitorInterval,
            reducedViewEffects: reducedViewEffects,
            disableConformation: disableConformation,
            storeRecent: storeRecent,
            saveTemporarySession: saveTemporarySession,
            terminalFontSize: terminalFontSize,
            terminalFontName: terminalFontName,
            themePreference: themePreference,
            terminalThemeName: terminalThemeName,
            useTmux: useTmux,
            tmuxSessionName: tmuxSessionName,
            tmuxAutoCreate: tmuxAutoCreate,
            speechInputEngine: speechInputEngine,
            speechInputLocaleIdentifier: speechInputLocaleIdentifier,
            openInterfaceAutomatically: openInterfaceAutomatically,
            fileTransferConflictPolicy: fileTransferConflictPolicy,
            fileTransferMaxConcurrent: fileTransferMaxConcurrent,
            fileTransferRateLimitKBps: fileTransferRateLimitKBps,
            fileTransferResumeEnabled: fileTransferResumeEnabled
        )

        var snapshots = listSyncSnapshots()
        snapshots.append(
            SyncSnapshot(
                reason: reason,
                machineGroup: machineGroup,
                identityGroup: identityGroup,
                snippetGroup: snippetGroup,
                portForwardGroup: portForwardGroup,
                settings: settings
            )
        )

        if snapshots.count > Self.maxSyncSnapshotCount {
            snapshots.removeFirst(snapshots.count - Self.maxSyncSnapshotCount)
        }

        storeEncryptedDefault(to: .syncSnapshotsEncrypted, with: snapshots)
    }

    public func listSyncSnapshots() -> [SyncSnapshot] {
        readEncryptedDefault(from: .syncSnapshotsEncrypted, [SyncSnapshot]()) ?? []
    }

    @discardableResult
    public func rollbackSyncSnapshot(id: UUID) -> Bool {
        guard let target = listSyncSnapshots().first(where: { $0.id == id }) else {
            return false
        }

        mainActor {
            self.machineGroup = target.machineGroup
            self.identityGroup = target.identityGroup
            self.snippetGroup = target.snippetGroup
            self.portForwardGroup = target.portForwardGroup

            self.timeout = target.settings.timeout
            self.monitorInterval = target.settings.monitorInterval
            self.reducedViewEffects = target.settings.reducedViewEffects
            self.disableConformation = target.settings.disableConformation
            self.storeRecent = target.settings.storeRecent
            self.saveTemporarySession = target.settings.saveTemporarySession
            self.terminalFontSize = target.settings.terminalFontSize
            self.terminalFontName = target.settings.terminalFontName
            self.themePreference = target.settings.themePreference
            self.terminalThemeName = target.settings.terminalThemeName
            self.useTmux = target.settings.useTmux
            self.tmuxSessionName = target.settings.tmuxSessionName
            self.tmuxAutoCreate = target.settings.tmuxAutoCreate
            self.speechInputEngine = target.settings.speechInputEngine
            self.speechInputLocaleIdentifier = target.settings.speechInputLocaleIdentifier
            self.openInterfaceAutomatically = target.settings.openInterfaceAutomatically
            self.fileTransferConflictPolicy = target.settings.fileTransferConflictPolicy
            self.fileTransferMaxConcurrent = target.settings.fileTransferMaxConcurrent
            self.fileTransferRateLimitKBps = target.settings.fileTransferRateLimitKBps
            self.fileTransferResumeEnabled = target.settings.fileTransferResumeEnabled
        }

        return true
    }
}
