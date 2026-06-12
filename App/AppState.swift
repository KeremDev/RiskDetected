import Foundation
import SwiftUI
import Combine
import Supabase

enum RDThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Sistem"
        case .light: return "Aydınlık"
        case .dark: return "Karanlık"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "Telefon ayarını takip eder."
        case .light: return "Her zaman açık tema."
        case .dark: return "Her zaman koyu tema."
        }
    }

    var icon: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppFlow: Equatable {
    case splash
    case onboarding
    case auth
    case main
}

enum QuickScanSource {
    case chooser
    case camera
    case gallery
}

enum ProfileDestination {
    case preferences
}

private struct BackendSubscriptionRow: Decodable {
    let tier: String
    let status: String?
    let entitlementID: String?
    let currentPeriodEndsAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case tier
        case status
        case entitlementID = "entitlement_id"
        case currentPeriodEndsAt = "current_period_ends_at"
        case updatedAt = "updated_at"
    }
}

@MainActor
final class AppState: ObservableObject {
    private static let onboardingCompletedKey = "rd.onboarding.completed"
    private static let darkModeKey = "rd.theme.darkModeEnabled"
    private static let themePreferenceKey = "rd.theme.preference"
    private static let languagePreferenceKey = "rd.language.preference"

    @Published var flow: AppFlow = .splash
    @Published var isPro: Bool = false
    @Published var currentTier: SubscriptionTier = .free
    @Published var planCapabilities: PlanCapabilities = .forTier(.free)
    @Published var profile: UserProfile?
    @Published var activeTab: RDTab = .home
    @Published var pendingProfileDestination: ProfileDestination?
    @Published var quickScanRequestID = UUID()
    var quickScanSource: QuickScanSource = .chooser
    @Published var hasSeenOnboarding: Bool
    @Published var authError: String?
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var subscriptionState: SubscriptionState = .free
    @Published private(set) var backendSubscriptionState: SubscriptionState = .free
    @Published private(set) var subscriptionPackages: [SubscriptionPlanPackage] = []
    @Published var isDarkModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDarkModeEnabled, forKey: Self.darkModeKey)
        }
    }
    @Published var themePreference: RDThemePreference {
        didSet {
            UserDefaults.standard.set(themePreference.rawValue, forKey: Self.themePreferenceKey)
            isDarkModeEnabled = themePreference == .dark
        }
    }
    @Published var languagePreference: RDLanguagePreference {
        didSet {
            UserDefaults.standard.set(languagePreference.rawValue, forKey: Self.languagePreferenceKey)
        }
    }

    let auth: AuthService
    let subscriptions: any SubscriptionManaging

    private let backendSubscriptionVerificationDelaysNanoseconds: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        3_000_000_000,
        5_000_000_000
    ]
    private var pendingNotificationAnalysisID: UUID?
    private var cancellables = Set<AnyCancellable>()

    init(
        auth: AuthService? = nil,
        subscriptions: (any SubscriptionManaging)? = nil
    ) {
        #if DEBUG
        Self.prepareForUITestLaunchIfNeeded()
        #endif

        let resolved = auth ?? AuthService()
        let resolvedSubscriptions = subscriptions ?? RevenueCatSubscriptionManager.shared
        self.auth = resolved
        self.subscriptions = resolvedSubscriptions
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
        let storedTheme = UserDefaults.standard.string(forKey: Self.themePreferenceKey)
            .flatMap(RDThemePreference.init(rawValue:))
        let resolvedTheme = storedTheme ?? (UserDefaults.standard.bool(forKey: Self.darkModeKey) ? .dark : .system)
        self.themePreference = resolvedTheme
        self.isDarkModeEnabled = resolvedTheme == .dark
        let storedLanguage = UserDefaults.standard.string(forKey: Self.languagePreferenceKey)
            .flatMap(RDLanguagePreference.init(rawValue:))
        self.languagePreference = Self.normalizedLanguagePreference(storedLanguage)
        self.profile = resolved.profile
        self.isAuthenticated = resolved.isAuthenticated
        applyTier(.free)
        self.authError = resolved.lastError
        observeAuth()
        observeSubscriptions()
        observeNotificationRouting()

        #if DEBUG
        if Self.isUITestResetLaunch {
            flow = .onboarding
            Task { await resolved.resetLocalSessionForUITests() }
            return
        }
        if Self.isUITestMainLaunch {
            let testTier: SubscriptionTier = Self.isUITestFreeTierLaunch ? .free : .plus
            profile = Self.uiTestProfile(tier: testTier)
            backendSubscriptionState = SubscriptionState(
                tier: testTier,
                entitlementID: testTier.isPaid ? testTier.rawValue : nil,
                source: "ui_test",
                updatedAt: Date(),
                errorMessage: nil
            )
            applyTier(testTier)
            flow = .main
            return
        }
        #endif

        Task { await bootstrap() }
    }

    func bootstrap() async {
        #if DEBUG
        if Self.isUITestResetLaunch {
            await auth.resetLocalSessionForUITests()
            profile = nil
            backendSubscriptionState = .free
            applyTier(.free)
            flow = .onboarding
            return
        }
        #endif

        if auth.isAuthenticated {
            async let initialProfileRefresh: Void = auth.refreshProfile()
            async let pendingDraftSync = OnboardingAnswersService.shared.syncPendingDraftIfPossible()
            async let welcomeEmail: Void = sendWelcomeEmailIfPossible()

            await subscriptions.identify(userID: auth.session?.user.id)
            _ = await (initialProfileRefresh, pendingDraftSync, welcomeEmail)

            async let offeringsLoad: Void = subscriptions.loadOfferings()
            _ = await offeringsLoad

            await reconcileBackendSubscriptionSnapshot()
            await auth.refreshProfile()
            let backendState = await refreshBackendSubscriptionState()
            applyTier(backendState.tier)
            flow = .main
            routePendingNotificationIfReady(defaultTab: .home)
            return
        }

        flow = hasSeenOnboarding ? .auth : .onboarding
    }

    func finishOnboarding() {
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        if auth.isAuthenticated {
            Task {
                await OnboardingAnswersService.shared.syncPendingDraftIfPossible()
                await self.sendWelcomeEmailIfPossible()
            }
            flow = .main
            routePendingNotificationIfReady(defaultTab: .home)
        } else {
            flow = .auth
        }
    }

    /// Auth tarafı zaten signedIn yayınladığında otomatik geçilecek; manuel çağrı
    /// sadece auth tamamlanması sonrası explicit route geçişleri için saklıdır.
    func signIn() {
        flow = .main
        routePendingNotificationIfReady(defaultTab: .home)
    }

    func requestProfileDestination(_ destination: ProfileDestination) {
        activeTab = .profile
        pendingProfileDestination = destination
    }

    func signOut() {
        Task {
            try? await auth.signOut()
        }
    }

    func refreshSubscriptionOfferings() async {
        guard let userID = auth.session?.user.id else {
            subscriptionPackages = []
            return
        }
        await subscriptions.identify(userID: userID)
        await subscriptions.loadOfferings()
        subscriptionPackages = subscriptions.packages
    }

    func refreshPlanState() async {
        guard let userID = auth.session?.user.id else {
            await auth.refreshProfile()
            backendSubscriptionState = .free
            applyTier(.free)
            return
        }
        await subscriptions.identify(userID: userID)
        await subscriptions.refreshCustomerInfo()
        await reconcileBackendSubscriptionSnapshot()
        await auth.refreshProfile()
        let backendState = await refreshBackendSubscriptionState()
        applyTier(backendState.tier)
    }

    @discardableResult
    func purchaseSubscription(packageID: String, expectedTier: SubscriptionTier? = nil) async throws -> SubscriptionState {
        guard let userID = auth.session?.user.id else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Abonelik başlatmadan önce tekrar giriş yapman gerekiyor."]
            )
        }
        await subscriptions.identify(userID: userID)
        let purchasedState = try await subscriptions.purchase(packageID: packageID)
        let assertedTier = expectedTier ?? purchasedState.tier
        guard purchasedState.tier == assertedTier else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "Abonelik doğrulanamadı. Seçilen plan \(assertedTier.title), doğrulanan plan \(purchasedState.tier.title)."]
            )
        }
        let backendState = try await syncBackendSubscriptionWithRetry(expectedTier: assertedTier)
        await auth.refreshProfile()
        backendSubscriptionState = backendState
        guard backendState.tier == assertedTier else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "Abonelik backend tarafında doğrulanamadı. Lütfen birkaç saniye sonra tekrar dene veya satın alımları geri yükle."]
            )
        }
        applyTier(backendState.tier)
        return backendState
    }

    @discardableResult
    func restoreSubscriptions() async throws -> SubscriptionState {
        guard let userID = auth.session?.user.id else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Satın alımları geri yüklemek için tekrar giriş yapman gerekiyor."]
            )
        }
        await subscriptions.identify(userID: userID)
        let restoredState = try await subscriptions.restorePurchases()
        guard restoredState.tier.isPaid else {
            await auth.refreshProfile()
            let backendState = await refreshBackendSubscriptionState()
            applyTier(backendState.tier)
            return backendState
        }
        let backendState = try await syncBackendSubscriptionWithRetry(expectedTier: restoredState.tier)
        await auth.refreshProfile()
        backendSubscriptionState = backendState
        applyTier(backendState.tier)
        return backendState
    }

    func setDarkMode(_ enabled: Bool) {
        setThemePreference(enabled ? .dark : .light)
    }

    func setThemePreference(_ preference: RDThemePreference) {
        themePreference = preference
    }

    func setLanguagePreference(_ preference: RDLanguagePreference) {
        languagePreference = Self.normalizedLanguagePreference(preference)
    }

    private static func normalizedLanguagePreference(_ preference: RDLanguagePreference?) -> RDLanguagePreference {
        guard let preference, RDLanguagePreference.supportedCases.contains(preference) else {
            return .turkish
        }
        return preference
    }

    #if DEBUG
    private static var isUITestResetLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_RESET_STATE")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_RESET_STATE"] == "1"
    }

    private static var isUITestMainLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_MAIN")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_MAIN"] == "1"
    }

    private static var isUITestFreeTierLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_FREE_TIER")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_FREE_TIER"] == "1"
    }

    private static func prepareForUITestLaunchIfNeeded() {
        guard isUITestResetLaunch || isUITestMainLaunch else { return }
        let defaults = UserDefaults.standard
        if isUITestResetLaunch {
            [
                onboardingCompletedKey,
                "rd.onboarding.v2.pendingAnswers",
                "rd.theme.darkModeEnabled",
                "rd.theme.preference",
                "rd.language.preference",
                "rd.paywall.funnelSessionID",
            ].forEach { defaults.removeObject(forKey: $0) }
        }

        if CommandLine.arguments.contains("RD_UI_TEST_DARK_MODE")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_DARK_MODE"] == "1" {
            defaults.set(RDThemePreference.dark.rawValue, forKey: themePreferenceKey)
        }
    }

    private static func uiTestProfile(tier: SubscriptionTier = .plus) -> UserProfile {
        UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000f201")!,
            email: "ui-test@riskdetected.app",
            fullName: "UI Test Kullanıcı",
            initials: "UT",
            title: "İSG Uzmanı · A Sınıfı",
            certificateNumber: "UI-TEST-001",
            companyName: "RiskDetected Test Firma",
            companyLogoURL: nil,
            avatarURL: nil,
            phone: "Test profil",
            tier: tier,
            preferredMethod: .fineKinney,
            dailyQuotaUsed: 0,
            dailyQuotaResetAt: nil,
            subscriptionPeriod: "monthly",
            subscriptionRenewalAt: nil,
            createdAt: nil
        )
    }
    #endif

    // MARK: - Observation

    /// Combine .sink ile auth state'ini SENKRON olarak mirror'lar.
    /// AsyncSequence (.values) pattern'i bazı durumlarda gecikmeli/atlamalı
    /// tetiklenebiliyor — sink garanti tetikler.
    private func observeAuth() {
        // Profile mirror
        auth.$profile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newProfile in
                guard let self else { return }
                #if DEBUG
                guard !Self.isUITestMainLaunch else { return }
                #endif
                self.profile = newProfile
            }
            .store(in: &cancellables)

        // Session mirror — flow geçişlerini tetikle
        auth.$session
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self else { return }
                #if DEBUG
                guard !Self.isUITestMainLaunch else { return }
                #endif
                self.isAuthenticated = session != nil
                if let session {
                    Task {
                        await LegalAcceptanceService.shared
                            .recordLoginNoticeAcceptanceIfNeeded(userID: session.user.id)
                        await NotificationService.shared.refreshSettings()
                        NotificationService.shared.syncCurrentTokenIfPossible()
                        await self.subscriptions.identify(userID: session.user.id)
                        await OnboardingAnswersService.shared.syncPendingDraftIfPossible()
                        await self.refreshPlanState()
                        await self.sendWelcomeEmailIfPossible()
                    }
                    if self.flow == .onboarding && !self.hasSeenOnboarding {
                        return
                    }
                    if self.flow != .main {
                        self.flow = .main
                    }
                    self.routePendingNotificationIfReady(defaultTab: .home)
                } else if self.flow == .main {
                    Task { await self.subscriptions.identify(userID: nil) }
                    self.backendSubscriptionState = .free
                    self.applyTier(.free)
                    self.flow = .auth
                }
            }
            .store(in: &cancellables)

        // lastError mirror — UI gösterimi için
        auth.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] err in
                self?.authError = err
            }
            .store(in: &cancellables)
    }

    private func observeNotificationRouting() {
        NotificationService.shared.$pendingAnalysisHistoryID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] analysisID in
                guard let self, let analysisID else { return }
                self.pendingNotificationAnalysisID = analysisID
                self.routePendingNotificationIfReady()
            }
            .store(in: &cancellables)

        NotificationService.shared.$pendingDestinationTab
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tab in
                guard let self, let tab else { return }
                self.routePendingNotificationIfReady(defaultTab: tab)
                if self.flow == .main, self.auth.isAuthenticated {
                    NotificationService.shared.pendingDestinationTab = nil
                }
            }
            .store(in: &cancellables)
    }

    private func routePendingNotificationIfReady(defaultTab: RDTab? = nil) {
        guard flow == .main, auth.isAuthenticated else {
            if let defaultTab, pendingNotificationAnalysisID == nil {
                activeTab = defaultTab
            }
            return
        }
        if pendingNotificationAnalysisID != nil {
            activeTab = .analyses
            pendingNotificationAnalysisID = nil
            NotificationService.shared.pendingAnalysisHistoryID = nil
        } else if let defaultTab {
            activeTab = defaultTab
        }
    }

    private func observeSubscriptions() {
        #if DEBUG
        if Self.isUITestMainLaunch { return }
        #endif
        subscriptions.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                #if DEBUG
                guard !Self.isUITestMainLaunch else { return }
                #endif
                self.subscriptionState = state
            }
            .store(in: &cancellables)

        subscriptions.packagesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] packages in
                self?.subscriptionPackages = packages
            }
            .store(in: &cancellables)
    }

    private func applyTier(_ tier: SubscriptionTier) {
        currentTier = tier
        planCapabilities = PlanCapabilities.forTier(tier)
        isPro = tier == .pro
    }

    @discardableResult
    private func refreshBackendSubscriptionState() async -> SubscriptionState {
        guard let userID = auth.session?.user.id else {
            backendSubscriptionState = .free
            return .free
        }

        do {
            let row: BackendSubscriptionRow = try await SupabaseService.shared.client
                .from("user_subscriptions")
                .select("tier,status,entitlement_id,current_period_ends_at,updated_at")
                .eq("user_id", value: userID.uuidString)
                .single()
                .execute()
                .value
            let state = Self.subscriptionState(from: row)
            backendSubscriptionState = state
            return state
        } catch let error as PostgrestError where Self.isMissingBackendSubscriptionError(error) {
            backendSubscriptionState = .free
            return .free
        } catch {
            let failedClosedState = SubscriptionState(
                tier: .free,
                entitlementID: nil,
                source: "supabase",
                updatedAt: Date(),
                errorMessage: error.localizedDescription
            )
            backendSubscriptionState = failedClosedState
            return failedClosedState
        }
    }

    private static func subscriptionState(from row: BackendSubscriptionRow) -> SubscriptionState {
        guard let tier = SubscriptionTier(rawValue: row.tier),
              tier.isPaid,
              Self.isActiveBackendStatus(row.status),
              Self.isFutureExpiration(row.currentPeriodEndsAt)
        else {
            return SubscriptionState(
                tier: .free,
                entitlementID: nil,
                source: row.status ?? "supabase",
                updatedAt: Date(),
                errorMessage: nil
            )
        }

        return SubscriptionState(
            tier: tier,
            entitlementID: row.entitlementID,
            source: row.status ?? "supabase",
            updatedAt: Date(),
            errorMessage: nil
        )
    }

    private static func isActiveBackendStatus(_ status: String?) -> Bool {
        guard let status else { return false }
        return ["active", "trialing", "grace_period"].contains(status)
    }

    private static func isFutureExpiration(_ value: String?) -> Bool {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date > Date()
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value).map { $0 > Date() } ?? false
    }

    private static func isMissingBackendSubscriptionError(_ error: PostgrestError) -> Bool {
        if error.code == "PGRST116" { return true }
        let lower = error.message.lowercased(with: Locale(identifier: "en_US_POSIX"))
        return lower.contains("0 rows") || lower.contains("no rows")
    }

    private func reconcileBackendSubscriptionSnapshot() async {
        guard auth.session != nil else { return }

        struct EmptySyncBody: Encodable {}
        struct SyncResponse: Decodable {
            let tier: String?
        }

        do {
            let _: SyncResponse = try await SupabaseService.shared.functions.invoke(
                RDConfig.syncRevenueCatSubscriptionFunctionName,
                options: FunctionInvokeOptions(body: EmptySyncBody())
            )
        } catch {
            // Paid access is intentionally not unlocked from this passive sync.
            // Purchase/restore paths call syncBackendSubscription(expectedTier:).
        }
    }

    private func syncBackendSubscription(expectedTier: SubscriptionTier) async throws -> SubscriptionState {
        guard auth.session != nil else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Abonelik doğrulaması için tekrar giriş yapman gerekiyor."]
            )
        }
        struct SyncBody: Encodable {
            let expected_tier: String
            let expected_entitlement_id: String?
        }
        struct SyncResponse: Decodable {
            let tier: String?
            let entitlement_id: String?
            let status: String?
        }

        let response: SyncResponse = try await SupabaseService.shared.functions.invoke(
            RDConfig.syncRevenueCatSubscriptionFunctionName,
            options: FunctionInvokeOptions(
                body: SyncBody(
                    expected_tier: expectedTier.rawValue,
                    expected_entitlement_id: subscriptions.state.entitlementID
                )
            )
        )
        guard let tier = response.tier.flatMap(SubscriptionTier.init(rawValue:)) else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 502,
                userInfo: [NSLocalizedDescriptionKey: "Abonelik doğrulama yanıtı okunamadı."]
            )
        }
        guard tier == expectedTier || (!expectedTier.isPaid && !tier.isPaid) else {
            let message: String
            if expectedTier.isPaid && !tier.isPaid {
                message = "App Store hesabında \(expectedTier.title) aboneliği görünüyor, ancak RevenueCat backend doğrulaması henüz ücretli plan döndürmüyor. Güvenlik için plan açılmadı; abonelik RevenueCat/Supabase tarafında eşleşince otomatik açılır."
            } else {
                message = "Abonelik doğrulanamadı. Seçilen plan \(expectedTier.title), backend planı \(tier.title)."
            }
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return SubscriptionState(
            tier: tier,
            entitlementID: response.entitlement_id,
            source: response.status ?? "supabase",
            updatedAt: Date(),
            errorMessage: nil
        )
    }

    private func syncBackendSubscriptionWithRetry(expectedTier: SubscriptionTier) async throws -> SubscriptionState {
        do {
            return try await syncBackendSubscription(expectedTier: expectedTier)
        } catch {
            guard expectedTier.isPaid,
                  Self.isBackendTierMismatch(error),
                  !backendSubscriptionVerificationDelaysNanoseconds.isEmpty
            else {
                throw error
            }

            var lastError = error
            for delay in backendSubscriptionVerificationDelaysNanoseconds {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: delay)
                do {
                    return try await syncBackendSubscription(expectedTier: expectedTier)
                } catch {
                    lastError = error
                    guard Self.isBackendTierMismatch(error) else {
                        throw error
                    }
                }
            }
            throw lastError
        }
    }

    private static func isBackendTierMismatch(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "RiskDetected.Subscription", nsError.code == 409 else {
            return false
        }
        let message = nsError.localizedDescription.lowercased(with: Locale(identifier: "tr_TR"))
        return message.contains("backend planı")
            || message.contains("backend doğrulaması henüz")
            || message.contains("revenuecat backend doğrulaması")
    }

    private func sendWelcomeEmailIfPossible() async {
        guard auth.session != nil else { return }

        do {
            _ = try await WelcomeEmailService.shared.sendIfNeeded()
        } catch {
            // Welcome email delivery is tracked server-side and must not block sign-in.
        }
    }

    func requestQuickScan(source: QuickScanSource = .chooser) {
        quickScanSource = source
        activeTab = .home
        quickScanRequestID = UUID()
    }
}
