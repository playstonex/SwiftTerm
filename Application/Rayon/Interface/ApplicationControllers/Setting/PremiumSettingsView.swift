//
//  PremiumSettingsView.swift
//  Rayon (macOS)
//
//  Created by Claude on 2026/2/15.
//

import Premium
import RevenueCat
import SwiftUI

struct PremiumSettingsView: View {
    @ObservedObject var premiumManager = PremiumManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var showingPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var availablePackages: [Package] = []
    @State private var isLoadingPackages = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Status Section
                Section {
                    if premiumManager.isSubscribed {
                        subscribedStatusView
                    } else {
                        notSubscribedView
                    }
                } header: {
                    Text("Premium Status")
                        .font(.system(.headline, design: .rounded))
                } footer: {
                    Divider()
                }

                // Subscription Details (if subscribed)
                if premiumManager.isSubscribed {
                    Section {
                        subscriptionDetailsView
                    } header: {
                        Text("Subscription Details")
                            .font(.system(.headline, design: .rounded))
                    } footer: {
                        Divider()
                    }
                }

                // Premium Features
                Section {
                    premiumFeaturesView
                } header: {
                    Text("Premium Features")
                        .font(.system(.headline, design: .rounded))
                } footer: {
                    Text("Unlock all premium features to enhance your server management experience.")
                        .font(.system(.subheadline, design: .rounded))
                    Divider()
                }

