import Combine
import Foundation
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
    let subtitle: String
    let productIdentifier: String
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
    func restorePurchases() async throws
}

@MainActor
final class RevenueCatSubscriptionManager: NSObject, ObservableObject, SubscriptionManaging {
    static let shared = RevenueCatSubscriptionManager()

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

    private override init() {
        super.init()
    }

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
            state = .free
            return
        }

        do {
            let result = try await Purchases.shared.logIn(userID.uuidString.lowercased())
            apply(result.customerInfo)
        } catch {
            apply(error: error)
        }
    }

    func loadOfferings() async {
        configure()

        do {
            let offerings = try await Purchases.shared.offerings()
            let allPackages = offerings.current?.availablePackages ?? offerings.all.values.flatMap(\.availablePackages)
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
                        subtitle: Self.subtitle(for: package),
                        productIdentifier: package.storeProduct.productIdentifier
                    )
                )
            }

            packageByID = rawByID
            packages = mappedPackages.sorted {
                if $0.tier.rank == $1.tier.rank { return $0.price < $1.price }
                return $0.tier.rank < $1.tier.rank
            }
        } catch {
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
        guard !result.userCancelled else { return }
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

    func restorePurchases() async throws {
        configure()
        let customerInfo = try await Purchases.shared.restorePurchases()
        apply(customerInfo)
    }

    private func apply(_ customerInfo: CustomerInfo) {
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

        state = SubscriptionState(
            tier: tier,
            entitlementID: entitlementID,
            source: "revenuecat",
            updatedAt: Date(),
            errorMessage: nil
        )
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
        let token = [
            package.identifier,
            package.storeProduct.productIdentifier,
            package.storeProduct.localizedTitle,
        ].joined(separator: " ").lowercased()
        if token.contains("pro") { return .pro }
        if token.contains("plus") { return .plus }
        return nil
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
