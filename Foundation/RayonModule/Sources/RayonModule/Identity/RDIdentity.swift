//
//  RDIdentity.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/9.
//

import Foundation
import NSRemoteShell
import DataSync
import CloudKit

extension RDIdentity: iCloudSyncItem {
    
    
    public var recordId: CKRecord.ID {
        return CKRecord.ID(recordName:  self.id.uuidString)
    }
    
    
    public func update(to record:CKRecord) {
        record.setValue(id.uuidString, forKey: "id")
        record.setValue(username, forKey: "username")
        record.setValue(password, forKey: "password")
        record.setValue(privateKey, forKey: "privateKey")
        record.setValue(publicKey, forKey: "publicKey")
        record.setValue(lastRecentUsed, forKey: "lastRecentUsed")
        record.setValue(comment, forKey: "comment")
        record.setValue(group, forKey: "group")
        record.setValue(authenticAutomatically, forKey: "authenticAutomatically")
        record.setValue(lastModifiedDate, forKey: "lastModifiedDate")
        record.setValue(isDeleted, forKey: "isDeleted")
        
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(attachment) {
            let attachmentString =  String(data: data, encoding: String.Encoding.utf8)
            record.setValue(attachmentString, forKey: "attachment")
        }
        else {
            record.setValue("{}", forKey: "attachment")
        }
    }
    
    public init(With record: CKRecord) {
        self.id = UUID(uuidString: record["id"] as? String ?? "") ?? UUID()
        self.username = record["username"] as? String ?? ""
        self.password = record["password"] as? String ?? ""
        self.privateKey = record["privateKey"] as? String ?? ""
        self.publicKey = record["publicKey"] as? String ?? ""
        self.lastRecentUsed = record["lastRecentUsed"] as? Date ?? Date()
        self.comment = record["comment"] as? String ?? ""
        self.group = record["group"] as? String ?? ""
        self.authenticAutomatically = record["authenticAutomatically"] as? Bool ?? true
        
        let attachmentString = record["attachment"] as? String ?? "{}"
        
        if  let data = attachmentString.data(using: String.Encoding.utf8),
            let newAttachment = try? JSONSerialization.jsonObject(with: data) as? [String:String] {
            self.attachment = newAttachment
        }
        else {
            self.attachment = [:]
        }
        self.lastModifiedDate = record["lastModifiedDate"] as? Date ?? Date()
        self.isDeleted = record["isDeleted"] as? Bool ?? false
    }
    
    public static func recordType() -> String {
        return "RDIdentity"
    }
    
    public static func saveToLocal(record:CKRecord) {
        
        let id = UUID(uuidString: record.recordID.recordName)
        let identity = RayonStore.shared.identityGroup.identities.first {id == $0.id}
        if var idt = identity {
            idt.username = record["username"] as? String ?? ""
            idt.password = record["password"] as? String ?? ""
            idt.privateKey = record["privateKey"] as? String ?? ""
            idt.publicKey = record["publicKey"] as? String ?? ""
            idt.lastRecentUsed = record["lastRecentUsed"] as? Date ?? Date()
            idt.comment = record["comment"] as? String ?? ""
            idt.group = record["group"] as? String ?? ""
            idt.authenticAutomatically = record["authenticAutomatically"] as? Bool ?? true
            
            let attachmentString = record["attachment"] as? String ?? "{}"
            if  let data = attachmentString.data(using: String.Encoding.utf8),
                let newAttachment = try? JSONSerialization.jsonObject(with: data) as? [String:String] {
                idt.attachment = newAttachment
            }
            else {
                idt.attachment = [:]
            }
            idt.lastModifiedDate = Date()
            idt.isDeleted = record["isDeleted"] as? Bool ?? false
            
            RayonStore.shared.identityGroup.insert(idt)
        }
        else {
            var identify = RDIdentity(With: record)
            identify.lastModifiedDate = Date()
            RayonStore.shared.identityGroup.insert(identify)
        }
    }
    