                // Manage Subscription
                if premiumManager.isSubscribed {
                    Section {
                        manageSubscriptionView
                    } header: {
                        Text("Manage Subscription")
                            .font(.system(.headline, design: .rounded))
                    } footer: {
                        Divider()
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Premium")
        .frame(minWidth: 550, idealWidth: 600, maxWidth: 700,
               minHeight: 500, idealHeight: 600, maxHeight: 700)
        .sheet(isPresented: $showingPaywall) {
            CustomPaywallView(
                packages: availablePackages,
                isLoading: isLoadingPackages,
                onPurchase: { package in
                    Task {
                        await purchasePackage(package)
                    }
                },
                onLoadPackages: {
                    Task {
                        await loadPackages()
                    }
                }
            )
            .frame(minWidth: 500, minHeight: 600)
        }
        .onAppear {
            Task {
                await loadPackages()
            }
        }
    }

    // MARK: - Subscribed Status View

    private var subscribedStatusView: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: "crown.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Premium Active")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.green)

                Text(premiumManager.subscriptionStatusDescription)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Not Subscribed View

    private var notSubscribedView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: "crown")
                        .foregroundColor(.orange)
                        .font(.title2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Free Plan")
                        .font(.system(.headline, design: .rounded))

                    Text("Upgrade to Premium for more features")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button(action: {
                    showingPaywall = true
                }) {
                    Label("Upgrade to Premium", systemImage: "crown.fill")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    Task {
                        await restorePurchases()
                    }
                }) {
                    if isRestoring {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Restoring...")
                                .font(.system(.subheadline, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Restore Purchases")
                                .font(.system(.headline, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRestoring)
            }

            if let message = restoreMessage {
                Text(message)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(message.contains("Success") ? .green : .red)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Subscription Details View

    private var subscriptionDetailsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if premiumManager.willRenew {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-renewal Enabled")
                            .font(.system(.headline, design: .rounded))
                        Text("Your subscription will automatically renew")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }

            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expires On")
                        .font(.system(.headline, design: .rounded))
                    Text(premiumManager.formattedExpirationDate)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if !premiumManager.productIdentifier.isEmpty {
                HStack {
                    Image(systemName: "tag")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Plan")
                            .font(.system(.headline, design: .rounded))
                        Text(premiumManager.packageType)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Premium Features View

    private var premiumFeaturesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureRow(
                icon: "infinity",
                title: "Unlimited Connections",
                description: "Connect to unlimited number of servers"
            )
            Divider()

            FeatureRow(
                icon: "bolt.fill",
                title: "Advanced Monitoring",
                description: "Real-time system status and alerts"
            )
            Divider()

            FeatureRow(
                icon: "brain.head.profile",
                title: "AI Assistant",
                description: "Smart command suggestions and explanations"
            )
            Divider()

            FeatureRow(
                icon: "folder.fill",
                title: "File Transfer",
                description: "Enhanced file transfer capabilities"
            )
            Divider()

            FeatureRow(
                icon: "moon.fill",
                title: "Dark Mode Themes",
                description: "Premium terminal color schemes"
            )
        }
    }

    // MARK: - Manage Subscription View

    private var manageSubscriptionView: some View {
        VStack(spacing: 12) {
            Button(action: {
                if let url = premiumManager.getManageSubscriptionURL() {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack {
                    Image(systemName: "link")
                    Text("Manage Subscription in App Store")
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
            }

            Button(action: {
                Task {
                    await premiumManager.refreshSubscriptionStatus()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Subscription Status")
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
            }
        }
    }

    // MARK: - Helper Methods

    private func restorePurchases() async {
        isRestoring = true
        restoreMessage = nil

        do {
            try await premiumManager.restorePurchases()
            restoreMessage = "Success! Your purchases have been restored."
        } catch {
            restoreMessage = "Failed to restore purchases: \(error.localizedDescription)"
        }

        isRestoring = false
    }

    private func loadPackages() async {
        isLoadingPackages = true
        availablePackages = await premiumManager.getAvailablePackages()
        isLoadingPackages = false
    }

    private func purchasePackage(_ package: Package) async {
        do {
            _ = try await premiumManager.purchase(package: package)
            await premiumManager.refreshSubscriptionStatus()
            showingPaywall = false
        } catch {
            print("Purchase failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded))

                Text(description)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Custom Paywall View for macOS

struct CustomPaywallView: View {
    let packages: [Package]
    let isLoading: Bool
    let onPurchase: (Package) -> Void
    let onLoadPackages: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var isPurchasing = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Upgrade to Premium")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    onLoadPackages()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading subscription options...")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if packages.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)

                    Text("No Subscription Options Available")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)

                    Text("Please check your internet connection and try again.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        onLoadPackages()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Features
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Premium Features")
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.bold)

                            FeatureRow(
                                icon: "infinity",
                                title: "Unlimited Connections",
                                description: "Connect to unlimited number of servers"
                            )
                            FeatureRow(
                                icon: "bolt.fill",
                                title: "Advanced Monitoring",
                                description: "Real-time system status and alerts"
                            )
                            FeatureRow(
                                icon: "brain.head.profile",
                                title: "AI Assistant",
                                description: "Smart command suggestions and explanations"
                            )
                            FeatureRow(
                                icon: "folder.fill",
                                title: "File Transfer",
                                description: "Enhanced file transfer capabilities"
                            )
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)

                        // Packages
                        Text("Choose Your Plan")
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)

                        ForEach(packages, id: \.identifier) { package in
                            PackageCard(
                                package: package,
                                onPurchase: {
                                    isPurchasing = true
                                    onPurchase(package)
                                }
                            )
                            .disabled(isPurchasing)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

// MARK: - Package Card Component

struct PackageCard: View {
    let package: Package
    let onPurchase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.storeProduct.localizedTitle)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.bold)

                    let description = package.storeProduct.localizedDescription
                    if !description.isEmpty {
                        Text(description)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(package.storeProduct.localizedPriceString)
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)

                    let packageType = package.packageType
                    Text(packageType.displayName)
                        .font(.system(.caption, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }
            }

            Button(action: onPurchase) {
                HStack {
                    Spacer()
                    Text("Subscribe")
                        .font(.system(.headline, design: .rounded))
                    if package.packageType == .annual {
                        Text("– Save 20%")
                            .font(.system(.subheadline, design: .rounded))
                            .opacity(0.8)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor, lineWidth: 2)
        )
    }
}

// MARK: - PackageType Extension

extension PackageType {
    var displayName: String {
        switch self {
        case .annual:
            return "Annual"
        case .monthly:
            return "Monthly"
        case .twoMonth:
            return "Two Months"
        case .threeMonth:
            return "Three Months"
        case .sixMonth:
            return "Six Months"
        case .weekly:
            return "Weekly"
        case .lifetime:
            return "Lifetime"
        default:
            return String(describing: self).capitalized
        }
    }
}

// MARK: - Preview

struct PremiumSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PremiumSettingsView()
    }
}
