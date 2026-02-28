//
//  SettingsCategory.swift
//  SettingsUI
//
//  Created for GoodTerm
//

import Foundation
import SwiftUI

// MARK: - Settings Category
public enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case about = "About"
    case appearance = "Appearance"
    case premium = "Premium"
    case sync = "Sync & Automation"
    case ai = "AI Assistant"
    case advanced = "Advanced"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .about: return "info.circle"
        case .appearance: return "paintpalette"
        case .premium: return "crown"
        case .sync: return "arrow.triangle.2.circlepath.icloud"
        case .ai: return "brain.head.profile"
        case .advanced: return "slider.horizontal.3"
        }
    }

    // Items within each category
    public var items: [SettingsItem] {
        switch self {
        case .about:
            return [.appInfo, .documents]
        case .appearance:
            return [.appTheme, .terminalTheme, .effects]
        case .premium:
            return [.subscriptionStatus, .premiumFeatures]
        case .sync:
            return [.cloudSync, .snapshots, .automation, .monitoring]
        case .ai:
            return [.aiConfiguration]
        case .advanced:
            return [.applicationSettings, .connectionSettings, .fileTransferSettings, .tmuxSettings]
        }
    }
}

// MARK: - Settings Item
public enum SettingsItem: String, CaseIterable, Identifiable, Hashable, Codable {
    // About
    case appInfo = "App Info"
    case documents = "Documents"

    // Appearance
    case appTheme = "App Theme"
    case terminalTheme = "Terminal Theme"
    case effects = "Effects"

    // Premium
    case subscriptionStatus = "Subscription Status"
    case premiumFeatures = "Premium Features"

    // Sync & Automation
    case cloudSync = "Cloud Sync"
    case snapshots = "Cloud Snapshots"
    case automation = "Automation Tasks"
    case monitoring = "Monitoring & Export"

    // AI Assistant
    case aiConfiguration = "AI Configuration"

    // Advanced
    case applicationSettings = "Application Settings"
    case connectionSettings = "Connection Settings"
    case fileTransferSettings = "File Transfer Settings"
    case tmuxSettings = "Tmux Settings"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .appInfo: return "info.circle"
        case .documents: return "doc.text"
        case .appTheme: return "paintbrush"
        case .terminalTheme: return "terminal"
        case .effects: return "sparkles"
        case .subscriptionStatus: return "crown.fill"
        case .premiumFeatures: return "star.fill"
        case .cloudSync: return "icloud"
        case .snapshots: return "clock.arrow.circlepath"
        case .automation: return "gearshape.2"
        case .monitoring: return "chart.line.uptrend.xyaxis"
        case .aiConfiguration: return "brain.head.profile"
        case .applicationSettings: return "app"
        case .connectionSettings: return "network"
        case .fileTransferSettings: return "arrow.up.arrow.down"
        case .tmuxSettings: return "terminal.fill"
        }
    }

    public var description: String? {
        switch self {
        case .appInfo: return "Version and build information"
        case .documents: return "Thanks and license"
        case .appTheme: return "Appearance preferences"
        case .terminalTheme: return "Terminal appearance and font"
        case .effects: return "Visual effects settings"
        case .subscriptionStatus: return "Manage your subscription"
        case .premiumFeatures: return "View premium features"
        case .cloudSync: return "Sync with iCloud"
        case .snapshots: return "Backup snapshots"
        case .automation: return "Automated tasks"
        case .monitoring: return "Server monitoring thresholds"
        case .aiConfiguration: return "AI assistant settings"
        case .applicationSettings: return "General app settings"
        case .connectionSettings: return "Connection preferences"
        case .fileTransferSettings: return "File transfer options"
        case .tmuxSettings: return "Tmux session settings"
        }
    }
}
