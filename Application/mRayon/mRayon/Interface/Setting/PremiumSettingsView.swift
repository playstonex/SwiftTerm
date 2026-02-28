//
//  PremiumSettingsView.swift
//  mRayon
//
//  Created by Claude on 2026/2/15.
//

import Premium
import RevenueCat
import RevenueCatUI
import SwiftUI

struct PremiumSettingsView: View {
    @ObservedObject var premiumManager = PremiumManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var showingPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var showingManageSubscription = false

    var body: some View {
        Form {
            // Status Section
            Section {
                if premiumManager.isSubscribed {
                    subscribedStatusView
                } else {
                    notSubscribedView
                }
            } header: {
                Text("Premium Status")
            }

            // Subscription Details (if subscribed)
            if premiumManager.isSubscribed {
                Section {
                    subscriptionDetailsView
                } header: {
                    Text("Subscription Details")
                }
            }

            // Premium Features
            Section {
                premiumFeaturesView
            } header: {
                Text("Premium Features")
            } footer: {
                Text("Unlock all premium features to enhance your server management experience.")
            }

            // Manage Subscription
            if premiumManager.isSubscribed {
                Section {
                    manageSubscriptionView
                } header: {
                    Text("Manage Subscription")
                }
            }
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .onPurchaseCompleted { _ in
                    Task {
                        await premiumManager.refreshSubscriptionStatus()
                    }
                }
                .onPurchaseCancelled {
                    // User cancelled purchase
                }
        }
        .sheet(isPresented: $showingManageSubscription) {
            if let url = premiumManager.getManageSubscriptionURL() {
                #if os(iOS)
                SafariView(url: url)
                #endif
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
                    .font(.headline)
                    .foregroundColor(.green)

                Text(premiumManager.subscriptionStatusDescription)
                    .font(.caption)
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
                        .font(.headline)

                    Text("Upgrade to Premium for more features")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Button(action: {
                showingPaywall = true
            }) {
                Label("Upgrade to Premium", systemImage: "crown.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: {
                Task {
                    await restorePurchases()
                }
            }) {
                HStack {
                    if isRestoring {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Restoring...")
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("Restore Purchases")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isRestoring)

            if let message = restoreMessage {
                Text(message)
                    .font(.caption)
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
                    VStack(alignment: .leading) {
                        Text("Auto-renewal Enabled")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Your subscription will automatically renew")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }

            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text("Expires On")
                        .font(.subheadline)
                    Text(premiumManager.formattedExpirationDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if !premiumManager.productIdentifier.isEmpty {
                HStack {
                    Image(systemName: "tag")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading) {
                        Text("Plan")
                            .font(.subheadline)
                        Text(premiumManager.packageType)
                            .font(.caption)
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
        VStack(alignment: .leading, spacing: 8) {
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
                showingManageSubscription = true
            }) {
                HStack {
                    Image(systemName: "link")
                    Text("Manage Subscription in App Store")
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

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Safari View (for iOS)

#if os(iOS)
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}
#endif

// MARK: - Preview

struct PremiumSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PremiumSettingsView()
        }
        .onAppear {
            // Preview with mock data if needed
        }
    }
}
