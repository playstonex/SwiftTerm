//
//  SettingsDetailContent.swift
//  SettingsUI
//
//  Created for GoodTerm
//

#if canImport(AppKit)
import AppKit
#endif
import DataSync
import MachineStatus
import Premium
import RayonModule
import RevenueCat
import Speech
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Group (System Settings Style Card)
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            #if os(macOS)
            .background(.regularMaterial)
            #else
            .background(Color(UIColor.secondarySystemGroupedBackground))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Settings Row (Title + Control — System Settings Style)
struct SettingsIconRow<Content: View>: View {
    let icon: String // kept for API compatibility, not rendered on macOS
    let tint: Color // kept for API compatibility, not rendered on macOS
    let title: String
    let subtitle: String?
    @ViewBuilder let control: () -> Content

    init(icon: String, tint: Color = .blue, title: String, subtitle: String? = nil,
         @ViewBuilder control: @escaping () -> Content)
    {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.control = control
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Settings Divider (Inset from Card Edges)
struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 8)
    }
}

// MARK: - Settings Detail Content
public struct SettingsDetailContent: View {
    public let item: SettingsItem
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var store: RayonStore
    @ObservedObject var syncManager = AutoSyncManager.shared
    @ObservedObject var premium = PremiumManager.shared
    @ObservedObject private var automation = AutomationManager.shared

    @State private var snapshotReason: String = "manual"
    @State private var taskName: String = ""
    @State private var selectedSnippetId: UUID?
    @State private var selectedMachineIds: Set<UUID> = []
    @State private var scheduleKind: AutomationSchedule.Kind = .manual
    @State private var intervalMinutes: Int = 30
    @State private var dailyHour: Int = 2
    @State private var dailyMinute: Int = 0
    @State private var selectedMachineForMonitor: UUID?
    @State private var cpuThreshold: Double = Double(MonitorThresholdProfile.default.cpuPercent)
    @State private var memoryThreshold: Double = Double(MonitorThresholdProfile.default.memoryPercent)
    @State private var diskThreshold: Double = Double(MonitorThresholdProfile.default.diskPercent)
    @State private var showingThanks = false
    @State private var showingLicense = false
    @State private var availablePackages: [Package] = []
    @State private var isLoadingPackages = false
    @State private var isRestoringPurchases = false
    @State private var purchasingPackageID: String?
    @State private var restoreMessage: String?
    @State private var restoreMessageIsSuccess = false
    @State private var showingItermImporter = false
    @State private var customThemeVersion = 0

    #if os(iOS)
        @State private var exportDocument: ExportDocument?
        @State private var exportName: String = "monitor-report.csv"
        @State private var exportType: UTType = .commaSeparatedText
        @State private var showingExporter = false
    #endif

    private var snapshots: [SyncSnapshot] {
        store.listSyncSnapshots().sorted { $0.createdAt > $1.createdAt }
    }

    private var machines: [RDMachine] {
        store.machineGroup.machines.filter { $0.isNotPlaceholder() }.sorted { $0.name < $1.name }
    }

    private var snippets: [RDSnippet] {
        store.snippetGroup.snippets.sorted { $0.name < $1.name }
    }

    private var trendSamples: [MonitorTelemetrySample] {
        guard let machineId = selectedMachineForMonitor else { return [] }
        return MonitorTelemetryManager.shared.trend(for: machineId, within: 24)
    }

