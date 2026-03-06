//
//  RDMachine+Mosh.swift
//  RayonModule
//
//  Mosh connection support extension.
//

import Foundation

public extension RDMachine {

    /// Connection type for remote shell
    enum ConnectionType: String, Codable, Sendable {
        case ssh = "ssh"
        case mosh = "mosh"

        @MainActor var displayName: String {
            switch self {
            case .ssh: return "SSH"
            case .mosh: return "Mosh"
            }
        }

        var icon: String {
            switch self {
            case .ssh: return "network"
            case .mosh: return "antenna.radiowaves.left.and.right"
            }
        }
    }

    /// The connection type to use for this machine
    var connectionType: ConnectionType {
        get {
            guard let typeString = attachment["connection.type"],
                  let type = ConnectionType(rawValue: typeString) else {
                return .ssh
            }
            return type
        }
        set {
            attachment["connection.type"] = newValue.rawValue
        }
    }

    /// Mosh-specific prediction mode
    enum MoshPredictionMode: String, Codable, Sendable {
        case adaptive = "adaptive"
        case always = "always"
        case never = "never"
        case experimental = "experimental"

        var displayName: String {
            rawValue.capitalized
        }
    }

    /// Mosh prediction mode
    var moshPredictionMode: MoshPredictionMode {
        get {
            guard let modeString = attachment["mosh.prediction"],
                  let mode = MoshPredictionMode(rawValue: modeString) else {
                return .adaptive
            }
            return mode
        }
        set {
            attachment["mosh.prediction"] = newValue.rawValue
        }
    }

    /// Mosh port range (e.g., "60000-61000")
    var moshPortRange: String {
        get {
            attachment["mosh.port.range", default: "60000-61000"]
        }
        set {
            attachment["mosh.port.range"] = newValue
        }
    }

    /// Mosh server path on remote machine
    var moshServerPath: String {
        get {
            attachment["mosh.server.path", default: "mosh-server"]
        }
        set {
            attachment["mosh.server.path"] = newValue
        }
    }

    /// Whether to use Mosh for this connection
    var useMosh: Bool {
        connectionType == .mosh
    }

    /// Get connection display string with type indicator
    func connectionDisplayString() -> String {
        let typeIndicator: String
        switch connectionType {
        case .ssh:
            typeIndicator = ""
        case .mosh:
            typeIndicator = "[Mosh] "
        }
        return typeIndicator + shortDescription(withComment: false)
    }

    /// Get command string for the current connection type
    func getCommandForCurrentType() -> String {
        switch connectionType {
        case .ssh:
            return getCommand(insertLeadingSSH: true)
        case .mosh:
            return getMoshCommand()
        }
    }

    /// Get mosh command string
    func getMoshCommand() -> String {
        var build = "mosh"

        // Add port if not default
        if remotePort != "22" {
            build += " -p \(remotePort)"
        }

        // Add prediction mode if not default
        if moshPredictionMode != .adaptive {
            build += " --predict=\(moshPredictionMode.rawValue)"
        }

        // Add username if available
        if let aid = associatedIdentity,
           let uid = UUID(uuidString: aid) {
            let identity = RayonStore.shared.identityGroup[uid]
            if !identity.username.isEmpty {
                build += " \(identity.username)@"
            }
        }

        build += remoteAddress
        return build
    }
}

// MARK: - Mosh Configuration Extensions

public extension RDMachine {
    /// Check if server supports Mosh
    var supportsMosh: Bool {
        // This would be determined by attempting to connect or by cached capability
        attachment["mosh.supported"] == "true"
    }

    /// Set Mosh support capability
    mutating func setMoshSupport(_ supported: Bool) {
        attachment["mosh.supported"] = supported ? "true" : "false"
    }
}
