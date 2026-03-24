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

    public var title: String {
        switch self {
        case .about: return L10n.tr("About")
        case .appearance: return L10n.tr("Appearance")
        case .premium: return L10n.tr("Premium")
        case .sync: return L10n.tr("Sync & Automation")
        case .ai: return L10n.tr("AI Assistant")
        case .advanced: return L10n.tr("Advanced")
        }
    }

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
            return [.appTheme, .terminalTheme, .voiceSettings, .effects]
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
    case voiceSettings = "Voice Input"
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

    public var title: String {
        switch self {
        case .appInfo: return L10n.tr("App Info")
        case .documents: return L10n.tr("Documents")
        case .appTheme: return L10n.tr("App Theme")
        case .terminalTheme: return L10n.tr("Terminal Theme")
        case .voiceSettings: return L10n.tr("Voice Input")
        case .effects: return L10n.tr("Effects")
        case .subscriptionStatus: return L10n.tr("Subscription Status")
        case .premiumFeatures: return L10n.tr("Premium Features")
        case .cloudSync: return L10n.tr("Cloud Sync")
        case .snapshots: return L10n.tr("Cloud Snapshots")
        case .automation: return L10n.tr("Automation Tasks")
        case .monitoring: return L10n.tr("Monitoring & Export")
        case .aiConfiguration: return L10n.tr("AI Configuration")
        case .applicationSettings: return L10n.tr("Application Settings")
        case .connectionSettings: return L10n.tr("Connection Settings")
        case .fileTransferSettings: return L10n.tr("File Transfer Settings")
        case .tmuxSettings: return L10n.tr("Tmux Settings")
        }
    }

    public var icon: String {
        switch self {
        case .appInfo: return "info.circle"
        case .documents: return "doc.text"
        case .appTheme: return "paintbrush"
        case .terminalTheme: return "terminal"
        case .voiceSettings: return "waveform.badge.mic"
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
        case .appInfo: return L10n.tr("Version and build information")
        case .documents: return L10n.tr("Thanks and license")
        case .appTheme: return L10n.tr("Appearance preferences")
        case .terminalTheme: return L10n.tr("Terminal appearance and font")
        case .voiceSettings: return L10n.tr("Speech input engine and language")
        case .effects: return L10n.tr("Visual effects settings")
        case .subscriptionStatus: return L10n.tr("Manage your subscription")
        case .premiumFeatures: return L10n.tr("View premium features")
        case .cloudSync: return L10n.tr("Sync with iCloud")
        case .snapshots: return L10n.tr("Backup snapshots")
        case .automation: return L10n.tr("Automated tasks")
        case .monitoring: return L10n.tr("Server monitoring thresholds")
        case .aiConfiguration: return L10n.tr("AI assistant settings")
        case .applicationSettings: return L10n.tr("General app settings")
        case .connectionSettings: return L10n.tr("Connection preferences")
        case .fileTransferSettings: return L10n.tr("File transfer options")
        case .tmuxSettings: return L10n.tr("Tmux session settings")
        }
    }
}
