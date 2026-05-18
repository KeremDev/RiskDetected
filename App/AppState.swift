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

@MainActor
final class AppState: ObservableObject {
    private static let darkModeKey = "rd.theme.darkModeEnabled"
    private static let themePreferenceKey = "rd.theme.preference"
    private static let languagePreferenceKey = "rd.language.preference"

    @Published var flow: AppFlow = .splash
    @Published var isPro: Bool = false
    @Published var currentTier: SubscriptionTier = .free
    @Published var planCapabilities: PlanCapabilities = .forTier(.free)
    @Published var profile: UserProfile?
    @Published var activeTab: RDTab = .home
    @Published var quickScanRequestID = UUID()
    var quickScanSource: QuickScanSource = .chooser
    @Published var hasSeenOnboarding: Bool
    @Published var authError: String?
    @Published private(set) var subscriptionState: SubscriptionState = .free
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

    private var cancellables = Set<AnyCancellable>()

    init(
        auth: AuthService? = nil,
        subscriptions: (any SubscriptionManaging)? = nil
    ) {
        let resolved = auth ?? AuthService()
        let resolvedSubscriptions = subscriptions ?? RevenueCatSubscriptionManager.shared
        self.auth = resolved
        self.subscriptions = resolvedSubscriptions
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: "rd.onboarding.completed")
        let storedTheme = UserDefaults.standard.string(forKey: Self.themePreferenceKey)
            .flatMap(RDThemePreference.init(rawValue:))
        let resolvedTheme = storedTheme ?? (UserDefaults.standard.bool(forKey: Self.darkModeKey) ? .dark : .system)
        self.themePreference = resolvedTheme
        self.isDarkModeEnabled = resolvedTheme == .dark
        let storedLanguage = UserDefaults.standard.string(forKey: Self.languagePreferenceKey)
            .flatMap(RDLanguagePreference.init(rawValue:))
        self.languagePreference = Self.normalizedLanguagePreference(storedLanguage)
        self.profile = resolved.profile
        applyTier(displayTier(profileTier: resolved.profile?.tier ?? .free, subscriptionTier: resolvedSubscriptions.state.tier))
        self.authError = resolved.lastError
        resolvedSubscriptions.configure()
        observeAuth()
        observeSubscriptions()
        Task { await bootstrap() }
    }

    func bootstrap() async {
        try? await Task.sleep(nanoseconds: 800_000_000)

        if auth.isAuthenticated {
            // Profile observer'ı zaten bağladığımız için fetch otomatik tetiklenir,
            // yine de kesinlik için bir kez daha refresh edelim.
            await auth.refreshProfile()
            await subscriptions.identify(userID: auth.session?.user.id)
            await syncBackendSubscription()
            await auth.refreshProfile()
            await subscriptions.loadOfferings()
            activeTab = .home
            flow = .main
            return
        }

        flow = hasSeenOnboarding ? .auth : .onboarding
    }

    func finishOnboarding() {
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: "rd.onboarding.completed")
        flow = .auth
    }

    /// Auth tarafı zaten signedIn yayınladığında otomatik geçilecek; manuel çağrıyı
    /// AuthView'in geçici "demo giriş" senaryosu için saklıyoruz.
    func signIn() {
        activeTab = .home
        flow = .main
    }

    func signOut() {
        Task {
            try? await auth.signOut()
        }
    }

    func refreshSubscriptionOfferings() async {
        await subscriptions.loadOfferings()
    }

    func refreshPlanState() async {
        await subscriptions.refreshCustomerInfo()
        await syncBackendSubscription()
        await auth.refreshProfile()
        applyTier(displayTier(profileTier: auth.profile?.tier ?? .free, subscriptionTier: subscriptions.state.tier))
    }

    func purchaseSubscription(packageID: String) async throws {
        try await subscriptions.purchase(packageID: packageID)
        await syncBackendSubscription()
        await auth.refreshProfile()
    }

    @discardableResult
    func restoreSubscriptions() async throws -> SubscriptionState {
        let restoredState = try await subscriptions.restorePurchases()
        await syncBackendSubscription()
        await auth.refreshProfile()
        return restoredState
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
                self.profile = newProfile
                self.applyTier(self.displayTier(profileTier: newProfile?.tier ?? .free, subscriptionTier: self.subscriptionState.tier))
            }
            .store(in: &cancellables)

        // Session mirror — flow geçişlerini tetikle
        auth.$session
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self else { return }
                if let session {
                    Task {
                        await LegalAcceptanceService.shared
                            .recordLoginNoticeAcceptanceIfNeeded(userID: session.user.id)
                        await NotificationService.shared.refreshSettings()
                        NotificationService.shared.syncCurrentTokenIfPossible()
                        await self.subscriptions.identify(userID: session.user.id)
                    }
                    self.activeTab = .home
                    if self.flow != .main {
                        self.flow = .main
                    }
                } else if self.flow == .main {
                    Task { await self.subscriptions.identify(userID: nil) }
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

    private func observeSubscriptions() {
        subscriptions.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.subscriptionState = state
                self.applyTier(self.displayTier(profileTier: self.profile?.tier ?? .free, subscriptionTier: state.tier))
            }
            .store(in: &cancellables)

        subscriptions.packagesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] packages in
                self?.subscriptionPackages = packages
            }
            .store(in: &cancellables)
    }

    private func displayTier(profileTier: SubscriptionTier, subscriptionTier: SubscriptionTier) -> SubscriptionTier {
        if subscriptionTier.isPaid {
            return subscriptionTier
        }
        return .free
    }

    private func applyTier(_ tier: SubscriptionTier) {
        currentTier = tier
        planCapabilities = PlanCapabilities.forTier(tier)
        isPro = tier == .pro
    }

    private func syncBackendSubscription() async {
        guard auth.session != nil else { return }
        struct SyncBody: Encodable {
            let expected_tier: String
            let expected_entitlement_id: String?
        }
        struct SyncResponse: Decodable {
            let tier: String?
        }

        do {
            let response: SyncResponse = try await SupabaseService.shared.functions.invoke(
                RDConfig.syncRevenueCatSubscriptionFunctionName,
                options: FunctionInvokeOptions(
                    body: SyncBody(
                        expected_tier: subscriptions.state.tier.rawValue,
                        expected_entitlement_id: subscriptions.state.entitlementID
                    )
                )
            )
            if let tier = response.tier.flatMap(SubscriptionTier.init(rawValue:)) {
                applyTier(displayTier(profileTier: tier, subscriptionTier: subscriptions.state.tier))
            }
        } catch {
            // RevenueCat SDK state remains the user-facing source; backend sync retry
            // happens on the next refresh/purchase/restore/bootstrap.
        }
    }

    func requestQuickScan(source: QuickScanSource = .chooser) {
        quickScanSource = source
        activeTab = .home
        quickScanRequestID = UUID()
    }
}