    public var body: some View {
        detailContentForItem
            .onAppear {
                if selectedSnippetId == nil { selectedSnippetId = snippets.first?.id }
                if selectedMachineForMonitor == nil {
                    selectedMachineForMonitor = machines.first?.id
                    loadThresholdForSelectedMachine()
                }
                Task {
                    await premium.refreshSubscriptionStatus()
                    await loadPackagesIfNeeded()
                }
            }
            .onChange(of: selectedMachineForMonitor) { _, _ in
                loadThresholdForSelectedMachine()
            }
            .sheet(isPresented: $showingThanks) {
                ThanksView()
                    #if os(macOS)
                    .frame(minWidth: 700, minHeight: 500)
                    #endif
            }
            .sheet(isPresented: $showingLicense) {
                LicenseView()
                    #if os(macOS)
                    .frame(minWidth: 700, minHeight: 500)
                    #endif
            }
            #if os(iOS)
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: exportType,
                defaultFilename: exportName
            ) { _ in
                exportDocument = nil
            }
            #endif
            .fileImporter(
                isPresented: $showingItermImporter,
                allowedContentTypes: [.xml],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        var theme = try TerminalTheme.fromItermColor(url: url)
                        // Avoid name collision with built-in themes
                        if TerminalTheme.builtInThemes.contains(where: { $0.name == theme.name }) {
                            theme = TerminalTheme(
                                name: "\(theme.name) (Custom)",
                                foreground: theme.foreground, background: theme.background,
                                cursor: theme.cursor,
                                black: theme.black, red: theme.red, green: theme.green,
                                yellow: theme.yellow, blue: theme.blue, magenta: theme.magenta,
                                cyan: theme.cyan, white: theme.white,
                                brightBlack: theme.brightBlack, brightRed: theme.brightRed,
                                brightGreen: theme.brightGreen, brightYellow: theme.brightYellow,
                                brightBlue: theme.brightBlue, brightMagenta: theme.brightMagenta,
                                brightCyan: theme.brightCyan, brightWhite: theme.brightWhite
                            )
                        }
                        TerminalTheme.addCustomTheme(theme)
                        store.terminalThemeName = theme.name
                        customThemeVersion += 1
                    } catch {
                        // Silently fail — the file was not a valid .itermcolors file
                    }
                case .failure:
                    break
                }
            }
    }

    @ViewBuilder
    private var detailContentForItem: some View {
        switch item {
        // About
        case .appInfo:
            appInfoView
        case .documents:
            documentsView

        // Appearance
        case .appTheme:
            appThemeView
        case .terminalTheme:
            terminalThemeView
        case .voiceSettings:
            voiceSettingsView
        case .effects:
            effectsView

        // Premium
        case .subscriptionStatus:
            subscriptionStatusPlaceholderView
        case .premiumFeatures:
            premiumFeaturesView

        // Sync & Automation
        case .cloudSync:
            cloudSyncView
        case .snapshots:
            snapshotsView
        case .automation:
            automationView
        case .monitoring:
            monitoringView

        // AI
        case .aiConfiguration:
            aiConfigurationView

        // Advanced
        case .applicationSettings:
            applicationSettingsView
        case .connectionSettings:
            connectionSettingsView
        case .fileTransferSettings:
            fileTransferSettingsView
        case .tmuxSettings:
            tmuxSettingsView
        }
    }

    // MARK: - About Views

    private var appInfoView: some View {
        SettingsGroup(title: L10n.tr("App")) {
            SettingsIconRow(icon: "app", tint: .blue, title: L10n.tr("Name")) {
                Text("GoodTerm")
                    .foregroundStyle(.secondary)
            }
            SettingsDivider()
            SettingsIconRow(icon: "info.circle", tint: .gray, title: L10n.tr("Version")) {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L10n.tr("Unknown"))
                    .foregroundStyle(.secondary)
            }
            SettingsDivider()
            SettingsIconRow(icon: "hammer", tint: .gray, title: L10n.tr("Build")) {
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? L10n.tr("Unknown"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var documentsView: some View {
        SettingsGroup(title: L10n.tr("Documents")) {
            SettingsIconRow(icon: "heart.fill", tint: .pink, title: L10n.tr("Thanks")) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture { showingThanks = true }

            SettingsDivider()

            SettingsIconRow(icon: "doc.text.fill", tint: .blue, title: L10n.tr("Software License")) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture { showingLicense = true }
        }
    }

    // MARK: - Appearance Views

    private var appThemeView: some View {
        SettingsGroup(title: L10n.tr("Appearance")) {
            SettingsIconRow(icon: "paintbrush.fill", tint: .pink, title: L10n.tr("Appearance")) {
                Picker(L10n.tr("Appearance"), selection: $store.themePreference) {
                    Text(L10n.tr("System")).tag("system")
                    Text(L10n.tr("Light")).tag("light")
                    Text(L10n.tr("Dark")).tag("dark")
                }
                .labelsHidden()
            }
        }
    }

    private var terminalThemeView: some View {
        SettingsGroup(title: L10n.tr("Terminal")) {
            SettingsIconRow(icon: "paintpalette", tint: .purple, title: L10n.tr("Terminal Theme")) {
                Picker(L10n.tr("Terminal Theme"), selection: $store.terminalThemeName) {
                    ForEach(TerminalTheme.allThemes, id: \.name) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                .id(customThemeVersion)
                .labelsHidden()
            }

            SettingsDivider()

            SettingsIconRow(icon: "square.and.arrow.down", tint: .blue, title: "Import iTerm2 Theme") {
                Button {
                    showingItermImporter = true
                } label: {
                    Image(systemName: "arrow.up.doc")
                }
                .buttonStyle(.plain)
            }

            if !TerminalTheme.customThemes.isEmpty {
                ForEach(TerminalTheme.customThemes, id: \.name) { theme in
                    SettingsDivider()
                    SettingsIconRow(icon: "trash", tint: .red, title: theme.name) {
                        Button {
                            TerminalTheme.removeCustomTheme(named: theme.name)
                            customThemeVersion += 1
                            if store.terminalThemeName == theme.name {
                                store.terminalThemeName = TerminalTheme.default.name
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            SettingsDivider()

            SettingsIconRow(icon: "textformat", tint: .orange, title: L10n.tr("Terminal Font")) {
                Picker(L10n.tr("Terminal Font"), selection: $store.terminalFontName) {
                    Text("Menlo").tag("Menlo")
                    Text("Monaco").tag("Monaco")
                    Text("SF Mono").tag("SF Mono")
                    Text("FiraCode Nerd Font Mono").tag("FiraCode Nerd Font Mono")
                    Text("Maple Mono NF CN").tag("Maple Mono NF CN")
                    Text("Cascadia Code NF").tag("Cascadia Code NF")
                    Text("Cascadia Mono NF").tag("Cascadia Mono NF")
                    Text("Hack Nerd Font Mono").tag("Hack Nerd Font Mono")
                    Text("Inconsolata Nerd Font Mono").tag("Inconsolata Nerd Font Mono")
                    Text("JetBrains Mono").tag("JetBrains Mono")
                    Text("Source Code Pro").tag("Source Code Pro")
                }
                .labelsHidden()
            }

            SettingsDivider()

            SettingsIconRow(icon: "textformat.size", tint: .indigo, title: L10n.tr("Terminal Font Size")) {
                HStack(spacing: 6) {
                    Text("\(store.terminalFontSize)")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Stepper("", value: $store.terminalFontSize, in: 5...30)
                        .labelsHidden()
                }
            }

            SettingsDivider()

            SettingsIconRow(icon: "return", tint: .green, title: L10n.tr("iOS Return Sends Line Feed")) {
                Toggle("", isOn: $store.terminalReturnKeySendsLineFeed)
                    .labelsHidden()
            }

            SettingsDivider()

            SettingsIconRow(icon: "bell.fill", tint: .red, title: L10n.tr("Command Notifications")) {
                Toggle("", isOn: $store.terminalCommandNotificationsEnabled)
                    .labelsHidden()
            }

            if store.terminalCommandNotificationsEnabled {
                SettingsDivider()
                SettingsIconRow(icon: "moon.fill", tint: .indigo, title: L10n.tr("Only When App Is Inactive")) {
                    Toggle("", isOn: $store.terminalCommandNotificationsOnlyWhenInactive)
                        .labelsHidden()
                }

                SettingsDivider()
                SettingsIconRow(icon: "clock", tint: .teal, title: L10n.tr("Notification Threshold")) {
                    HStack(spacing: 6) {
                        Text("\(store.terminalCommandNotificationMinimumDuration)s")
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                        Stepper("", value: $store.terminalCommandNotificationMinimumDuration, in: 1...3600)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private var effectsView: some View {
        SettingsGroup(title: L10n.tr("Effects")) {
            SettingsIconRow(icon: "sparkles", tint: .yellow, title: L10n.tr("Reduced Effect")) {
                Toggle("", isOn: $store.reducedViewEffects)
                    .labelsHidden()
            }
        }
    }

    private var voiceSettingsView: some View {
        SettingsGroup(title: L10n.tr("Voice Input")) {
            SettingsIconRow(icon: "waveform.badge.mic", tint: .green, title: L10n.tr("Engine")) {
                Picker(L10n.tr("Engine"), selection: $store.speechInputEngine) {
                    Text(L10n.tr("Apple (On-device/API)")).tag("apple")
                    Text(L10n.tr("Disabled")).tag("disabled")
                }
                .labelsHidden()
            }

            SettingsDivider()

            SettingsIconRow(icon: "globe", tint: .blue, title: L10n.tr("Language")) {
                Picker(L10n.tr("Language"), selection: $store.speechInputLocaleIdentifier) {
                    Text(L10n.tr("System Default")).tag("system")
                    ForEach(Self.supportedSpeechLocaleIdentifiers, id: \.self) { identifier in
                        Text(Self.displayName(for: identifier)).tag(identifier)
                    }
                }
                .labelsHidden()
                .disabled(store.speechInputEngine == "disabled")
            }
        }
    }

    // MARK: - Premium Views

    private var subscriptionStatusPlaceholderView: some View {
        Group {
            SettingsGroup(title: L10n.tr("Subscription Status")) {
                premiumStatusSummaryView

                if premium.isSubscribed {
                    SettingsDivider()
                    premiumSubscriptionDetailsView
                }
            }

            if !premium.isSubscribed {
                SettingsGroup(title: L10n.tr("Subscription Options")) {
                    subscriptionOptionsView
                }
            }

            SettingsGroup(title: L10n.tr("Legal")) {
                SettingsIconRow(icon: "doc.text.fill", tint: .blue, title: L10n.tr("Terms of Use")) {
                    Link(destination: SubscriptionLegalLinks.termsOfUseURL) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                }

                SettingsDivider()

                SettingsIconRow(icon: "hand.raised.fill", tint: .purple, title: L10n.tr("Privacy Policy")) {
                    Link(destination: SubscriptionLegalLinks.privacyPolicyURL) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                }
            }

            if !premium.isSubscribed {
                SettingsGroup(title: L10n.tr("Subscription Reminders")) {
                    subscriptionRemindersView
                }
            }

            SettingsGroup(title: L10n.tr("Subscription Actions")) {
                SettingsIconRow(icon: "arrow.clockwise", tint: .green, title: L10n.tr("Restore Purchases")) {
                    Button {
                        Task { await restorePurchases() }
                    } label: {
                        if isRestoringPurchases {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.tr("Restore"))
                        }
                    }
                    .disabled(isRestoringPurchases)
                }

                if let url = premium.getManageSubscriptionURL() {
                    SettingsDivider()
                    SettingsIconRow(icon: "link", tint: .blue, title: L10n.tr("Manage in App Store")) {
                        Button { openURL(url) } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(.plain)
                    }
                }

                SettingsDivider()

                SettingsIconRow(icon: "arrow.triangle.2.circlepath", tint: .orange, title: L10n.tr("Refresh Subscription Status")) {
                    Button {
                        Task {
                            restoreMessage = nil
                            restoreMessageIsSuccess = false
                            await premium.refreshSubscriptionStatus()
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.plain)
                }

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.caption)
                        .foregroundStyle(restoreMessageIsSuccess ? .green : .red)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var premiumStatusSummaryView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: premium.isSubscribed ? "crown.fill" : "crown")
                        .foregroundStyle(premium.isSubscribed ? .green : .orange)
                    Text(premium.isSubscribed ? L10n.tr("Premium Active") : L10n.tr("Free Plan"))
                        .font(.headline)
                }

                Text(
                    premium.isSubscribed
                        ? premium.subscriptionStatusDescription
                        : L10n.tr("Choose a subscription to unlock all premium features.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var subscriptionOptionsView: some View {
        if isLoadingPackages && availablePackages.isEmpty {
            HStack(spacing: 12) {
                ProgressView()
                Text(L10n.tr("Loading subscription options..."))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } else if availablePackages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("No subscription options available right now."))
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await loadPackages(force: true)
                    }
                } label: {
                    Label(L10n.tr("Reload Subscription Options"), systemImage: "arrow.clockwise")
                }
            }
            .padding(.vertical, 4)
        } else {
            VStack(spacing: 12) {
                ForEach(sortedPackages, id: \.identifier) { package in
                    subscriptionPackageCard(package)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var premiumSubscriptionDetailsView: some View {
        if premium.willRenew {
            premiumDetailRow(
                icon: "arrow.clockwise",
                tint: .green,
                title: L10n.tr("Auto-renewal Enabled"),
                value: L10n.tr("Your subscription will automatically renew")
            )
        }

        premiumDetailRow(
            icon: "calendar",
            tint: .blue,
            title: L10n.tr("Expires On"),
            value: premium.formattedExpirationDate
        )

        if !premium.productIdentifier.isEmpty {
            premiumDetailRow(
                icon: "tag",
                tint: .purple,
                title: L10n.tr("Plan"),
                value: premium.packageType
            )
        }
    }

    private var sortedPackages: [Package] {
        availablePackages.sorted { lhs, rhs in
            lhs.packageType.sortOrder < rhs.packageType.sortOrder
        }
    }

    private func subscriptionPackageCard(_ package: Package) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(package.packageType.displayName)
                            .font(.headline)

                        if package.packageType == .annual {
                            Text(L10n.tr("Best Value"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.16))
                                .foregroundStyle(.green)
                                .clipShape(.capsule)
                        }
                    }

                    if !package.storeProduct.localizedDescription.isEmpty {
                        Text(package.storeProduct.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(package.storeProduct.localizedPriceString)
                        .font(.title3.weight(.semibold))

                    Text(package.storeProduct.localizedTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            Button {
                Task {
                    await purchasePackage(package)
                }
            } label: {
                HStack {
                    Spacer()
                    if purchasingPackageID == package.identifier {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.tr("Processing..."))
                    } else {
                        Text(L10n.tr("Subscribe"))
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchasingPackageID != nil)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(package.packageType == .annual ? Color.green.opacity(0.45) : Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func premiumDetailRow(icon: String, tint: Color, title: String, value: String) -> some View {
        SettingsIconRow(icon: icon, tint: tint, title: title, subtitle: value) {
            EmptyView()
        }
    }

    private var premiumFeaturesView: some View {
        SettingsGroup(title: L10n.tr("Premium Features")) {
            FeatureRow(icon: "infinity", title: "Unlimited Connections", description: "Connect to unlimited number of servers")
            SettingsDivider()
            FeatureRow(icon: "bolt.fill", title: "Advanced Monitoring", description: "Real-time system status and alerts")
            SettingsDivider()
            FeatureRow(icon: "brain.head.profile", title: "AI Assistant", description: "Smart command suggestions and explanations")
            SettingsDivider()
            FeatureRow(icon: "folder.fill", title: "File Transfer", description: "Enhanced file transfer capabilities")
            SettingsDivider()
            FeatureRow(icon: "moon.fill", title: "Dark Mode Themes", description: "Premium terminal color schemes")
        }
    }

    private var subscriptionRemindersView: some View {
        VStack(alignment: .leading, spacing: 10) {
            subscriptionReminderText("kSubscriptionTip1")
            subscriptionReminderText("kSubscriptionTip2")
            subscriptionReminderText("kSubscriptionTip3")
            subscriptionReminderText("kSubscriptionTip4")
        }
        .padding(.vertical, 4)
    }

    private func subscriptionReminderText(_ key: String) -> some View {
        Text(L10n.tr(key))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sync & Automation Views

    private var cloudSyncView: some View {
        SettingsGroup(title: L10n.tr("Sync")) {
            SettingsIconRow(icon: "icloud", tint: .blue, title: L10n.tr("Sync Now"),
                            subtitle: L10n.tr("Last sync: %@", lastSyncDateString)) {
                Button {
                    Task { await performSync() }
                } label: {
                    if syncManager.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.counterclockwise.icloud")
                    }
                }
                .disabled(syncManager.isSyncing)
            }

            if let error = syncManager.syncError {
                SettingsDivider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(width: 26)
                    Text(L10n.tr("Error: %@", error.localizedDescription))
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
            }
        }
    }

    private var snapshotsView: some View {
        SettingsGroup(title: L10n.tr("Cloud Backup Snapshots")) {
            SettingsIconRow(icon: "camera.fill", tint: .blue, title: L10n.tr("Snapshot reason")) {
                HStack(spacing: 8) {
                    TextField("", text: $snapshotReason)
                        #if os(macOS)
                        .textFieldStyle(.plain)
                        #endif
                        .frame(width: 120)
                    Button(L10n.tr("Create")) {
                        guard premium.isSubscribed else { return }
                        let reason = snapshotReason.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.createSyncSnapshot(reason: reason.isEmpty ? "manual" : reason)
                    }
                    .disabled(!premium.isSubscribed)
                    .controlSize(.small)
                }
            }

            ForEach(Array(snapshots.prefix(8)), id: \.id) { snapshot in
                SettingsDivider()
                SettingsIconRow(icon: "clock.arrow.circlepath", tint: .teal, title: snapshot.reason) {
                    HStack(spacing: 8) {
                        Text(snapshot.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(L10n.tr("Rollback")) {
                            guard premium.isSubscribed else { return }
                            _ = store.rollbackSyncSnapshot(id: snapshot.id)
                        }
                        .disabled(!premium.isSubscribed)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var automationView: some View {
        Group {
            SettingsGroup(title: L10n.tr("Create Automation Task")) {
                SettingsIconRow(icon: "text.cursor", tint: .blue, title: L10n.tr("Task name")) {
                    TextField("", text: $taskName)
                        #if os(macOS)
                        .textFieldStyle(.plain)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                }

                SettingsDivider()

                SettingsIconRow(icon: "chevron.left.forwardslash.chevron.right", tint: .purple, title: L10n.tr("Snippet Template")) {
                    Picker(L10n.tr("Snippet Template"), selection: Binding<UUID>(
                        get: { selectedSnippetId ?? snippets.first?.id ?? UUID() },
                        set: { selectedSnippetId = $0 }
                    )) {
                        ForEach(snippets, id: \.id) { snippet in
                            Text(snippet.name.isEmpty ? snippet.id.uuidString : snippet.name).tag(snippet.id)
                        }
                    }
                    .labelsHidden()
                    .disabled(snippets.isEmpty)
                }

                SettingsDivider()

                SettingsIconRow(icon: "desktopcomputer", tint: .teal, title: L10n.tr("Target Machines")) {
                    EmptyView()
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(machines, id: \.id) { machine in
                        HStack {
                            Text(machine.name)
                            Spacer()
                            Toggle("", isOn: Binding<Bool>(
                                get: { selectedMachineIds.contains(machine.id) },
                                set: { enabled in
                                    if enabled { selectedMachineIds.insert(machine.id) }
                                    else { selectedMachineIds.remove(machine.id) }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }
                .padding(.leading, 50)

                SettingsDivider()

                SettingsIconRow(icon: "clock.badge", tint: .orange, title: L10n.tr("Schedule")) {
                    Picker(L10n.tr("Schedule"), selection: $scheduleKind) {
                        Text(L10n.tr("Manual")).tag(AutomationSchedule.Kind.manual)
                        Text(L10n.tr("Interval")).tag(AutomationSchedule.Kind.interval)
                        Text(L10n.tr("Daily")).tag(AutomationSchedule.Kind.daily)
                    }
                    #if os(macOS)
                    .pickerStyle(.segmented)
                    #endif
                    .labelsHidden()
                }

                if scheduleKind == .interval {
                    SettingsDivider()
                    SettingsIconRow(icon: "timer", tint: .indigo, title: L10n.tr("Every")) {
                        HStack(spacing: 8) {
                            Text("\(intervalMinutes)")
                                .foregroundStyle(.secondary)
                            Stepper("", value: $intervalMinutes, in: 5...1440, step: 5)
                                .labelsHidden()
                            Text(L10n.tr("minutes"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if scheduleKind == .daily {
                    SettingsDivider()
                    SettingsIconRow(icon: "sun.max", tint: .yellow, title: L10n.tr("Hour")) {
                        HStack(spacing: 6) {
                            Text("\(dailyHour)")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Stepper("", value: $dailyHour, in: 0...23)
                                .labelsHidden()
                        }
                    }
                    SettingsDivider()
                    SettingsIconRow(icon: "clock", tint: .cyan, title: L10n.tr("Minute")) {
                        HStack(spacing: 6) {
                            Text("\(dailyMinute)")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Stepper("", value: $dailyMinute, in: 0...59)
                                .labelsHidden()
                        }
                    }
                }

                SettingsDivider()

                HStack {
                    Spacer()
                    Button(L10n.tr("Create Task")) {
                        guard premium.isSubscribed else { return }
                        guard let snippetId = selectedSnippetId else { return }
                        guard !taskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        guard !selectedMachineIds.isEmpty else { return }

                        let schedule = AutomationSchedule(kind: scheduleKind, intervalMinutes: intervalMinutes, hour: dailyHour, minute: dailyMinute)
                        automation.upsertTask(
                            AutomationTask(name: taskName, snippetId: snippetId, machineIds: Array(selectedMachineIds), schedule: schedule)
                        )
                        taskName = ""
                    }
                    .disabled(!premium.isSubscribed || snippets.isEmpty || machines.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }

            SettingsGroup(title: L10n.tr("Tasks")) {
                ForEach(automation.tasks, id: \.id) { task in
                    SettingsIconRow(icon: "gearshape.2", tint: .purple, title: task.name) {
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding<Bool>(
                                get: { task.enabled },
                                set: { enabled in
                                    var updated = task
                                    updated.enabled = enabled
                                    automation.upsertTask(updated)
                                }
                            ))
                            .labelsHidden()
                            Button(L10n.tr("Run")) { Task { await automation.runNow(taskId: task.id) } }
                                .disabled(!premium.isSubscribed)
                                .controlSize(.small)
                            Button(L10n.tr("Delete")) { automation.removeTask(id: task.id) }
                                .disabled(!premium.isSubscribed)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var monitoringView: some View {
        SettingsGroup(title: L10n.tr("Monitoring Thresholds & Export")) {
            SettingsIconRow(icon: "desktopcomputer", tint: .blue, title: L10n.tr("Machine")) {
                Picker(L10n.tr("Machine"), selection: Binding<UUID>(
                    get: { selectedMachineForMonitor ?? machines.first?.id ?? UUID() },
                    set: { selectedMachineForMonitor = $0 }
                )) {
                    ForEach(machines, id: \.id) { machine in
                        Text(machine.name).tag(machine.id)
                    }
                }
                .labelsHidden()
                .disabled(machines.isEmpty)
            }

            SettingsDivider()

            SettingsIconRow(icon: "cpu", tint: .red, title: L10n.tr("CPU")) {
                Picker(L10n.tr("CPU"), selection: $cpuThreshold) {
                    Text("70%").tag(70.0); Text("75%").tag(75.0); Text("80%").tag(80.0)
                    Text("85%").tag(85.0); Text("90%").tag(90.0); Text("95%").tag(95.0)
                }
                .labelsHidden()
            }

            SettingsDivider()

            SettingsIconRow(icon: "memorychip", tint: .orange, title: L10n.tr("Memory")) {
                Picker(L10n.tr("Memory"), selection: $memoryThreshold) {
                    Text("70%").tag(70.0); Text("75%").tag(75.0); Text("80%").tag(80.0)
                    Text("85%").tag(85.0); Text("90%").tag(90.0); Text("95%").tag(95.0)
                }
                .labelsHidden()
            }

            SettingsDivider()

            SettingsIconRow(icon: "square.stack.3d.up.fill", tint: .teal, title: L10n.tr("Disk")) {
                Picker(L10n.tr("Disk"), selection: $diskThreshold) {
                    Text("70%").tag(70.0); Text("75%").tag(75.0); Text("80%").tag(80.0)
                    Text("85%").tag(85.0); Text("90%").tag(90.0); Text("95%").tag(95.0)
                }
                .labelsHidden()
            }

            SettingsDivider()

            HStack {
                Button(L10n.tr("Save Thresholds")) {
                    guard premium.isSubscribed, let machineId = selectedMachineForMonitor else { return }
                    MonitorTelemetryManager.shared.setThreshold(
                        machineId: machineId,
                        profile: .init(cpuPercent: Float(cpuThreshold), memoryPercent: Float(memoryThreshold), diskPercent: Float(diskThreshold))
                    )
                }
                .disabled(!premium.isSubscribed || selectedMachineForMonitor == nil)

                #if os(macOS)
                Button(L10n.tr("Export CSV")) { exportTrend(format: .csv) }
                    .disabled(!premium.isSubscribed || selectedMachineForMonitor == nil)
                    .controlSize(.small)
                Button(L10n.tr("Export JSON")) { exportTrend(format: .json) }
                    .disabled(!premium.isSubscribed || selectedMachineForMonitor == nil)
                    .controlSize(.small)
                #else
                Button(L10n.tr("Export CSV Report")) {
                    guard premium.isSubscribed, let machineId = selectedMachineForMonitor else { return }
                    let csv = MonitorTelemetryManager.shared.csv(for: machineId)
                    exportDocument = ExportDocument(data: Data(csv.utf8))
                    exportName = "monitor-report.csv"
                    exportType = .commaSeparatedText
                    showingExporter = true
                }
                .disabled(!premium.isSubscribed || selectedMachineForMonitor == nil)

                Button(L10n.tr("Export JSON Report")) {
                    guard premium.isSubscribed, let machineId = selectedMachineForMonitor else { return }
                    exportDocument = ExportDocument(data: MonitorTelemetryManager.shared.json(for: machineId))
                    exportName = "monitor-report.json"
                    exportType = .json
                    showingExporter = true
                }
                .disabled(!premium.isSubscribed || selectedMachineForMonitor == nil)
                #endif
            }

            if !trendSamples.isEmpty {
                let cpuAvg = trendSamples.map(\.cpuPercent).reduce(0, +) / Float(trendSamples.count)
                let memAvg = trendSamples.map(\.memoryPercent).reduce(0, +) / Float(trendSamples.count)
                let diskAvg = trendSamples.map(\.diskPercent).reduce(0, +) / Float(trendSamples.count)
                Text(L10n.tr("24h trends: %d points, avg CPU %d%%, avg Memory %d%%, avg Disk %d%%", trendSamples.count, Int(cpuAvg), Int(memAvg), Int(diskAvg)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - AI Views

    private var aiConfigurationView: some View {
        AIConfigurationContent()
    }

    private struct AIConfigurationContent: View {
        @ObservedObject private var aiAssistant = AIAssistant.shared
        @State private var isTesting = false
        @State private var testResult: AIAssistant.TestResult?

        var body: some View {
            Group {
                statusSection
                configurationSection
                featuresSection
            }
        }

        private var statusSection: some View {
            SettingsGroup(title: L10n.tr("Status")) {
                SettingsIconRow(icon: "brain.head.profile", tint: .purple, title: L10n.tr("Enable AI Assistant")) {
                    Toggle("", isOn: $aiAssistant.isEnabled)
                        .labelsHidden()
                }
            }
        }

        private var configurationSection: some View {
            SettingsGroup(title: L10n.tr("Configuration")) {
                SettingsIconRow(icon: "server.rack", tint: .blue, title: L10n.tr("AI Provider")) {
                    Picker(L10n.tr("AI Provider"), selection: $aiAssistant.provider) {
                        ForEach(AIAssistant.AIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                SettingsDivider()

                SettingsIconRow(icon: "key.fill", tint: .yellow, title: L10n.tr("API Key")) {
                    SecureField(L10n.tr("API Key"), text: $aiAssistant.apiKey)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 180)
                }

                SettingsDivider()

                SettingsIconRow(icon: "link", tint: .teal, title: L10n.tr("Custom Base URL (optional)")) {
                    TextField("", text: $aiAssistant.customBaseURL)
                        .disableAutocorrection(true)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 180)
                }

                SettingsDivider()

                SettingsIconRow(icon: "cpu", tint: .indigo, title: L10n.tr("Custom Model (optional)")) {
                    TextField("", text: $aiAssistant.customModel)
                        .disableAutocorrection(true)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 180)
                }

                SettingsDivider()

                HStack {
                    Spacer()
                    Button(action: {
                        Task { await testAPIConnection() }
                    }) {
                        HStack {
                            if isTesting {
                                ProgressView().controlSize(.small)
                                Text(L10n.tr("Testing..."))
                            } else {
                                Image(systemName: "checkmark.circle")
                                Text(L10n.tr("Test Connection"))
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || aiAssistant.apiKey.isEmpty)
                }

                if let result = testResult {
                    HStack(spacing: 12) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? .green : .red)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.message)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if let details = result.details {
                                Text(details)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background((result.success ? Color.green : Color.red).opacity(0.1))
                    .cornerRadius(8)
                }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Leave custom fields empty to use defaults."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(L10n.tr("Your API key is stored locally and never sent to our servers."))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        Text(L10n.tr("Get OpenAI API Key →"))
                            .font(.caption)
                    }
                }
            }
        }

        private var featuresSection: some View {
            SettingsGroup(title: L10n.tr("Features")) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.tr("Command explanation"), systemImage: "info.circle")
                    Label(L10n.tr("Smart suggestions"), systemImage: "lightbulb")
                    Label(L10n.tr("Error diagnosis"), systemImage: "stethoscope")
                    Label(L10n.tr("Natural language to command"), systemImage: "wand.and.stars")
                    Label(L10n.tr("Command history analysis"), systemImage: "chart.bar")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }

        private func testAPIConnection() async {
            isTesting = true
            testResult = nil

            let result = await aiAssistant.testConnection()

            DispatchQueue.main.async {
                self.testResult = result
                self.isTesting = false
            }
        }
    }

    // MARK: - Advanced Views

    private var applicationSettingsView: some View {
        SettingsGroup(title: L10n.tr("Application")) {
            SettingsIconRow(icon: "exclamationmark.shield.fill", tint: .orange, title: L10n.tr("Disable Confirmation")) {
                Toggle("", isOn: $store.disableConformation)
                    .labelsHidden()
            }

            SettingsDivider()

            SettingsIconRow(icon: "clock.arrow.circlepath", tint: .teal, title: L10n.tr("Record Recent")) {
                Toggle("", isOn: $store.storeRecent)
                    .labelsHidden()
            }

            #if os(iOS)
            SettingsDivider()
            SettingsIconRow(icon: "arrow.right.circle", tint: .green, title: L10n.tr("Open at Connect")) {
                Toggle("", isOn: $store.openInterfaceAutomatically)
                    .labelsHidden()
            }
            #endif
        }
    }

    private var connectionSettingsView: some View {
        SettingsGroup(title: L10n.tr("Connection")) {
            SettingsIconRow(icon: "clock.badge", tint: .red, title: L10n.tr("Timeout")) {
                Picker(L10n.tr("Timeout"), selection: $store.timeout) {
                    Text("2s").tag(2)
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("15s").tag(15)
                    Text("20s").tag(20)
                    Text("30s").tag(30)
                }
                .labelsHidden()
            }

            SettingsDivider()

            SettingsIconRow(icon: "chart.line.uptrend.xyaxis", tint: .purple, title: L10n.tr("Monitor interval")) {
                Picker(L10n.tr("Monitor interval"), selection: $store.monitorInterval) {
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("45s").tag(45)
                    Text("60s").tag(60)
                }
                .labelsHidden()
            }
        }
    }

    private var fileTransferSettingsView: some View {
        SettingsGroup(title: L10n.tr("File Transfer")) {
            SettingsIconRow(icon: "arrow.triangle.2.circlepath", tint: .yellow, title: L10n.tr("Conflict Policy")) {
                Picker(L10n.tr("Conflict Policy"), selection: $store.fileTransferConflictPolicy) {
                    Text(L10n.tr("Rename")).tag("rename")
                    Text(L10n.tr("Overwrite")).tag("overwrite")
                    Text(L10n.tr("Skip")).tag("skip")
                }
                .labelsHidden()
            }

            SettingsDivider()

            SettingsIconRow(icon: "arrow.up.arrow.down.circle", tint: .blue, title: L10n.tr("Max Concurrent Transfers")) {
                HStack(spacing: 6) {
                    Text("\(store.fileTransferMaxConcurrent)")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Stepper("", value: $store.fileTransferMaxConcurrent, in: 1...16)
                        .labelsHidden()
                }
            }

            SettingsDivider()

            SettingsIconRow(icon: "gauge.with.dots.needle.67percent", tint: .orange, title: L10n.tr("Rate Limit (KB/s)")) {
                HStack(spacing: 6) {
                    Text("\(store.fileTransferRateLimitKBps)")
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                    Stepper("", value: $store.fileTransferRateLimitKBps, in: 0...20000, step: 100)
                        .labelsHidden()
                }
            }

            SettingsDivider()

            SettingsIconRow(icon: "arrow.uturn.backward.circle", tint: .green, title: L10n.tr("Enable Resume for Failed Transfers")) {
                Toggle("", isOn: $store.fileTransferResumeEnabled)
                    .labelsHidden()
            }
        }
    }

    private var tmuxSettingsView: some View {
        SettingsGroup(title: L10n.tr("Tmux")) {
            SettingsIconRow(icon: "terminal.fill", tint: .green, title: L10n.tr("Use Tmux Session")) {
                Toggle("", isOn: $store.useTmux)
                    .labelsHidden()
            }

            if store.useTmux {
                SettingsDivider()
                SettingsIconRow(icon: "tag.fill", tint: .purple, title: L10n.tr("Tmux Session Name")) {
                    TextField("", text: $store.tmuxSessionName)
                        #if os(macOS)
                        .textFieldStyle(.plain)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }

                SettingsDivider()
                SettingsIconRow(icon: "plus.circle.fill", tint: .blue, title: L10n.tr("Auto-create Session")) {
                    Toggle("", isOn: $store.tmuxAutoCreate)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - Helper Methods

    private var lastSyncDateString: String {
        guard let date = syncManager.lastSyncDate else { return L10n.tr("Never") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func tappableTextRow(_ title: String, isDisabled: Bool = false, action: @escaping () -> Void) -> some View {
        HStack {
            Text(L10n.tr(title))
                .foregroundStyle(isDisabled ? .secondary : .primary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDisabled else { return }
            action()
        }
    }

    private func performSync() async {
        if #available(macOS 12.0, iOS 15.0, *) {
            await RayonStore.shared.syncAllDataToCloud(reason: "manual")
        }
    }

    private func loadThresholdForSelectedMachine() {
        guard let machineId = selectedMachineForMonitor else { return }
        let profile = MonitorTelemetryManager.shared.threshold(for: machineId)
        cpuThreshold = Double(profile.cpuPercent)
        memoryThreshold = Double(profile.memoryPercent)
        diskThreshold = Double(profile.diskPercent)
    }

    #if os(macOS)
        private enum ExportFormat { case csv, json }

        private func exportTrend(format: ExportFormat) {
            guard let machineId = selectedMachineForMonitor else { return }
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = format == .csv ? "monitor-report.csv" : "monitor-report.json"
            panel.allowedContentTypes = format == .csv ? [.commaSeparatedText] : [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                if format == .csv {
                    try MonitorTelemetryManager.shared.exportCSV(for: machineId, to: url)
                } else {
                    try MonitorTelemetryManager.shared.exportJSON(for: machineId, to: url)
                }
            } catch {
                #if os(macOS)
                // UIBridge is a Rayon app-specific utility
                // For SettingsUI module, we'll use Alert instead
                NSAlert(error: error).runModal()
                #else
                print("Export failed: \(error.localizedDescription)")
                #endif
            }
        }
    #endif
}

private enum SubscriptionLegalLinks {
    static let termsOfUseURL = URL(string: "https://goodterm.playstone.top/terms")!
    static let privacyPolicyURL = URL(string: "https://goodterm.playstone.top/privacy")!
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        SettingsIconRow(icon: icon, tint: .accentColor, title: title, subtitle: description) {
            EmptyView()
        }
    }
}

// MARK: - iOS Export Document
#if os(iOS)
    struct ExportDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.plainText, .json] }
        let data: Data

        init(data: Data) {
            self.data = data
        }

        init(configuration: ReadConfiguration) throws {
            self.data = configuration.file.regularFileContents ?? Data()
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }
#endif

// MARK: - Monitor Models
public struct MonitorThresholdProfile: Codable, Equatable {
    public var cpuPercent: Float
    public var memoryPercent: Float
    public var diskPercent: Float

    public static let `default` = MonitorThresholdProfile(cpuPercent: 85, memoryPercent: 90, diskPercent: 90)

    public init(cpuPercent: Float, memoryPercent: Float, diskPercent: Float) {
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.diskPercent = diskPercent
    }
}

extension SettingsDetailContent {
    private static var supportedSpeechLocaleIdentifiers: [String] {
        SFSpeechRecognizer
            .supportedLocales()
            .map(\.identifier)
            .sorted()
    }

    private static func displayName(for localeIdentifier: String) -> String {
        let name = Locale.current.localizedString(forIdentifier: localeIdentifier)
            ?? localeIdentifier
        return L10n.tr("%@ (%@)", name, localeIdentifier)
    }

    @MainActor
    private func restorePurchases() async {
        isRestoringPurchases = true
        restoreMessage = nil
        restoreMessageIsSuccess = false

        defer {
            isRestoringPurchases = false
        }

        do {
            try await premium.restorePurchases()
            restoreMessageIsSuccess = premium.isSubscribed
            restoreMessage = premium.isSubscribed
                ? L10n.tr("Success! Your purchases have been restored.")
                : L10n.tr("No active subscription was found for this Apple account.")
        } catch {
            restoreMessageIsSuccess = false
            restoreMessage = L10n.tr("Failed to restore purchases: %@", error.localizedDescription)
        }
    }

    @MainActor
    private func loadPackagesIfNeeded() async {
        guard availablePackages.isEmpty else { return }
        await loadPackages(force: false)
    }

    @MainActor
    private func loadPackages(force: Bool) async {
        guard force || !isLoadingPackages else { return }

        isLoadingPackages = true
        defer {
            isLoadingPackages = false
        }

        availablePackages = await premium.getAvailablePackages()
    }

    @MainActor
    private func purchasePackage(_ package: Package) async {
        purchasingPackageID = package.identifier
        restoreMessage = nil
        restoreMessageIsSuccess = false

        defer {
            purchasingPackageID = nil
        }

        do {
            _ = try await premium.purchase(package: package)
            await premium.refreshSubscriptionStatus()
            await loadPackages(force: true)
        } catch {
            restoreMessageIsSuccess = false
            restoreMessage = L10n.tr("Purchase failed: %@", error.localizedDescription)
        }
    }
}

private extension PackageType {
    var displayName: String {
        switch self {
        case .annual:
            return L10n.tr("Annual")
        case .monthly:
            return L10n.tr("Monthly")
        case .twoMonth:
            return L10n.tr("Two Months")
        case .threeMonth:
            return L10n.tr("Three Months")
        case .sixMonth:
            return L10n.tr("Six Months")
        case .weekly:
            return L10n.tr("Weekly")
        case .lifetime:
            return L10n.tr("Lifetime")
        default:
            return String(describing: self).capitalized
        }
    }

    var sortOrder: Int {
        switch self {
        case .monthly:
            return 0
        case .annual:
            return 1
        case .weekly:
            return 2
        case .twoMonth:
            return 3
        case .threeMonth:
            return 4
        case .sixMonth:
            return 5
        case .lifetime:
            return 6
        default:
            return 100
        }
    }
}

public struct MonitorTelemetrySample: Codable, Identifiable, Equatable {
    public let id: UUID
    public let machineId: UUID
    public let machineName: String
    public let timestamp: Date
    public let cpuPercent: Float
    public let memoryPercent: Float
    public let diskPercent: Float
    public let load1: Float

    public init(
        id: UUID = UUID(),
        machineId: UUID,
        machineName: String,
        timestamp: Date = Date(),
        cpuPercent: Float,
        memoryPercent: Float,
        diskPercent: Float,
        load1: Float
    ) {
        self.id = id
        self.machineId = machineId
        self.machineName = machineName
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.diskPercent = diskPercent
        self.load1 = load1
    }
}

public final class MonitorTelemetryManager {
    public static let shared = MonitorTelemetryManager()

    private let queue = DispatchQueue(label: "wiki.qaq.settingsui.monitor.telemetry", qos: .utility)
    private let sampleStoreKey = "wiki.qaq.settingsui.monitor.samples.v1"
    private let thresholdStoreKey = "wiki.qaq.settingsui.monitor.thresholds.v1"
    private let maxSamples = 5000

    private var samples: [MonitorTelemetrySample] = []
    private var thresholds: [UUID: MonitorThresholdProfile] = [:]

    private init() {
        load()
    }

    public func appendSample(machineId: UUID, machineName: String, status: ServerStatus) {
        let diskPercent = status.fileSystem.elements.map(\.percent).max() ?? 0
        let sample = MonitorTelemetrySample(
            machineId: machineId,
            machineName: machineName,
            cpuPercent: status.processor.summary.sumUsed,
            memoryPercent: status.memory.phyUsed * 100,
            diskPercent: diskPercent,
            load1: status.system.load1
        )

        queue.async {
            self.samples.append(sample)
            if self.samples.count > self.maxSamples {
                self.samples.removeFirst(self.samples.count - self.maxSamples)
            }
            self.persistSamples()
        }
    }

    public func setThreshold(machineId: UUID, profile: MonitorThresholdProfile) {
        queue.async {
            self.thresholds[machineId] = profile
            self.persistThresholds()
        }
    }

    public func threshold(for machineId: UUID) -> MonitorThresholdProfile {
        queue.sync { thresholds[machineId] ?? .default }
    }

    public func trend(for machineId: UUID, within hours: Int) -> [MonitorTelemetrySample] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return queue.sync { samples.filter { $0.machineId == machineId && $0.timestamp >= cutoff } }
    }

    func csv(for machineId: UUID) -> String {
        let rows = queue.sync {
            var lines = ["timestamp,machine,cpu_percent,memory_percent,disk_percent,load1"]
            let formatter = ISO8601DateFormatter()
            let selected = samples.filter { $0.machineId == machineId }.sorted { $0.timestamp < $1.timestamp }
            for item in selected {
                lines.append("\(formatter.string(from: item.timestamp)),\(item.machineName),\(item.cpuPercent),\(item.memoryPercent),\(item.diskPercent),\(item.load1)")
            }
            return lines
        }
        return rows.joined(separator: "\n")
    }

    func json(for machineId: UUID) -> Data {
        let selected = queue.sync { samples.filter { $0.machineId == machineId }.sorted { $0.timestamp < $1.timestamp } }
        return (try? JSONEncoder().encode(selected)) ?? Data()
    }

    #if os(macOS)
        func exportCSV(for machineId: UUID, to url: URL) throws {
            let csv = csv(for: machineId)
            try csv.write(to: url, atomically: true, encoding: .utf8)
        }

        func exportJSON(for machineId: UUID, to url: URL) throws {
            let data = json(for: machineId)
            try data.write(to: url)
        }
    #endif

    private func load() {
        if let data = UserDefaults.standard.data(forKey: sampleStoreKey),
           let decoded = try? JSONDecoder().decode([MonitorTelemetrySample].self, from: data) {
            samples = decoded
        }
        if let data = UserDefaults.standard.data(forKey: thresholdStoreKey),
           let decoded = try? JSONDecoder().decode([UUID: MonitorThresholdProfile].self, from: data) {
            thresholds = decoded
        }
    }

    private func persistSamples() {
        if let data = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(data, forKey: sampleStoreKey)
        }
    }

    private func persistThresholds() {
        if let data = try? JSONEncoder().encode(thresholds) {
            UserDefaults.standard.set(data, forKey: thresholdStoreKey)
        }
    }
}
