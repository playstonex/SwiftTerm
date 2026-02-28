import CloudKit
import DataSync
import Foundation

extension RDSnippet: iCloudSyncItem {
    public var recordId: CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString)
    }

    public static func recordType() -> String {
        "RDSnippet"
    }

    public static func saveToLocal(record: CKRecord) {
        guard let recordName = UUID(uuidString: record.recordID.recordName) else { return }
        if (record["isDeleted"] as? Bool) == true {
            RayonStore.shared.snippetGroup.delete(recordName)
            return
        }

        var snippet = RDSnippet(With: record)
        snippet.lastModifiedDate = Date()
        RayonStore.shared.snippetGroup.insert(snippet)
    }

    public func update(to record: CKRecord) {
        record.setValue(id.uuidString, forKey: "id")
        record.setValue(name, forKey: "name")
        record.setValue(group, forKey: "group")
        record.setValue(code, forKey: "code")
        record.setValue(comment, forKey: "comment")
        record.setValue(lastModifiedDate, forKey: "lastModifiedDate")
        record.setValue(isDeleted, forKey: "isDeleted")

        if let data = try? JSONEncoder().encode(attachment),
           let attachmentString = String(data: data, encoding: .utf8)
        {
            record.setValue(attachmentString, forKey: "attachment")
        } else {
            record.setValue("{}", forKey: "attachment")
        }
    }

    public func generateRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType(), recordID: recordId)
        update(to: record)
        return record
    }

    public init(With record: CKRecord) {
        id = UUID(uuidString: record["id"] as? String ?? "") ?? UUID()
        name = record["name"] as? String ?? ""
        group = record["group"] as? String ?? ""
        code = record["code"] as? String ?? ""
        comment = record["comment"] as? String ?? ""
        lastModifiedDate = record["lastModifiedDate"] as? Date ?? Date()
        isDeleted = record["isDeleted"] as? Bool ?? false

        let attachmentString = record["attachment"] as? String ?? "{}"
        if let data = attachmentString.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        {
            attachment = decoded
        } else {
            attachment = [:]
        }
    }
}