    public func generateRecord() -> CKRecord {
        let record = CKRecord(recordType: RDIdentity.recordType(),
                              recordID:  CKRecord.ID(recordName: self.id.uuidString))
        record.setValue(id.uuidString, forKey: "id")
        record.setValue(username, forKey: "username")
        record.setValue(password, forKey: "password")
        record.setValue(privateKey, forKey: "privateKey")
        record.setValue(publicKey, forKey: "publicKey")
        record.setValue(lastRecentUsed, forKey: "lastRecentUsed")
        record.setValue(comment, forKey: "comment")
        record.setValue(group, forKey: "group")
        record.setValue(authenticAutomatically, forKey: "authenticAutomatically")
        record.setValue(lastModifiedDate, forKey: "lastModifiedDate")
        record.setValue(isDeleted, forKey: "isDeleted")
        
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(attachment) {
            let attachmentString =  String(data: data, encoding: String.Encoding.utf8)
            record.setValue(attachmentString, forKey: "attachment")
        }
        else {
            record.setValue("{}", forKey: "attachment")
        }
        
        return record
    }
}

public struct RDIdentity: Codable, Identifiable, Equatable {
    public init(
        id: UUID = .init(),
        username: String = "",
        password: String = "",
        privateKey: String = "",
        publicKey: String = "",
        lastRecentUsed: Date = .init(),
        comment: String = "",
        group: String = "",
        authenticAutomatically: Bool = true,
        attachment: [String: String] = [:],
        lastModifiedDate:Date = Date(),
        isDeleted:Bool = false
    ) {
        self.id = id
        self.username = username
        self.password = password
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.lastRecentUsed = lastRecentUsed
        self.comment = comment
        self.group = group
        self.authenticAutomatically = authenticAutomatically
        self.attachment = attachment
        self.lastModifiedDate = lastModifiedDate
        self.isDeleted = isDeleted;
    }

    public var id = UUID()

    // generic authenticate filed required for ssh
    public var username: String
    public var password: String
    public var privateKey: String
    public var publicKey: String

    // application required
    public var lastRecentUsed: Date
    public var comment: String
    public var group: String
    public var authenticAutomatically: Bool

    // reserved for future use
    public var attachment: [String: String]
    
    public var lastModifiedDate: Date
    public var isDeleted: Bool

    public func shortDescription() -> String {
        guard username.count > 0 else {
            return "Unknown Error"
        }
        var build = "User \(username) with \(getKeyType())"
        if group.count > 0 {
            build += " Group<\(group)>"
        }
        if comment.count > 0 {
            build += " (\(comment))"
        }
        return build
    }

    public func getKeyType() -> String {
        if privateKey.count > 0, publicKey.count > 0 {
            if password.count > 0 {
                return "Key Pair"
            } else {
                return "Plain Key Pair"
            }
        } else if privateKey.count > 0 {
            if password.count > 0 {
                return "Private Key"
            } else {
                return "Plain Private Key"
            }
        } else if publicKey.count > 0 {
            return "Unknown Key"
        } else if password.count > 0 {
            return "Password"
        } else {
            return "Username Only"
        }
    }

    public func callAuthenticationWith(remote: NSRemoteShell) {
        if remote.isAuthenticated { return }
        if privateKey.count > 0 || publicKey.count > 0 {
            remote.authenticate(with: username, andPublicKey: publicKey, andPrivateKey: privateKey, andPassword: password)
        } else {
            remote.authenticate(with: username, andPassword: password)
        }
        guard remote.isAuthenticated else {
            return
        }
        let date = Date()
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        fmt.timeStyle = .full
        debugPrint("Identity \(id) was used to authentic session at \(fmt.string(from: date))")
        mainActor {
            RayonStore.shared.identityGroup[id].lastRecentUsed = date
        }
    }
}
