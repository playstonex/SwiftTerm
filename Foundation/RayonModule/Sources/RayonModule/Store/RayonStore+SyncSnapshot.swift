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
        public var openInterfaceAutomatically: Bool
        public var fileTransferConflictPolicy: String
        public var fileTransferMaxConcurrent: Int
        public var fileTransferRateLimitKBps: Int
        public var fileTransferResumeEnabled: Bool
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
            self.openInterfaceAutomatically = target.settings.openInterfaceAutomatically
            self.fileTransferConflictPolicy = target.settings.fileTransferConflictPolicy
            self.fileTransferMaxConcurrent = target.settings.fileTransferMaxConcurrent
            self.fileTransferRateLimitKBps = target.settings.fileTransferRateLimitKBps
            self.fileTransferResumeEnabled = target.settings.fileTransferResumeEnabled
        }

        return true
    }
}
