import Combine
import Foundation
import os
import RevenueCat

struct SubscriptionState: Equatable {
    var tier: SubscriptionTier
    var entitlementID: String?
    var source: String
    var updatedAt: Date?
    var errorMessage: String?

    var isPro: Bool { tier == .pro }

    static let free = SubscriptionState(
        tier: .free,
        entitlementID: nil,
        source: "revenuecat",
        updatedAt: nil,
        errorMessage: nil
    )
}

struct SubscriptionPlanPackage: Identifiable, Equatable {
    let id: String
    let tier: SubscriptionTier
    let title: String
    let price: String
    let monthlyEquivalentPrice: String?
    let subtitle: String
    let productIdentifier: String
}

private enum SubscriptionManagerError: LocalizedError {
    case noPackagesConfigured
    case restoredPurchaseBelongsToAnotherAccount

    var errorDescription: String? {
        switch self {
        case .noPackagesConfigured:
            return "Abonelik paketleri RevenueCat tarafında bulunamadı."
        case .restoredPurchaseBelongsToAnotherAccount:
            return "Geri yüklenen abonelik başka bir hesapla ilişkili görünüyor."
        }
    }
}

@MainActor
protocol SubscriptionManaging: AnyObject {
    var state: SubscriptionState { get }
    var statePublisher: AnyPublisher<SubscriptionState, Never> { get }
    var packages: [SubscriptionPlanPackage] { get }
    var packagesPublisher: AnyPublisher<[SubscriptionPlanPackage], Never> { get }

    func configure()
    func identify(userID: UUID?) async
    func loadOfferings() async
    func purchase(packageID: String) async throws
    func refreshCustomerInfo() async
    @discardableResult
    func restorePurchases() async throws -> SubscriptionState
}

