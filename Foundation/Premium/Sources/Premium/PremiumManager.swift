//
//  PremiumManager.swift
//  Premium
//
//  Created by Claude on 2026/2/15.
//

import Foundation
import RevenueCat
import Combine
import Keychain

/// Manages premium subscription status using RevenueCat
@MainActor
public class PremiumManager: ObservableObject {
    public static let shared = PremiumManager()

    // MARK: - Published Properties

    @Published public var isSubscribed: Bool = false
    @Published public var subscriptionExpirationDate: Date?
    @Published public var isActive: Bool = false
    @Published public var willRenew: Bool = false
    @Published public var productIdentifier: String = ""
    @Published public var packageType: String = ""

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private let entitlementID = "premium" // Configure this in RevenueCat dashboard

    private init() {
        setupListeners()
        // Load initial subscription status
        Task {
            await refreshSubscriptionStatus()
        }
    }

    // MARK: - Setup

    private func setupListeners() {
        // Note: RevenueCat 5.x uses delegate pattern for customer info updates
        // You can set up a delegate if needed, or rely on manual refresh
    }

    // MARK: - Customer Info Handling

    private func handleCustomerInfoUpdate(_ customerInfo: CustomerInfo) {
        let entitlement = customerInfo.entitlements[entitlementID]

        isSubscribed = entitlement?.isActive ?? false
        isActive = entitlement?.isActive ?? false
        willRenew = entitlement?.willRenew ?? false
        productIdentifier = entitlement?.productIdentifier ?? ""
        subscriptionExpirationDate = entitlement?.expirationDate
        packageType = entitlement?.periodType == .intro ? "Introductory" :
                      entitlement?.periodType == .trial ? "Trial" : "Standard"
    }

    // MARK: - Public Methods

    /// Refresh subscription status from RevenueCat
    public func refreshSubscriptionStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            handleCustomerInfoUpdate(customerInfo)
        } catch {
            print("Failed to fetch customer info: \(error)")
        }
    }

    /// Show paywall for subscription purchase
    public func showPaywall() {
        Task { @MainActor in
            await showPaywallSheet()
        }
    }

    private func showPaywallSheet() async {
        // RevenueCat's paywall will be presented
        // The actual presentation should be handled in SwiftUI views
        // using PaywallView or presenting the paywall
    }

    /// Purchase a package
    public func purchase(package: Package) async throws -> StoreTransaction? {
        let result = try await Purchases.shared.purchase(package: package)

        if result.customerInfo.entitlements[entitlementID]?.isActive == true {
            await refreshSubscriptionStatus()
            return result.transaction
        }

        return nil
    }

    /// Restore purchases
    public func restorePurchases() async throws {
        let customerInfo = try await Purchases.shared.restorePurchases()
        handleCustomerInfoUpdate(customerInfo)
    }

    /// Get available packages
    public func getAvailablePackages() async -> [Package] {
        do {
            let offerings = try await Purchases.shared.offerings()
            // Get the current offering (or first available)
            if let currentOffering = offerings.current {
                return currentOffering.availablePackages
            } else if let firstOffering = offerings.all.first?.value {
                return firstOffering.availablePackages
            }
        } catch {
            print("Failed to fetch offerings: \(error)")
        }
        return []
    }

    /// Check if user is eligible for free trial
    public func isEligibleForTrial(completion: @escaping (Bool) -> Void) {
        Purchases.shared.checkTrialOrIntroDiscountEligibility([self.productIdentifier]) { eligibility in
            let eligibilityStatus = eligibility[self.productIdentifier]
            let isEligible = eligibilityStatus?.status == .eligible
            completion(isEligible)
        }
    }

    /// Get subscription status description
    public var subscriptionStatusDescription: String {
        if !isSubscribed {
            return "Not Subscribed"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        if let expirationDate = subscriptionExpirationDate {
            if willRenew {
                return "Renews on \(formatter.string(from: expirationDate))"
            } else {
                return "Expires on \(formatter.string(from: expirationDate))"
            }
        }

        return "Active"
    }

    /// Get formatted expiration date
    public var formattedExpirationDate: String {
        guard let expirationDate = subscriptionExpirationDate else {
            return "N/A"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        return formatter.string(from: expirationDate)
    }

    // MARK: - Subscription Management

    /// Get URL to manage subscription
    public func getManageSubscriptionURL() -> URL? {
        // iOS Settings > Apple ID > Subscriptions
        // This should open the subscription management page
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            return url
        }
        return nil
    }
}

// MARK: - Subscription Status

public extension PremiumManager {
    enum SubscriptionStatus {
        case notSubscribed
        case subscribed(willRenew: Bool)
        case expired
        case inGracePeriod
        case inTrial

        var displayName: String {
            switch self {
            case .notSubscribed:
                return "Free"
            case .subscribed(let willRenew):
                return willRenew ? "Premium (Renewing)" : "Premium (Will Expire)"
            case .expired:
                return "Expired"
            case .inGracePeriod:
                return "Premium (Grace Period)"
            case .inTrial:
                return "Premium (Trial)"
            }
        }
    }

    var currentStatus: SubscriptionStatus {
        guard isSubscribed else {
            return .notSubscribed
        }

        // You may want to add more granular status checking here
        // based on RevenueCat's entitlement information
        if willRenew {
            return .subscribed(willRenew: true)
        } else if subscriptionExpirationDate != nil {
            return .subscribed(willRenew: false)
        }

        return .notSubscribed
    }
}
