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
public final class PremiumManager: NSObject, ObservableObject {
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

    private override init() {
        super.init()
        setupListeners()
        // Load initial subscription status
        Task {
            await refreshSubscriptionStatus()
        }
    }

    // MARK: - Setup

    private func setupListeners() {
        Purchases.shared.delegate = self
    }

    // MARK: - Customer Info Handling

    private func handleCustomerInfoUpdate(_ customerInfo: CustomerInfo) {
        let matchedEntitlement =
            customerInfo.entitlements[entitlementID]
            ?? customerInfo.entitlements.active[entitlementID]
            ?? customerInfo.entitlements.activeInAnyEnvironment[entitlementID]
            ?? customerInfo.entitlements.active.values.first
            ?? customerInfo.entitlements.activeInAnyEnvironment.values.first

        let fallbackProductIdentifier = customerInfo.activeSubscriptions.sorted().first
            ?? customerInfo.allPurchasedProductIdentifiers.sorted().first
        let fallbackSubscription = fallbackProductIdentifier.flatMap {
            customerInfo.subscriptionsByProductIdentifier[$0]
        }

        let resolvedIsActive = matchedEntitlement?.isActive
            ?? !customerInfo.activeSubscriptions.isEmpty
        let resolvedProductIdentifier = matchedEntitlement?.productIdentifier
            ?? fallbackProductIdentifier
            ?? ""
        let resolvedExpirationDate = matchedEntitlement?.expirationDate
            ?? fallbackSubscription?.expiresDate
            ?? customerInfo.latestExpirationDate
        let resolvedWillRenew = matchedEntitlement?.willRenew
            ?? fallbackSubscription?.willRenew
            ?? false
        let resolvedPeriodType = matchedEntitlement?.periodType
            ?? fallbackSubscription?.periodType

        isSubscribed = resolvedIsActive
        isActive = resolvedIsActive
        willRenew = resolvedWillRenew
        productIdentifier = resolvedProductIdentifier
        subscriptionExpirationDate = resolvedExpirationDate
        packageType = packageTypeDescription(for: resolvedPeriodType)
    }

    private func packageTypeDescription(for periodType: PeriodType?) -> String {
        switch periodType {
        case .some(.intro):
            return "Introductory"
        case .some(.trial):
            return "Trial"
        case .some(.normal):
            return "Standard"
        case .some(.prepaid):
            return "Prepaid"
        case .none:
            return ""
        @unknown default:
            return "Standard"
        }
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

        handleCustomerInfoUpdate(result.customerInfo)

        if isSubscribed {
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

            var packagesByIdentifier: [String: Package] = [:]
            var orderedIdentifiers: [String] = []

            func appendPackages(from packages: [Package]) {
                for package in packages where packagesByIdentifier[package.identifier] == nil {
                    packagesByIdentifier[package.identifier] = package
                    orderedIdentifiers.append(package.identifier)
                }
            }

            if let currentOffering = offerings.current {
                appendPackages(from: currentOffering.availablePackages)
            }

            for offering in offerings.all.values {
                appendPackages(from: offering.availablePackages)
            }

            return orderedIdentifiers.compactMap { packagesByIdentifier[$0] }
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

extension PremiumManager: PurchasesDelegate {
    nonisolated public func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            PremiumManager.shared.handleCustomerInfoUpdate(customerInfo)
        }
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