@MainActor
final class RevenueCatSubscriptionManager: NSObject, ObservableObject, SubscriptionManaging {
    static let shared = RevenueCatSubscriptionManager()
    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "RevenueCat")

    @Published private(set) var state: SubscriptionState = .free
    @Published private(set) var packages: [SubscriptionPlanPackage] = []

    var statePublisher: AnyPublisher<SubscriptionState, Never> {
        $state.eraseToAnyPublisher()
    }

    var packagesPublisher: AnyPublisher<[SubscriptionPlanPackage], Never> {
        $packages.eraseToAnyPublisher()
    }

    private var isConfigured = false
    private var packageByID: [String: Package] = [:]
    private var currentAppUserID: String?

    private override init() {
        super.init()
    }

    #if DEBUG
    private static func writeDiagnostics(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(timestamp) \(line)\n"
        guard let data = entry.data(using: .utf8),
              let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        let fileURL = cachesURL.appendingPathComponent("revenuecat-diagnostics.log")
        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    #endif

    func configure() {
        guard !isConfigured else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: RDConfig.Subscription.revenueCatAPIKey)
        Purchases.shared.delegate = self
        isConfigured = true
    }

    func identify(userID: UUID?) async {
        configure()

        guard let userID else {
            currentAppUserID = nil
            state = .free
            return
        }

        do {
            let appUserID = userID.uuidString.lowercased()
            currentAppUserID = appUserID
            let result = try await Purchases.shared.logIn(appUserID)
            apply(result.customerInfo)
        } catch {
            apply(error: error)
        }
    }

    func loadOfferings() async {
        configure()

        do {
            #if DEBUG
            Self.writeDiagnostics("RD_REVENUECAT_LOAD_OFFERINGS_START")
            #endif
            let offerings = try await Purchases.shared.offerings()
            let currentPackages = offerings.current?.availablePackages ?? []
            let allPackages = currentPackages.isEmpty
                ? offerings.all.values.flatMap(\.availablePackages)
                : currentPackages
            var mappedPackages: [SubscriptionPlanPackage] = []
            var rawByID: [String: Package] = [:]

            for package in allPackages {
                guard let tier = Self.tier(for: package) else { continue }
                let id = package.identifier + "::" + package.storeProduct.productIdentifier
                rawByID[id] = package
                mappedPackages.append(
                    SubscriptionPlanPackage(
                        id: id,
                        tier: tier,
                        title: tier.title,
                        price: package.localizedPriceString,
                        monthlyEquivalentPrice: package.storeProduct.localizedPricePerMonth,
                        subtitle: Self.subtitle(for: package),
                        productIdentifier: package.storeProduct.productIdentifier
                    )
                )

                Self.logger.info(
                    """
                    RevenueCat package loaded \
                    id=\(package.identifier, privacy: .public) \
                    product=\(package.storeProduct.productIdentifier, privacy: .public) \
                    tier=\(tier.rawValue, privacy: .public) \
                    type=\(String(describing: package.packageType), privacy: .public) \
                    price=\(package.localizedPriceString, privacy: .public) \
                    monthly=\((package.storeProduct.localizedPricePerMonth ?? "nil"), privacy: .public)
                    """
                )
                #if DEBUG
                let diagnosticLine = "RD_REVENUECAT_PACKAGE id=\(package.identifier) product=\(package.storeProduct.productIdentifier) tier=\(tier.rawValue) type=\(String(describing: package.packageType)) price=\(package.localizedPriceString) monthly=\(package.storeProduct.localizedPricePerMonth ?? "nil")"
                print(diagnosticLine)
                Self.writeDiagnostics(diagnosticLine)
                #endif
            }

            packageByID = rawByID
            packages = mappedPackages.sorted {
                if $0.tier.rank == $1.tier.rank { return $0.price < $1.price }
                return $0.tier.rank < $1.tier.rank
            }

            if packages.isEmpty {
                Self.logger.error("RevenueCat offerings loaded but no app packages were mapped.")
                #if DEBUG
                Self.writeDiagnostics("RD_REVENUECAT_NO_MAPPED_PACKAGES")
                #endif
                apply(error: SubscriptionManagerError.noPackagesConfigured)
            } else {
                Self.logger.info("RevenueCat mapped \(self.packages.count, privacy: .public) subscription packages.")
                #if DEBUG
                Self.writeDiagnostics("RD_REVENUECAT_MAPPED_COUNT \(self.packages.count)")
                #endif
                state = SubscriptionState(
                    tier: state.tier,
                    entitlementID: state.entitlementID,
                    source: state.source,
                    updatedAt: state.updatedAt,
                    errorMessage: nil
                )
            }
        } catch {
            Self.logger.error("RevenueCat offerings load failed: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            Self.writeDiagnostics("RD_REVENUECAT_LOAD_ERROR \(error.localizedDescription)")
            #endif
            apply(error: error)
        }
    }

    func purchase(packageID: String) async throws {
        configure()
        if packageByID[packageID] == nil {
            await loadOfferings()
        }
        guard let package = packageByID[packageID] else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Seçilen abonelik paketi bulunamadı."]
            )
        }
        let result = try await Purchases.shared.purchase(package: package)
        guard !result.userCancelled else { throw CancellationError() }
        apply(result.customerInfo)
    }

    func refreshCustomerInfo() async {
        configure()

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            apply(customerInfo)
        } catch {
            apply(error: error)
        }
    }

    @discardableResult
    func restorePurchases() async throws -> SubscriptionState {
        configure()
        let customerInfo = try await Purchases.shared.restorePurchases()
        let restoredState = Self.state(from: customerInfo)
        if restoredState.tier.isPaid,
           let currentAppUserID,
           customerInfo.originalAppUserId.lowercased() != currentAppUserID {
            let error = SubscriptionManagerError.restoredPurchaseBelongsToAnotherAccount
            state = SubscriptionState(
                tier: .free,
                entitlementID: nil,
                source: "revenuecat",
                updatedAt: Date(),
                errorMessage: error.localizedDescription
            )
            throw error
        }
        return apply(customerInfo)
    }

    @discardableResult
    private func apply(_ customerInfo: CustomerInfo) -> SubscriptionState {
        let nextState = Self.state(from: customerInfo)
        state = nextState
        return nextState
    }

    private static func state(from customerInfo: CustomerInfo) -> SubscriptionState {
        if let productTier = tier(fromActiveSubscriptionsIn: customerInfo) {
            return SubscriptionState(
                tier: productTier,
                entitlementID: productTier.isPaid ? productTier.rawValue : nil,
                source: "revenuecat",
                updatedAt: Date(),
                errorMessage: nil
            )
        }

        let tier: SubscriptionTier
        let entitlementID: String?
        if customerInfo.entitlements[RDConfig.Subscription.proEntitlementID]?.isActive == true {
            tier = .pro
            entitlementID = RDConfig.Subscription.proEntitlementID
        } else if customerInfo.entitlements[RDConfig.Subscription.plusEntitlementID]?.isActive == true {
            tier = .plus
            entitlementID = RDConfig.Subscription.plusEntitlementID
        } else {
            tier = .free
            entitlementID = nil
        }

        return SubscriptionState(
            tier: tier,
            entitlementID: entitlementID,
            source: "revenuecat",
            updatedAt: Date(),
            errorMessage: nil
        )
    }

    private static func tier(fromActiveSubscriptionsIn customerInfo: CustomerInfo) -> SubscriptionTier? {
        customerInfo.activeSubscriptions
            .compactMap { productIdentifier -> (tier: SubscriptionTier, purchasedAt: Date)? in
                guard let tier = tier(fromProductIdentifier: productIdentifier) else { return nil }
                return (
                    tier: tier,
                    purchasedAt: customerInfo.purchaseDate(forProductIdentifier: productIdentifier) ?? .distantPast
                )
            }
            .sorted {
                if $0.purchasedAt == $1.purchasedAt {
                    return $0.tier.rank > $1.tier.rank
                }
                return $0.purchasedAt > $1.purchasedAt
            }
            .first?
            .tier
    }

    private static func tier(fromProductIdentifier productIdentifier: String) -> SubscriptionTier? {
        let token = productIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch token {
        case "riskdetected_plus_monthly", "riskdetected_plus_yearly":
            return .plus
        case "riskdetected_pro_monthly", "riskdetected_pro_yearly":
            return .pro
        default:
            let parts = Set(token.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            if parts.contains("plus") { return .plus }
            if parts.contains("pro") { return .pro }
            return nil
        }
    }

    private func apply(error: Error) {
        state = SubscriptionState(
            tier: state.tier,
            entitlementID: state.entitlementID,
            source: "revenuecat",
            updatedAt: state.updatedAt,
            errorMessage: error.localizedDescription
        )
    }

    private static func tier(for package: Package) -> SubscriptionTier? {
        tier(fromProductIdentifier: package.storeProduct.productIdentifier)
            ?? tier(fromProductIdentifier: package.identifier)
    }

    private static func subtitle(for package: Package) -> String {
        switch package.packageType {
        case .annual:
            return "Yıllık abonelik"
        case .monthly:
            return "Aylık abonelik"
        default:
            return package.storeProduct.localizedDescription.isEmpty
                ? "Abonelik"
                : package.storeProduct.localizedDescription
        }
    }
}

extension RevenueCatSubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            RevenueCatSubscriptionManager.shared.apply(customerInfo)
        }
    }
}
