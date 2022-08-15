//
//  File.swift
//  
//
//  Created by Lei Guo on 2022/8/9.
//

import Foundation
import CloudKit

public protocol iCloudSyncItem : Codable {
    
    static func recordType() -> String
    
    static func saveToLocal(record:CKRecord)
    
    var lastModifiedDate:Date { get  }
    var isDeleted:Bool {get}
    
    func update(to record:CKRecord)
    
    func generateRecord() -> CKRecord
    
    var recordId: CKRecord.ID {get}
    
    init(With record:CKRecord)
}

enum CompareResult {
    case remoteNeedUpdate
    case localNeedUpdate
    case same
}

extension iCloudSyncItem {
    func compareWithRecord(record:CKRecord) -> CompareResult {
        if let remoteModifiedDate = record["lastModifiedDate"] as? Date {
            let interval = remoteModifiedDate.timeIntervalSince(self.lastModifiedDate)
            if interval == 0 {
                return .same
            }
            else if interval > 0 {
                return .localNeedUpdate
            }
            else {
                return .remoteNeedUpdate
            }
        }
        return .remoteNeedUpdate
    }
    
}

public class iCloudStoreSync {
    
    public static let share = iCloudStoreSync()
    
    let db = CKContainer(identifier: "iCloud.com.playstone.bigserver.cloud.store") .privateCloudDatabase
    
    var lastSyncDate : Date = Date(timeIntervalSince1970: 0)
    fileprivate  init() {
        dataSetup()
    }
    
    func dataSetup () {
        if let date = UserDefaults.standard.value(forKey: "kCloudStoreSyncLastSyncDate") as? Date {
            self.lastSyncDate = date
        }
    }
    
    public func upload(item: iCloudSyncItem) async throws {
        
        let record = item.generateRecord()
        
        do {
            try await db.save(record)
        }
        catch let error {
            throw error
        }
    }
    
    
    public func syncItem<T:iCloudSyncItem>(items:[T]) async throws {
        do {
            let ids = items.map {$0.recordId};
            if #available(iOS 15.0, macOS 12.0,*) {
                let fetchResults = try await db.records(for: ids)
            
                var needLocalUpdates : [CKRecord] = items.filter { item in
                    if let recordResult = fetchResults[item.recordId],
                       let record = try? recordResult.get() {
                        return item.compareWithRecord(record: record) == .localNeedUpdate
                    }
                    return false
                }.compactMap {try? fetchResults[$0.recordId]?.get()}
                var needRemoteUpdate : [T] = items.filter { item in
                    if let recordResult = fetchResults[item.recordId],
                       let record = try? recordResult.get() {
                        return item.compareWithRecord(record: record) == .remoteNeedUpdate
                    }
                    return true
                }
            } else {
                // Fallback on earlier versions
            }
            
            
        } catch let error {
            throw error
        }
    }
    
    public func finishSync() {
        self.lastSyncDate = Date()
        UserDefaults.standard.set(self.lastSyncDate, forKey: "kCloudStoreSyncLastSyncDate")
    }
    
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func startSync<T:iCloudSyncItem>(items:[T]) async throws {
        
        let moditifiedRemoteRecords = try await self.db.records(type: T.self,
                                                         predicate: NSPredicate(format: "lastModifiedDate >= %@", self.lastSyncDate as CVarArg))
//        let moditifiedRemoteRecords = try await self.db.records(type: T.self)
        
        let moditifiedLocalItems = items.filter { $0.lastModifiedDate.timeIntervalSince(self.lastSyncDate) > 0 }
        
        var remoteIdRecrds = moditifiedRemoteRecords.reduce([String:(CKRecord, Date)]()) { partialResult, record in
            //            guard let idString = record["id"] as? String,
            //               let date = record["lastModifiedDate"] as? Date else {
            //                return partialResult
//        }
            guard let idString = record["id"] as? String  else {
               
                return partialResult
              }
            let date = record["lastModifiedDate"] as? Date ?? Date()
            return partialResult.merging([idString:(record, date)]) { $0.1.timeIntervalSince($1.1) > 0 ? $0 : $1 }
        }
        
        var localIdItems = moditifiedLocalItems.reduce([String:(iCloudSyncItem, Date)]()) { partialResult, item in
            
            return partialResult.merging([item.recordId.recordName:(item, item.lastModifiedDate)]) { $0.1.timeIntervalSince($1.1) > 0 ? $0 : $1 }
        }
        
        let sameModiefyIds =  Set(localIdItems.map {$0.key }).intersection(Set(remoteIdRecrds.map {$0.key}))
        _ = sameModiefyIds.map { idString in
           if let remote = remoteIdRecrds[idString],
              let local = localIdItems[idString] {
               if remote.1.timeIntervalSince(local.1) > 0 {
                   localIdItems.removeValue(forKey: idString)
               }
               else {
                   remoteIdRecrds.removeValue(forKey: idString)
               }
           }
            
        }
        
        
        //save to local
        _ = remoteIdRecrds.map {T.saveToLocal(record: $0.value.0)}
        
        //Upload to remote
        let uploadrecord = try await withThrowingTaskGroup(of: Void.self, body: { group in
            localIdItems
                .map {$0.value.0}
                .map { item in
                    group.addTask {
                        try await self.saveAndUpdate(item: item)
                    }
                }
        })
        print(uploadrecord);
        
    }
    
    
    func saveAndUpdate(item: iCloudSyncItem) async throws {
        
        var record = try? await self.db.record(for:item.recordId)
        if let record = record {
            item.update(to: record)
            try await self.db.save(record)
        }
        else {
            let record = item.generateRecord()
            try await self.db.save(record)
        }
        
    }
}
