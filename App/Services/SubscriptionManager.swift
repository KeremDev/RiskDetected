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
    var managementURL: URL? = nil

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
    /// App Store fiyatının sayısal karşılığı; yıllık indirim oranını hesaplamak için.
    var priceAmount: Decimal? = nil
    /// Ücretsiz deneme gün sayısı (introductory offer). Teklif yoksa nil.
    var introductoryFreeTrialDays: Int? = nil

    var displayPrice: String? {
        Self.displayableStorePrice(price)
    }

    var displayMonthlyEquivalentPrice: String? {
        Self.displayableStorePrice(monthlyEquivalentPrice)
    }

    static func displayableStorePrice(_ price: String?) -> String? {
        guard let price else { return nil }
        let trimmed = price.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum SubscriptionManagerError: LocalizedError {
    case noPackagesConfigured
    case restoredPurchaseBelongsToAnotherAccount
    case purchasedSubscriptionBelongsToAnotherAccount
    case storeAccountAlreadyHasSubscription
    case purchaseTierMismatch(expected: SubscriptionTier, resolved: SubscriptionTier)
    case higherTierAlreadyActive(current: SubscriptionTier, selected: SubscriptionTier)

    var errorDescription: String? {
        switch self {
        case .noPackagesConfigured:
            return RDLocalization.string("paywall.subscription.manager.abonelik.paketleri.revenuecat.tarafinda.bulunama.83b104fa", table: .paywall, fallback: "Abonelik paketleri RevenueCat tarafında bulunamadı.")
        case .restoredPurchaseBelongsToAnotherAccount:
            return AppErrorMessage.subscriptionReceiptConflictMessage
        case .purchasedSubscriptionBelongsToAnotherAccount:
            return AppErrorMessage.subscriptionReceiptConflictMessage
        case .storeAccountAlreadyHasSubscription:
            return AppErrorMessage.existingAppStoreSubscriptionMessage
        case let .purchaseTierMismatch(expected, resolved):
            return RDLocalization.format("paywall.subscription.manager.app.store.aboneligi.dogrulanamadi.secilen.plan.1.44981b3a", table: .paywall, fallback: "App Store aboneliği doğrulanamadı. Seçilen plan %1$@, doğrulanan plan %2$@. Lütfen tekrar dene veya destekle iletişime geç.", arguments: [String(describing: expected.title), String(describing: resolved.title)])
        case let .higherTierAlreadyActive(current, selected):
            return AppErrorMessage.subscriptionActiveHigherTierMessage(current: current, selected: selected)
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
    @discardableResult
    func purchase(packageID: String) async throws -> SubscriptionState
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
              let fileURL = diagnosticsFileURL
        else { return }
        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static var diagnosticsFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("revenuecat-diagnostics.log")
    }

    private static func clearDiagnostics() {
        guard let diagnosticsFileURL else { return }
        try? FileManager.default.removeItem(at: diagnosticsFileURL)
    }

    #if DEBUG
    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
    }
    #endif

    private static func diagnosticSummary(for customerInfo: CustomerInfo) -> String {
        let entitlements = customerInfo.entitlements.active.keys.sorted().joined(separator: ",")
        let products = customerInfo.activeSubscriptions.sorted().joined(separator: ",")
        return RDLocalization.format("paywall.subscription.manager.original.1.activeproducts.2.activeentitlements.3.14079dbe", table: .paywall, fallback: "orijinal=%1$@ aktifÜrünler=[%2$@] activeEntitlements=[%3$@]", arguments: [String(describing: customerInfo.originalAppUserId), String(describing: products), String(describing: entitlements)])
    }
    #endif

    func configure() {
        configureIfNeeded()
    }

    private func configureIfNeeded(appUserID: String? = nil) {
        guard !isConfigured else { return }

        #if DEBUG
        if Self.isUITestLaunch {
            return
        }
        Purchases.logLevel = .debug
        #endif

        if let appUserID {
            Purchases.configure(withAPIKey: RDConfig.Subscription.revenueCatAPIKey, appUserID: appUserID)
            currentAppUserID = appUserID
        } else {
            Purchases.configure(withAPIKey: RDConfig.Subscription.revenueCatAPIKey)
        }
        Purchases.shared.delegate = self
        enableAppleAdsAttributionCollection()
        isConfigured = true
    }

    private func enableAppleAdsAttributionCollection() {
        #if os(iOS)
        Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()
        Self.logger.info("RevenueCat Apple Ads AdServices attribution token collection enabled.")
        #endif
    }

    func identify(userID: UUID?) async {
        guard let userID else {
            currentAppUserID = nil
            state = .free
            return
        }

        do {
            let appUserID = userID.uuidString.lowercased()
            if !isConfigured {
                configureIfNeeded(appUserID: appUserID)
                let customerInfo = try await Purchases.shared.customerInfo()
                try applyVerified(customerInfo)
                return
            }
            if currentAppUserID == appUserID {
                let customerInfo = try await Purchases.shared.customerInfo()
                try applyVerified(customerInfo)
                return
            }
            let result = try await Purchases.shared.logIn(appUserID)
            currentAppUserID = appUserID
            enableAppleAdsAttributionCollection()
            try applyVerified(result.customerInfo)
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
            let configuredOfferingID = RDConfig.Subscription.offeringIdentifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedOffering = configuredOfferingID.isEmpty
                ? offerings.current
                : offerings.offering(identifier: configuredOfferingID)
            let allPackages = selectedOffering?.availablePackages ?? []
            #if DEBUG
            let selectedOfferingLabel = selectedOffering?.identifier ?? "nil"
            Self.writeDiagnostics("RD_REVENUECAT_SELECTED_OFFERING \(selectedOfferingLabel)")
            #endif
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
                        productIdentifier: package.storeProduct.productIdentifier,
                        priceAmount: package.storeProduct.price,
                        introductoryFreeTrialDays: Self.introductoryFreeTrialDays(for: package)
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
                    errorMessage: nil,
                    managementURL: state.managementURL
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

    @discardableResult
    func purchase(packageID: String) async throws -> SubscriptionState {
        guard currentAppUserID != nil else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("paywall.subscription.manager.abonelik.baslatmadan.once.tekrar.giris.yapman.ge.fd36f753", table: .paywall, fallback: "Abonelik başlatmadan önce tekrar giriş yapman gerekiyor.")]
            )
        }
        configure()
        if packageByID[packageID] == nil {
            await loadOfferings()
        }
        guard let package = packageByID[packageID] else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("paywall.subscription.manager.secilen.abonelik.paketi.bulunamadi.6baced3f", table: .paywall, fallback: "Seçilen abonelik paketi bulunamadı.")]
            )
        }
        let expectedTier = Self.tier(for: package)
        if let existingCustomerInfo = try? await freshCustomerInfo(reason: "purchase_precheck") {
            let existingState = Self.state(from: existingCustomerInfo)
            try validateReceiptOwner(existingCustomerInfo, resolvedState: existingState)
            if let expectedTier,
               existingState.tier.isPaid {
                if existingState.tier == expectedTier {
                    return apply(existingCustomerInfo)
                }
                if existingState.tier.rank > expectedTier.rank {
                    let error = SubscriptionManagerError.higherTierAlreadyActive(
                        current: existingState.tier,
                        selected: expectedTier
                    )
                    state = Self.state(
                        from: existingCustomerInfo,
                        errorMessage: error.localizedDescription
                    )
                    throw error
                }
            }
        }
        let result: PurchaseResultData
        do {
            result = try await Purchases.shared.purchase(package: package)
        } catch {
            let classification = PurchaseErrorClassifier.classify(error)
            Self.logger.error(
                """
                RevenueCat purchase failed \
                product=\(package.storeProduct.productIdentifier, privacy: .public) \
                \(classification.debugSummary, privacy: .public)
                """
            )
            #if DEBUG
            Self.writeDiagnostics("RD_REVENUECAT_PURCHASE_ERROR product=\(package.storeProduct.productIdentifier) \(classification.debugSummary)")
            #endif

            if classification.kind == .cancelled {
                throw CancellationError()
            }

            if classification.kind == .existingSubscription,
               let customerInfo = try? await freshCustomerInfo(reason: "purchase_existing_subscription") {
                let ownedState = Self.state(from: customerInfo, preferredProductIdentifier: package.storeProduct.productIdentifier)
                try validateReceiptOwner(customerInfo, resolvedState: ownedState)
                if let expectedTier = Self.tier(for: package) {
                    if ownedState.tier == expectedTier {
                        return apply(customerInfo, preferredProductIdentifier: package.storeProduct.productIdentifier)
                    }
                    if ownedState.tier.rank > expectedTier.rank {
                        let error = SubscriptionManagerError.higherTierAlreadyActive(
                            current: ownedState.tier,
                            selected: expectedTier
                        )
                        state = Self.state(
                            from: customerInfo,
                            preferredProductIdentifier: package.storeProduct.productIdentifier,
                            errorMessage: error.localizedDescription
                        )
                        throw error
                    }
                }
                throw SubscriptionManagerError.storeAccountAlreadyHasSubscription
            }
            throw error
        }
        guard !result.userCancelled else { throw CancellationError() }
        let purchasedState = Self.state(from: result.customerInfo, preferredProductIdentifier: package.storeProduct.productIdentifier)
        #if DEBUG
        Self.writeDiagnostics(
            "RD_REVENUECAT_PURCHASE_RESULT product=\(package.storeProduct.productIdentifier) tier=\(purchasedState.tier.rawValue) \(Self.diagnosticSummary(for: result.customerInfo))"
        )
        #endif
        try validateReceiptOwner(result.customerInfo, resolvedState: purchasedState)
        if let expectedTier, purchasedState.tier != expectedTier {
            let mappedError = Self.purchaseTierMismatchError(expected: expectedTier, resolved: purchasedState.tier)
            state = Self.state(
                from: result.customerInfo,
                preferredProductIdentifier: package.storeProduct.productIdentifier,
                errorMessage: mappedError.localizedDescription
            )
            throw mappedError
        }
        return apply(result.customerInfo, preferredProductIdentifier: package.storeProduct.productIdentifier)
    }

    func refreshCustomerInfo() async {
        guard currentAppUserID != nil else {
            state = .free
            return
        }
        configure()

        do {
            let customerInfo = try await freshCustomerInfo(reason: "refresh")
            try applyVerified(customerInfo)
        } catch {
            apply(error: error)
        }
    }

    @discardableResult
    func restorePurchases() async throws -> SubscriptionState {
        guard currentAppUserID != nil else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("paywall.subscription.manager.satin.alimlari.geri.yuklemek.icin.tekrar.giris.y.2d7f4974", table: .paywall, fallback: "Satın alımları geri yüklemek için tekrar giriş yapman gerekiyor.")]
            )
        }
        configure()
        Purchases.shared.invalidateCustomerInfoCache()
        #if DEBUG
        Self.writeDiagnostics("RD_REVENUECAT_RESTORE_START")
        #endif
        if let preRestoreCustomerInfo = try? await freshCustomerInfo(reason: "restore_precheck") {
            let preRestoreState = Self.state(from: preRestoreCustomerInfo)
            try validateReceiptOwner(preRestoreCustomerInfo, resolvedState: preRestoreState)
        }
        let customerInfo = try await Purchases.shared.restorePurchases()
        Purchases.shared.invalidateCustomerInfoCache()
        let refreshedCustomerInfo = try await freshCustomerInfo(reason: "restore")
        #if DEBUG
        Self.writeDiagnostics("RD_REVENUECAT_RESTORE_RESULT \(Self.diagnosticSummary(for: customerInfo))")
        Self.writeDiagnostics("RD_REVENUECAT_RESTORE_REFRESHED \(Self.diagnosticSummary(for: refreshedCustomerInfo))")
        #endif
        let restoredState = Self.state(from: refreshedCustomerInfo)
        try validateReceiptOwner(refreshedCustomerInfo, resolvedState: restoredState)
        return apply(refreshedCustomerInfo)
    }

    private func freshCustomerInfo(reason: String) async throws -> CustomerInfo {
        Purchases.shared.invalidateCustomerInfoCache()
        let customerInfo = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
        #if DEBUG
        Self.writeDiagnostics("RD_REVENUECAT_CUSTOMER_INFO_\(reason.uppercased()) \(Self.diagnosticSummary(for: customerInfo))")
        #endif
        return customerInfo
    }

    @discardableResult
    private func apply(_ customerInfo: CustomerInfo, preferredProductIdentifier: String? = nil) -> SubscriptionState {
        let nextState = Self.state(from: customerInfo, preferredProductIdentifier: preferredProductIdentifier)
        state = nextState
        return nextState
    }

    @discardableResult
    private func applyVerified(
        _ customerInfo: CustomerInfo,
        preferredProductIdentifier: String? = nil
    ) throws -> SubscriptionState {
        let nextState = Self.state(
            from: customerInfo,
            preferredProductIdentifier: preferredProductIdentifier
        )
        try validateReceiptOwner(customerInfo, resolvedState: nextState)
        state = nextState
        return nextState
    }

    private static func state(
        from customerInfo: CustomerInfo,
        preferredProductIdentifier: String? = nil,
        errorMessage: String? = nil
    ) -> SubscriptionState {
        if let preferredProductIdentifier,
           customerInfo.activeSubscriptions.contains(preferredProductIdentifier),
           let preferredTier = tier(fromProductIdentifier: preferredProductIdentifier) {
            return SubscriptionState(
                tier: preferredTier,
                entitlementID: preferredTier.rawValue,
                source: "revenuecat",
                updatedAt: Date(),
                errorMessage: errorMessage,
                managementURL: customerInfo.managementURL
            )
        }

        if let productTier = tier(fromActiveSubscriptionsIn: customerInfo) {
            return SubscriptionState(
                tier: productTier,
                entitlementID: productTier.isPaid ? productTier.rawValue : nil,
                source: "revenuecat",
                updatedAt: Date(),
                errorMessage: errorMessage,
                managementURL: customerInfo.managementURL
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
            errorMessage: errorMessage,
            managementURL: customerInfo.managementURL
        )
    }

    private static func purchaseTierMismatchError(
        expected: SubscriptionTier,
        resolved: SubscriptionTier
    ) -> SubscriptionManagerError {
        if resolved.rank > expected.rank {
            return .higherTierAlreadyActive(current: resolved, selected: expected)
        }
        return .purchaseTierMismatch(expected: expected, resolved: resolved)
    }

    private func validateReceiptOwner(_ customerInfo: CustomerInfo, resolvedState: SubscriptionState) throws {
        guard resolvedState.tier.isPaid else { return }
        guard let currentAppUserID else { return }
        let original = customerInfo.originalAppUserId.lowercased()
        guard !original.hasPrefix("$rcanonymousid:") else { return }
        guard original != currentAppUserID else { return }

        let error = SubscriptionManagerError.storeAccountAlreadyHasSubscription
        state = SubscriptionState(
            tier: .free,
            entitlementID: nil,
            source: "revenuecat",
            updatedAt: Date(),
            errorMessage: error.localizedDescription,
            managementURL: state.managementURL
        )
        throw error
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

    /// RevenueCat introductory offer'ı ücretsiz denemeye çevirir. Teklif tanımlı
    /// değilse nil döner; paywall deneme anlatımını yalnızca teklif varken gösterir.
    private static func introductoryFreeTrialDays(for package: Package) -> Int? {
        guard let discount = package.storeProduct.introductoryDiscount,
              discount.paymentMode == .freeTrial else { return nil }
        let period = discount.subscriptionPeriod
        let periods = max(1, discount.numberOfPeriods)
        switch period.unit {
        case .day: return period.value * periods
        case .week: return period.value * 7 * periods
        case .month: return period.value * 30 * periods
        case .year: return period.value * 365 * periods
        @unknown default: return nil
        }
    }

    private static func subtitle(for package: Package) -> String {
        switch package.packageType {
        case .annual:
            return RDLocalization.string("paywall.subscription.manager.yillik.abonelik.c46f4eac", table: .paywall, fallback: "Yıllık abonelik")
        case .monthly:
            return RDLocalization.string("paywall.subscription.manager.aylik.abonelik.a9ddd6bf", table: .paywall, fallback: "Aylık abonelik")
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
            guard RevenueCatSubscriptionManager.shared.currentAppUserID != nil else {
                RevenueCatSubscriptionManager.shared.state = .free
                return
            }
            let updatedState = RevenueCatSubscriptionManager.state(from: customerInfo)
            do {
                try RevenueCatSubscriptionManager.shared.validateReceiptOwner(customerInfo, resolvedState: updatedState)
                RevenueCatSubscriptionManager.shared.apply(customerInfo)
            } catch {
                RevenueCatSubscriptionManager.shared.apply(error: error)
            }
        }
    }
}
