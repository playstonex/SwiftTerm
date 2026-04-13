//
//  RDMachine.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/8.
//

import Foundation
import DataSync
import CloudKit


extension RDMachine : iCloudSyncItem {
    public func update(to record: CKRecord) {
        record.setValue(id.uuidString, forKey: "id")
        record.setValue(remoteAddress, forKey: "remoteAddress")
        record.setValue(remotePort, forKey: "remotePort")
        record.setValue(name, forKey: "name")
        record.setValue(group, forKey: "group")
        record.setValue(lastConnection, forKey: "lastConnection")
        record.setValue(lastBanner, forKey: "lastBanner")
        record.setValue(comment, forKey: "comment")
        record.setValue(associatedIdentity, forKey: "associatedIdentity")
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
    
    
    public static func saveToLocal(record: CKRecord) {
        let id = UUID(uuidString: record.recordID.recordName)
        var machine = RayonStore.shared.machineGroup.machines.first {id == $0.id}
        
        if var machine = machine {
            machine.remoteAddress = record["remoteAddress"] as? String ?? ""
            machine.remotePort = record["remotePort"] as? String ?? ""
            machine.name = record["name"] as? String ?? ""
            machine.group = record["group"] as? String ?? ""
            machine.lastConnection = record["lastConnection"] as? Date ?? Date()
            machine.lastBanner = record["lastBanner"] as? String ?? ""
            machine.comment = record["comment"] as? String ?? ""
            machine.associatedIdentity = record["associatedIdentity"] as? String ?? ""
            
            let attachmentString = record["attachment"] as? String ?? "{}"
            
            if  let data = attachmentString.data(using: String.Encoding.utf8),
                let newAttachment = try? JSONSerialization.jsonObject(with: data) as? [String:String] {
                machine.attachment = newAttachment
            }
            else {
                machine.attachment = [:]
            }
            
            machine.lastModifiedDate = record["lastModifiedDate"] as? Date ?? Date()
            machine.isDeleted = record["isDeleted"] as? Bool ?? false
        }
        else {
            machine = RDMachine(With: record)
        }
        if var machine = machine {
            machine.lastModifiedDate = Date()
            if Thread.isMainThread {
                RayonStore.shared.machineGroup.insert(machine)
            } else {
                DispatchQueue.main.async {
                    RayonStore.shared.machineGroup.insert(machine)
                }
            }
        }
        
        
    }
    
    public var recordId: CKRecord.ID {
        return CKRecord.ID(recordName: self.id.uuidString)
    }
    
    public init(With record: CKRecord) {
        self.id = UUID(uuidString: record["id"] as? String ?? "") ?? UUID()
        
        self.remoteAddress = record["remoteAddress"] as? String ?? ""
        self.remotePort = record["remotePort"] as? String ?? ""
        self.name = record["name"] as? String ?? ""
        self.group = record["group"] as? String ?? ""
        self.lastConnection = record["lastConnection"] as? Date ?? Date()
        self.lastBanner = record["lastBanner"] as? String ?? ""
        self.comment = record["comment"] as? String ?? ""
        self.associatedIdentity = record["associatedIdentity"] as? String ?? ""
        
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
        return "RDMachine"
    }
    
    public func generateRecord() -> CKRecord {
        
        let record = CKRecord(recordType: RDMachine.recordType(),
                              recordID: CKRecord.ID(recordName: self.id.uuidString))
        
        record.setValue(id.uuidString, forKey: "id")
        record.setValue(remoteAddress, forKey: "remoteAddress")
        record.setValue(remotePort, forKey: "remotePort")
        record.setValue(name, forKey: "name")
        record.setValue(group, forKey: "group")
        record.setValue(lastConnection, forKey: "lastConnection")
        record.setValue(lastBanner, forKey: "lastBanner")
        record.setValue(comment, forKey: "comment")
        record.setValue(associatedIdentity, forKey: "associatedIdentity")
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
        
        return record;
    }
}

public struct RDMachine: Codable, Identifiable, Equatable {
    public init(id: UUID = UUID(),
                remoteAddress: String = "",
                remotePort: String = "",
                name: String = "",
                group: String = "",
                lastConnection: Date = .init(),
                lastBanner: String = "",
                comment: String = "",
                associatedIdentity: String? = nil,
                attachment: [String: String] = [:],
                lastModifiedDate:Date = Date(),
                isDeleted:Bool = false )
    {
        self.id = id
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.name = name
        self.group = group
        self.lastConnection = lastConnection
        self.lastBanner = lastBanner
        self.comment = comment
        self.associatedIdentity = associatedIdentity
        self.attachment = attachment
        self.lastModifiedDate = lastModifiedDate
        self.isDeleted = isDeleted;
    }

    public var id = UUID()
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    // generic authenticate filed required for ssh
    public var remoteAddress: String
    public var remotePort: String

    // application required
    public var name: String
    public var group: String
    public var lastConnection: Date
    public var lastBanner: String
    public var comment: String
    public var associatedIdentity: String?

    // reserved for future use
    public var attachment: [String: String]
    
    public var lastModifiedDate: Date
    public var isDeleted: Bool

    public var fileTransferLoginPath: String {
        get {
            attachment["sftp.login.path", default: "/"]
        }
        set {
            attachment["sftp.login.path"] = newValue
        }
    }

    // convince

    public func isQualifiedForSearch(text: String) -> Bool {
        let searchText = text.lowercased()
        if remoteAddress.description.lowercased().contains(searchText) { return true }
        if remotePort.description.lowercased().contains(searchText) { return true }
        if name.description.lowercased().contains(searchText) { return true }
        if group.description.lowercased().contains(searchText) { return true }
        if lastBanner.description.lowercased().contains(searchText) { return true }
        if comment.description.lowercased().contains(searchText) { return true }
        return false
    }

    public func shortDescription(withComment: Bool = true) -> String {
        var build = name + " "
        if let aid = associatedIdentity,
           let uid = UUID(uuidString: aid)
        {
            let identity = RayonStore.shared.identityGroup[uid]
            if !identity.username.isEmpty {
                build += identity.username + "@"
            }
        }
        build += remoteAddress
        if remotePort != "22" {
            build += " -p " + remotePort
        }
        if withComment, !comment.isEmpty {
            build += " (" + comment + ")"
        }
        return build
    }

    public func isNotPlaceholder() -> Bool {
        remoteAddress.count > 0 && remotePort.count > 0
    }

    public func getCommand(insertLeadingSSH: Bool = true) -> String {
        var build = ""
        let leading = insertLeadingSSH ? "ssh " : ""
        if let id = associatedIdentity,
           let rid = UUID(uuidString: id)
        {
            let oid = RayonStore.shared.identityGroup[rid]
            if !oid.username.isEmpty {
                build = leading + "\(oid.username)@\(remoteAddress)"
            }
        }
        if build.isEmpty {
            build = leading + "\(remoteAddress)"
        }
        if remotePort != "22" {
            build += " -p " + remotePort
        }
        return build
    }
}
