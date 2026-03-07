//
//  RDBrowserSession.swift
//
//
//  Created by Lakr Aream on 2022/3/10.
//

import Foundation

public struct RDBrowserSession: Codable, Identifiable, Equatable {
    public init(
        id: UUID = .init(),
        name: String = "",
        usingMachine: RDMachine.ID? = nil,
        remoteHost: String = "127.0.0.1",
        remotePort: Int = 3000,
        lastUrl: String? = nil,
        attachment: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.usingMachine = usingMachine
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.lastUrl = lastUrl
        self.attachment = attachment
    }

    public var id: UUID
    public var name: String
    public var usingMachine: RDMachine.ID?
    public var remoteHost: String
    public var remotePort: Int
    public var lastUrl: String?
    public var attachment: [String: String]

    public func isValid() -> Bool {
        guard !remoteHost.isEmpty,
              remotePort > 0, remotePort <= 65535,
              let machine = usingMachine,
              RayonStore.shared.machineGroup[machine].isNotPlaceholder()
        else {
            return false
        }
        return true
    }

    public func getMachineName() -> String? {
        guard let mid = usingMachine else {
            return nil
        }
        let machine = RayonStore.shared.machineGroup[mid]
        if machine.isNotPlaceholder() {
            return machine.name
        }
        return nil
    }

    public func shortDescription() -> String {
        guard isValid() else {
            return "Invalid Browser Session"
        }
        let machineName = getMachineName() ?? "Unknown"
        return "\(name.isEmpty ? "Browser" : name) - \(machineName):\(remotePort)"
    }

    public func fullUrlDescription() -> String {
        return "\(remoteHost):\(remotePort)"
    }
}
