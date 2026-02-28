import CloudKit
import DataSync
import Foundation

public struct RDAppSettingsSync: Codable, Equatable {
    public static let globalRecordName = "global-settings"

    public struct SettingsPayload: Codable, Equatable {
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
    }

    public init(
        id: String = RDAppSettingsSync.globalRecordName,
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
        fileTransferResumeEnabled: Bool,
        lastModifiedDate: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
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
        self.lastModifiedDate = lastModifiedDate
        self.isDeleted = isDeleted
    }

    public var id: String
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
    public var lastModifiedDate: Date
    public var isDeleted: Bool

    public var payload: SettingsPayload {
        .init(
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
    }

    private func payloadString() -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }
}

extension RDAppSettingsSync: iCloudSyncItem {
    public static func recordType() -> String {
        "RDAppSettingsSync"
    }

    public static func saveToLocal(record: CKRecord) {
        let item = RDAppSettingsSync(With: record)
        mainActor {
            RayonStore.shared.applySettingsSync(item)
        }
    }

    public func update(to record: CKRecord) {
        record.setValue(id, forKey: "id")
        record.setValue(payloadString(), forKey: "payload")
        record.setValue(lastModifiedDate, forKey: "lastModifiedDate")
        record.setValue(isDeleted, forKey: "isDeleted")
    }

    public func generateRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType(), recordID: recordId)
        update(to: record)
        return record
    }

    public var recordId: CKRecord.ID {
        CKRecord.ID(recordName: id)
    }

    public init(With record: CKRecord) {
        id = record["id"] as? String ?? Self.globalRecordName

        if let payloadString = record["payload"] as? String,
           let data = payloadString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(SettingsPayload.self, from: data)
        {
            timeout = decoded.timeout
            monitorInterval = decoded.monitorInterval
            reducedViewEffects = decoded.reducedViewEffects
            disableConformation = decoded.disableConformation
            storeRecent = decoded.storeRecent
            saveTemporarySession = decoded.saveTemporarySession
            terminalFontSize = decoded.terminalFontSize
            terminalFontName = decoded.terminalFontName
            themePreference = decoded.themePreference
            terminalThemeName = decoded.terminalThemeName
            useTmux = decoded.useTmux
            tmuxSessionName = decoded.tmuxSessionName
            tmuxAutoCreate = decoded.tmuxAutoCreate
            speechInputEngine = decoded.speechInputEngine
            speechInputLocaleIdentifier = decoded.speechInputLocaleIdentifier
            openInterfaceAutomatically = decoded.openInterfaceAutomatically
            fileTransferConflictPolicy = decoded.fileTransferConflictPolicy
            fileTransferMaxConcurrent = decoded.fileTransferMaxConcurrent
            fileTransferRateLimitKBps = decoded.fileTransferRateLimitKBps
            fileTransferResumeEnabled = decoded.fileTransferResumeEnabled
        } else {
            // Backward compatibility: read legacy flat fields if payload is unavailable.
            timeout = record["timeout"] as? Int ?? 5
            monitorInterval = record["monitorInterval"] as? Int ?? 5
            reducedViewEffects = record["reducedViewEffects"] as? Bool ?? false
            disableConformation = record["disableConformation"] as? Bool ?? false
            storeRecent = record["storeRecent"] as? Bool ?? true
            saveTemporarySession = record["saveTemporarySession"] as? Bool ?? true
            terminalFontSize = record["terminalFontSize"] as? Int ?? 14
            terminalFontName = record["terminalFontName"] as? String ?? "Menlo"
            themePreference = record["themePreference"] as? String ?? "system"
            terminalThemeName = record["terminalThemeName"] as? String ?? "Default"
            useTmux = record["useTmux"] as? Bool ?? false
            tmuxSessionName = record["tmuxSessionName"] as? String ?? "default"
            tmuxAutoCreate = record["tmuxAutoCreate"] as? Bool ?? true
            speechInputEngine = record["speechInputEngine"] as? String ?? "apple"
            speechInputLocaleIdentifier = record["speechInputLocaleIdentifier"] as? String ?? "system"
            openInterfaceAutomatically = record["openInterfaceAutomatically"] as? Bool ?? true
            fileTransferConflictPolicy = record["fileTransferConflictPolicy"] as? String ?? "rename"
            fileTransferMaxConcurrent = record["fileTransferMaxConcurrent"] as? Int ?? 2
            fileTransferRateLimitKBps = record["fileTransferRateLimitKBps"] as? Int ?? 0
            fileTransferResumeEnabled = record["fileTransferResumeEnabled"] as? Bool ?? true
        }

        lastModifiedDate = record["lastModifiedDate"] as? Date ?? Date()
        isDeleted = record["isDeleted"] as? Bool ?? false
    }
}

public extension RayonStore {
    func buildSettingsSyncPayload() -> RDAppSettingsSync {
        RDAppSettingsSync(
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
            fileTransferResumeEnabled: fileTransferResumeEnabled,
            lastModifiedDate: Date(),
            isDeleted: false
        )
    }

    func applySettingsSync(_ settings: RDAppSettingsSync) {
        timeout = settings.timeout
        monitorInterval = settings.monitorInterval
        reducedViewEffects = settings.reducedViewEffects
        disableConformation = settings.disableConformation
        storeRecent = settings.storeRecent
        saveTemporarySession = settings.saveTemporarySession
        terminalFontSize = settings.terminalFontSize
        terminalFontName = settings.terminalFontName
        themePreference = settings.themePreference
        terminalThemeName = settings.terminalThemeName
        useTmux = settings.useTmux
        tmuxSessionName = settings.tmuxSessionName
        tmuxAutoCreate = settings.tmuxAutoCreate
        speechInputEngine = settings.speechInputEngine
        speechInputLocaleIdentifier = settings.speechInputLocaleIdentifier
        openInterfaceAutomatically = settings.openInterfaceAutomatically
        fileTransferConflictPolicy = settings.fileTransferConflictPolicy
        fileTransferMaxConcurrent = settings.fileTransferMaxConcurrent
        fileTransferRateLimitKBps = settings.fileTransferRateLimitKBps
        fileTransferResumeEnabled = settings.fileTransferResumeEnabled
    }
}
