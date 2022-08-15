//
//  File.swift
//  
//
//  Created by Lei Guo on 2022/8/14.
//

import Foundation
import CloudKit

public extension CKDatabase {
  /// Request `CKRecord`s that correspond to a Swift type.
  ///
  /// - Parameters:
  ///   - recordType: Its name has to be the same in your code, and in CloudKit.
  ///   - predicate: for the `CKQuery`
  ///
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func records<T:iCloudSyncItem>(  type _: T.Type, zoneID: CKRecordZone.ID? = nil, predicate: NSPredicate = .init(value: true)) async throws -> [CKRecord] {
        try await withThrowingTaskGroup(of: [CKRecord].self) { group in
            func process( _ records: ( matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor? ) ) async throws {
                group.addTask {
                    try records.matchResults.map { try $1.get() }
                }
                
                if let cursor = records.queryCursor {
                    try await process(self.records(continuingMatchFrom: cursor))
                }
            }
            
            try await process(
                records(
                    matching: .init(
                        recordType: T.recordType(),
                        predicate: predicate
                    ),
                    inZoneWith: zoneID
                )
            )
            
            return try await group.reduce(into: [], +=)
        }
    }
}
