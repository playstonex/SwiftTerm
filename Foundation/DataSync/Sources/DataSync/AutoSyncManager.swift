//
//  AutoSyncManager.swift
//  DataSync
//
//  Created by Claude on 2026/2/16.
//

import Foundation
import CloudKit
import Combine

/// Manages automatic synchronization with CloudKit
@MainActor
public class AutoSyncManager: ObservableObject {
    public static let shared = AutoSyncManager()

    // MARK: - Published Properties

    @Published public var isSyncing: Bool = false
    public var lastSyncDate: Date? {
        iCloudStoreSync.share.syncDate
    }
    @Published public var syncError: Error?

    // MARK: - Private Properties

    private let syncManager = iCloudStoreSync.share
    private var debounceTimer: Timer?
    private let debounceDelay: TimeInterval = 2.0 // seconds to wait after data changes
    private var autoSyncHandler: (() async -> Void)?
    private var unsupportedRecordTypes = Set<String>()

    private init() {}

    // MARK: - Configuration

    /// Register app-level sync handler to execute full sync logic.
    public func registerAutoSyncHandler(_ handler: @escaping () async -> Void) {
        autoSyncHandler = handler
    }

    // MARK: - Public Methods

    /// Perform automatic sync on app launch
    public func syncOnAppLaunch() async {
        // Only sync if last sync was more than 5 minutes ago
        let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)

        if lastSyncDate == nil || (lastSyncDate != nil && (lastSyncDate ?? .distantPast) < fiveMinutesAgo) {
            print("AutoSync: Syncing on app launch")
            await autoSyncHandler?()
        }
    }

    /// Trigger sync with debounce (for data changes)
    public func triggerSync() {
        // Cancel any pending sync
        debounceTimer?.invalidate()

        // Schedule a new debounced sync
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay,
                                               repeats: false) { [weak self] _ in
            Task { @MainActor in
                print("AutoSync: Triggered by data change")
                self?.syncError = nil
                await self?.autoSyncHandler?()
            }
        }
    }

    /// Force immediate sync (ignoring debounce)
    public func forceSyncNow() async {
        debounceTimer?.invalidate()
        print("AutoSync: Forced sync")
        await autoSyncHandler?()
    }

    /// Sync specific data types (for manual sync button)
    @available(macOS 12.0, iOS 15.0, *)
    public func sync<T: iCloudSyncItem>(items: [T]) async {
        let recordType = T.recordType()
        guard !unsupportedRecordTypes.contains(recordType) else { return }
        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil

        do {
            try await syncManager.startSync(items: items)
            syncManager.finishSync()

            try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000)) // 1 second delay
            NotificationCenter.default.post(name: .syncDataDidUpdate, object: nil)

            print("AutoSync: Synced \(items.count) items")

        } catch let error {
            if isSchemaNotReadyError(error) {
                unsupportedRecordTypes.insert(recordType)
                print("AutoSync: CloudKit schema for '\(recordType)' is not ready (missing type or index). Skipping this type until app restart.")
            } else {
                syncError = error
                print("Auto-sync failed: \(error.localizedDescription)")
            }
        }

        isSyncing = false
    }

    private func isSchemaNotReadyError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = [
            error.localizedDescription,
            nsError.localizedDescription,
            nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return message.contains("did not find record type")
            || message.contains("type is not marked indexable")
    }
}

// MARK: - Sync Errors

public enum SyncError: LocalizedError {
    case cloudKitNotAvailable
    case syncInProgress

    public var errorDescription: String? {
        switch self {
        case .cloudKitNotAvailable:
            return "CloudKit is not available. Please check your internet connection and iCloud settings."
        case .syncInProgress:
            return "A sync operation is already in progress."
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let syncDataDidUpdate = Notification.Name("syncDataDidUpdate")
}
