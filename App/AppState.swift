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
        case .system: return RDLocalization.string("localizable.app.state.sistem.9cce35aa", table: .localizable, fallback: "Sistem")
        case .light: return RDLocalization.string("localizable.app.state.aydinlik.af1a2800", table: .localizable, fallback: "Aydınlık")
        case .dark: return RDLocalization.string("localizable.app.state.karanlik.e3c9f637", table: .localizable, fallback: "Karanlık")
        }
    }

    var subtitle: String {
        switch self {
        case .system: return RDLocalization.string("localizable.app.state.telefon.ayarini.takip.eder.bd03e613", table: .localizable, fallback: "Telefon ayarını takip eder.")
        case .light: return RDLocalization.string("localizable.app.state.her.zaman.acik.tema.04d1e49b", table: .localizable, fallback: "Her zaman açık tema.")
        case .dark: return RDLocalization.string("localizable.app.state.her.zaman.koyu.tema.aa37f82a", table: .localizable, fallback: "Her zaman koyu tema.")
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

enum SubscriptionOfferingsLoadState: Equatable {
    case loading
    case retryingOnce
    case loaded
    case failed(String)

    var isLoading: Bool {
        switch self {
        case .loading, .retryingOnce:
            return true
        case .loaded, .failed:
            return false
        }
    }

    var errorMessage: String? {
        switch self {
        case let .failed(message):
            return message
        case .loading, .retryingOnce, .loaded:
            return nil
        }
    }
}

enum QuickScanSource {
    case chooser
    case camera
    case gallery
}

enum ProfileDestination {
    case preferences
    case referral
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

private struct BackendPlanCapabilityRuleRow: Decodable {
    let maxPhotosPerAnalysis: Int?
    let visiblePhotoSlotsInUI: Int?
    let maxFindingsPerPhoto: Int?
    let maxFindingsPerAnalysis: Int?
    let canUseMultiPhotoAnalysis: Bool?
    let canEditAIFindings: Bool?
    let canAddManualFindings: Bool?

    enum CodingKeys: String, CodingKey {
        case maxPhotosPerAnalysis = "max_photos_per_analysis"
        case visiblePhotoSlotsInUI = "visible_photo_slots_in_ui"
        case maxFindingsPerPhoto = "max_findings_per_photo"
        case maxFindingsPerAnalysis = "max_findings_per_analysis"
        case canUseMultiPhotoAnalysis = "can_use_multi_photo_analysis"
        case canEditAIFindings = "can_edit_ai_findings"
        case canAddManualFindings = "can_add_manual_findings"
    }
}

private struct BackendMultiPhotoFlags: Decodable {
    let killSwitch: Bool?
    let rolloutMode: String?
    let enabledIOSBuilds: [String]?
    let minIOSBuild: Int?
    let features: BackendFeatureFlags?
    let enableMultiPhotoAnalysis: Bool?
    let enablePhotoLimitLockedSlotsForFree: Bool?
    let enablePlusPro5PhotoLimit: Bool?
    let enableEditableFindings: Bool?
    let enableManualFindingAdd: Bool?
    let maxPhotoCountFree: Int?
    let maxPhotoCountPlus: Int?
    let maxPhotoCountPro: Int?
    let maxFindingsPerPhoto: Int?

    enum CodingKeys: String, CodingKey {
        case killSwitch = "kill_switch"
        case rolloutMode = "rollout_mode"
        case enabledIOSBuilds = "enabled_ios_builds"
        case minIOSBuild = "min_ios_build"
        case features
        case enableMultiPhotoAnalysis = "enable_multi_photo_analysis"
        case enablePhotoLimitLockedSlotsForFree = "enable_photo_limit_locked_slots_for_free"
        case enablePlusPro5PhotoLimit = "enable_plus_pro_5_photo_limit"
        case enableEditableFindings = "enable_editable_findings"
        case enableManualFindingAdd = "enable_manual_finding_add"
        case maxPhotoCountFree = "max_photo_count_free"
        case maxPhotoCountPlus = "max_photo_count_plus"
        case maxPhotoCountPro = "max_photo_count_pro"
        case maxFindingsPerPhoto = "max_findings_per_photo"
    }
}

private struct BackendFeatureFlags: Decodable {
    let multiPhotoAnalysis: Bool?
    let photoLimitLockedSlotsForFree: Bool?
    let plusPro5PhotoLimit: Bool?
    let editableFindings: Bool?
    let manualFindingAdd: Bool?
    let reportSnapshotV2: Bool?

    enum CodingKeys: String, CodingKey {
        case multiPhotoAnalysis = "multi_photo_analysis"
        case photoLimitLockedSlotsForFree = "photo_limit_locked_slots_for_free"
        case plusPro5PhotoLimit = "plus_pro_5_photo_limit"
        case editableFindings = "editable_findings"
        case manualFindingAdd = "manual_finding_add"
        case reportSnapshotV2 = "report_snapshot_v2"
    }
}

private extension BackendMultiPhotoFlags {
    var isReleaseGateOpenForCurrentBuild: Bool {
        guard killSwitch != true else { return false }
        let build = AppClientMetadata.appBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !build.isEmpty, build != "unknown" else { return false }

        switch (rolloutMode ?? "off").lowercased() {
        case "all":
            return true
        case "build_allowlist":
            let allowed = enabledIOSBuilds ?? []
            if allowed.contains(build) { return true }
            guard let buildNumber = Int(build) else { return false }
            return allowed.compactMap(Int.init).contains(buildNumber)
                || (minIOSBuild.map { buildNumber >= $0 } == true)
        case "min_build":
            guard let buildNumber = Int(build), let minimum = minIOSBuild else { return false }
            return buildNumber >= minimum
        default:
            return false
        }
    }

    var effectiveEnableMultiPhotoAnalysis: Bool {
        isReleaseGateOpenForCurrentBuild && (features?.multiPhotoAnalysis ?? enableMultiPhotoAnalysis ?? false)
    }

    var effectiveEnablePhotoLimitLockedSlotsForFree: Bool {
        isReleaseGateOpenForCurrentBuild && (features?.photoLimitLockedSlotsForFree ?? enablePhotoLimitLockedSlotsForFree ?? false)
    }

    var effectiveEnablePlusPro5PhotoLimit: Bool {
        isReleaseGateOpenForCurrentBuild && (features?.plusPro5PhotoLimit ?? enablePlusPro5PhotoLimit ?? false)
    }

    var effectiveEnableEditableFindings: Bool {
        isReleaseGateOpenForCurrentBuild && (features?.editableFindings ?? enableEditableFindings ?? false)
    }

    var effectiveEnableManualFindingAdd: Bool {
        isReleaseGateOpenForCurrentBuild && (features?.manualFindingAdd ?? enableManualFindingAdd ?? false)
    }
}

private struct BackendFeatureFlagRow: Decodable {
    let value: BackendMultiPhotoFlags
}

struct AppReleasePolicy: Codable, Equatable {
    let minimumSupportedBuild: Int?
    let latestBuild: Int?
    let hardUpdateEnabled: Bool?
    let softUpdateEnabled: Bool?
    let appStoreURLString: String?
    let messageTR: String?
    let messageEN: String?
    let policyVersion: String?

    enum CodingKeys: String, CodingKey {
        case minimumSupportedBuild = "minimum_supported_build"
        case latestBuild = "latest_build"
        case hardUpdateEnabled = "hard_update_enabled"
        case softUpdateEnabled = "soft_update_enabled"
        case appStoreURLString = "app_store_url"
        case messageTR = "message_tr"
        case messageEN = "message_en"
        case policyVersion = "policy_version"
    }

    static let fallback = AppReleasePolicy(
        minimumSupportedBuild: 62,
        latestBuild: 88,
        hardUpdateEnabled: false,
        softUpdateEnabled: false,
        appStoreURLString: RDConfig.Web.appStoreURL.absoluteString,
        messageTR: "Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin.",
        messageEN: "A new version is available. Please update the app to continue.",
        policyVersion: "fallback"
    )

    var appStoreURL: URL {
        URL(string: appStoreURLString ?? "") ?? RDConfig.Web.appStoreURL
    }

    var displayMessage: String {
        let selectedMessage = RDLanguage.current == .english ? messageEN : messageTR
        let trimmed = (selectedMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? RDLocalization.string(
                "localizable.release.update_required",
                fallback: "Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin."
            )
            : trimmed
    }

    var identity: String {
        [
            policyVersion,
            minimumSupportedBuild.map(String.init),
            latestBuild.map(String.init)
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    func requiresHardUpdate(currentBuild: Int?) -> Bool {
        guard hardUpdateEnabled == true,
              let currentBuild,
              let minimumSupportedBuild
        else { return false }
        return currentBuild < minimumSupportedBuild
    }

    func offersSoftUpdate(currentBuild: Int?) -> Bool {
        guard softUpdateEnabled == true,
              let currentBuild,
              let latestBuild
        else { return false }
        return currentBuild < latestBuild
    }
}

private struct AppReleasePolicyResponse: Decodable {
    let ok: Bool?
    let policy: AppReleasePolicy?
}

private struct AppReleasePolicyRequest: Encodable {
    let client_platform: String
    let client_app_version: String
    let client_app_build: String
    let api_contract_version: Int
}

enum AppReleaseUpdateRequirement: Equatable {
    case none
    case soft(AppReleasePolicy)
    case hard(AppReleasePolicy)
}

@MainActor
final class AppState: ObservableObject {
    private static let onboardingCompletedKey = "rd.onboarding.completed"
    private static let darkModeKey = "rd.theme.darkModeEnabled"
    private static let themePreferenceKey = "rd.theme.preference"
    private static let safetyProfilePreferenceKey = "rd.safetyProfile.preference"
    private static let cachedHardReleasePolicyKey = "rd.releasePolicy.cachedHard"
    private static let dismissedSoftReleasePolicyKey = "rd.releasePolicy.dismissedSoft"

    @Published var flow: AppFlow = .splash
    @Published var isPro: Bool = false
    @Published var currentTier: SubscriptionTier = .free
    @Published var planCapabilities: PlanCapabilities = .forTier(.free)
    @Published private(set) var releaseUpdateRequirement: AppReleaseUpdateRequirement = .none
    @Published var profile: UserProfile?
    @Published var activeTab: RDTab = .home
    @Published var pendingProfileDestination: ProfileDestination?
    @Published var pendingAnalysisResultID: UUID?
    @Published var quickScanRequestID = UUID()
    var quickScanSource: QuickScanSource = .chooser
    @Published var hasSeenOnboarding: Bool
    #if DEBUG && NOVA_PILOT_BUILD
    /// True while the Nova pilot funnel is on screen. The funnel keeps running
    /// after the account is created (trial, notification permission), so a new
    /// session must not pull the app to `.main` underneath it.
    @Published var novaPilotOnboardingActive = false
    #endif
    @Published var authError: String?
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var subscriptionState: SubscriptionState = .free
    @Published private(set) var backendSubscriptionState: SubscriptionState = .free
    @Published private(set) var subscriptionPackages: [SubscriptionPlanPackage] = []
    @Published private(set) var subscriptionOfferingsLoadState: SubscriptionOfferingsLoadState = .loading
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
    @Published private(set) var languagePreference: RDLanguagePreference
    @Published private(set) var safetyProfileID: RDSafetyProfileID?

    let auth: AuthService
    let subscriptions: any SubscriptionManaging

    private let backendSubscriptionVerificationDelaysNanoseconds: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        3_000_000_000,
        5_000_000_000
    ]
    private let subscriptionOfferingsRetryDelayNanoseconds: UInt64 = 1_200_000_000
    private var pendingNotificationAnalysisID: UUID?
    private var cancellables = Set<AnyCancellable>()

    init(
        auth: AuthService? = nil,
        subscriptions: (any SubscriptionManaging)? = nil
    ) {
        #if DEBUG
        Self.prepareForUITestLaunchIfNeeded()
        Self.prepareForRealE2ELaunchIfNeeded()
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
        let nativeLanguage = RDLanguage.current
        self.languagePreference = nativeLanguage
        let storedSafetyProfile = UserDefaults.standard
            .string(forKey: Self.safetyProfilePreferenceKey)
            .flatMap(RDSafetyProfileID.init(rawValue:))
        self.safetyProfileID = RDGlobalLocalizationBuildGate.isEnabled
            ? Self.compatibleSafetyProfileID(
                storedSafetyProfile,
                with: nativeLanguage.appLanguage
            )
                ?? (nativeLanguage == .turkish ? .turkeyCurrentV1 : nil)
            : .turkeyCurrentV1
        self.profile = resolved.profile
        self.isAuthenticated = resolved.isAuthenticated
        applyTier(.free)
        self.authError = resolved.lastError
        observeAuth()
        observeSubscriptions()
        observeNotificationRouting()

        #if DEBUG
        let releasePolicyOverridden = applyUITestReleasePolicyOverrideIfNeeded()
        if !releasePolicyOverridden && !Self.isUITestLaunch {
            applyCachedHardReleasePolicyIfNeeded()
            Task { await refreshReleasePolicy() }
        }
        #else
        applyCachedHardReleasePolicyIfNeeded()
        Task { await refreshReleasePolicy() }
        #endif

        #if DEBUG
        if Self.isUITestResetLaunch {
            flow = .onboarding
            Task { await resolved.resetLocalSessionForUITests() }
            return
        }
        if Self.isUITestAuthLaunch {
            hasSeenOnboarding = true
            UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
            flow = .auth
            Task { await resolved.resetLocalSessionForUITests() }
            return
        }
        if Self.isUITestMainLaunch {
            let testTier: SubscriptionTier = Self.isUITestFreeTierLaunch
                ? .free
                : Self.isUITestProTierLaunch
                    ? .pro
                    : .plus
            let testProfile = Self.uiTestProfile(tier: testTier)
            profile = testProfile
            safetyProfileID = testProfile.safetyProfileID
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
        if Self.isRealE2EAnalysisLaunch || Self.isPilotPasswordLoginLaunch {
            Task { await bootstrapDebugPasswordLogin() }
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

        // The splash stays up while a lapsed access token refreshes, so a
        // signed-in user lands in the app rather than in onboarding or login.
        await auth.restoreLapsedSessionIfPossible()

        if auth.isAuthenticated {
            #if DEBUG && NOVA_PILOT_BUILD
            NovaPilotEntryGate.markReturningUser()
            #endif
            async let initialProfileRefresh: Void = auth.refreshProfile()
            async let pendingDraftSync = OnboardingAnswersService.shared.syncPendingDraftIfPossible()
            async let welcomeEmail: Void = sendWelcomeEmailIfPossible()

            await subscriptions.identify(userID: auth.session?.user.id)
            _ = await (initialProfileRefresh, pendingDraftSync, welcomeEmail)

            await loadSubscriptionOfferings(retryOnce: true, identifyUserID: nil)

            await reconcileBackendSubscriptionSnapshot()
            await auth.refreshProfile()
            let backendState = await refreshBackendSubscriptionState()
            applyTier(backendState.tier)
            flow = .main
            routePendingNotificationIfReady(defaultTab: .home)
            routePendingReferralIfReady()
            return
        }

        flow = hasSeenOnboarding ? .auth : .onboarding
    }

    #if DEBUG
    /// Debug/device-pilot helper. Credentials are supplied only to the launch
    /// process and are never compiled into the app bundle. The authenticated
    /// Supabase session then persists through the normal auth storage.
    private func bootstrapDebugPasswordLogin() async {
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)

        if !auth.isAuthenticated {
            let environment = ProcessInfo.processInfo.environment
            let email = environment["RD_E2E_EMAIL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let password = environment["RD_E2E_PASSWORD"] ?? ""
            guard !email.isEmpty, !password.isEmpty else {
                authError = Self.isOSGBPilotBundle ? nil : "Pilot giriş bilgileri eksik."
                flow = .auth
                return
            }

            do {
                try await auth.signInWithPassword(email: email, password: password)
            } catch {
                authError = "Pilot girişi başarısız: \(error.localizedDescription)"
                flow = .auth
                return
            }
        }

        await auth.refreshProfile()
        await subscriptions.identify(userID: auth.session?.user.id)
        let backendState = await refreshBackendSubscriptionState()
        applyTier(backendState.tier)
        await refreshPlanState()
        flow = .main
        routePendingNotificationIfReady(defaultTab: .home)
        routePendingReferralIfReady()
    }
    #endif

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
            routePendingReferralIfReady()
        } else {
            flow = .auth
        }
    }

    /// Auth tarafı zaten signedIn yayınladığında otomatik geçilecek; manuel çağrı
    /// sadece auth tamamlanması sonrası explicit route geçişleri için saklıdır.
    func signIn() {
        flow = .main
        routePendingNotificationIfReady(defaultTab: .home)
        routePendingReferralIfReady()
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
        #if DEBUG
        // Deterministic presentation fixtures. No RevenueCat product IDs are used,
        // so these packages cannot start a real store transaction.
        if Self.isUITestLaunch && CommandLine.arguments.contains("RD_UI_TEST_PAYWALL_PRICES") {
            subscriptionPackages = [.plus, .pro].flatMap { (tier: SubscriptionTier) in
                [SubscriptionPlanPackage(
                    id: "fixture_\(tier.rawValue)_annual", tier: tier, title: tier.title,
                    price: tier == .plus ? "₺2.499,99" : "₺4.999,99",
                    monthlyEquivalentPrice: tier == .plus ? "₺208,33" : "₺416,67",
                    subtitle: "annual", productIdentifier: "fixture_\(tier.rawValue)_annual",
                    priceAmount: tier == .plus ? 2499.99 : 4999.99,
                    introductoryFreeTrialDays: tier == .plus && !CommandLine.arguments.contains("RD_UI_TEST_NO_TRIAL") ? 7 : nil
                ), SubscriptionPlanPackage(
                    id: "fixture_\(tier.rawValue)_monthly", tier: tier, title: tier.title,
                    price: tier == .plus ? "₺249,99" : "₺499,99", monthlyEquivalentPrice: nil,
                    subtitle: "monthly", productIdentifier: "fixture_\(tier.rawValue)_monthly",
                    priceAmount: tier == .plus ? 249.99 : 499.99
                )]
            }
            subscriptionOfferingsLoadState = .loaded
            return
        }
        #endif
        guard let userID = auth.session?.user.id else {
            subscriptionPackages = []
            subscriptionOfferingsLoadState = .failed(RDLocalization.string("localizable.app.state.app.store.fiyatlari.icin.tekrar.giris.yapman.ger.8a6258a3", table: .localizable, fallback: "App Store fiyatları için tekrar giriş yapman gerekiyor."))
            return
        }
        await loadSubscriptionOfferings(retryOnce: true, identifyUserID: userID)
    }

    private func loadSubscriptionOfferings(retryOnce: Bool, identifyUserID: UUID?) async {
        if let identifyUserID {
            await subscriptions.identify(userID: identifyUserID)
        }

        subscriptionOfferingsLoadState = .loading
        await subscriptions.loadOfferings()
        subscriptionPackages = subscriptions.packages
        guard subscriptionPackages.isEmpty else {
            subscriptionOfferingsLoadState = .loaded
            return
        }

        guard retryOnce else {
            subscriptionOfferingsLoadState = .failed(subscriptionOfferingsFailureMessage())
            return
        }

        subscriptionOfferingsLoadState = .retryingOnce
        try? await Task.sleep(nanoseconds: subscriptionOfferingsRetryDelayNanoseconds)
        guard !Task.isCancelled else { return }

        await subscriptions.loadOfferings()
        subscriptionPackages = subscriptions.packages
        subscriptionOfferingsLoadState = subscriptionPackages.isEmpty
            ? .failed(subscriptionOfferingsFailureMessage())
            : .loaded
    }

    private func subscriptionOfferingsFailureMessage() -> String {
        return RDLocalization.string("localizable.app.state.app.store.abonelik.fiyatlari.su.an.alinamadi.int.69c82993", table: .localizable, fallback: "App Store abonelik fiyatları şu an alınamadı. İnternet bağlantını kontrol edip tekrar dene.")
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

    func refreshReleasePolicy() async {
        #if DEBUG
        if Self.isUITestLaunch { return }
        #endif

        let payload = AppReleasePolicyRequest(
            client_platform: AppClientMetadata.platform,
            client_app_version: AppClientMetadata.appVersion,
            client_app_build: AppClientMetadata.appBuild,
            api_contract_version: AppClientMetadata.apiContractVersion
        )

        do {
            let response: AppReleasePolicyResponse = try await SupabaseService.shared.client.functions.invoke(
                RDConfig.appReleasePolicyFunctionName,
                options: FunctionInvokeOptions(body: payload)
            )
            applyReleasePolicy(response.policy ?? .fallback, cacheHardPolicy: true)
        } catch {
            applyCachedHardReleasePolicyIfNeeded()
        }
    }

    func dismissSoftReleaseNotice() {
        guard case let .soft(policy) = releaseUpdateRequirement else { return }
        UserDefaults.standard.set(policy.identity, forKey: Self.dismissedSoftReleasePolicyKey)
        releaseUpdateRequirement = .none
    }

    private func applyReleasePolicy(_ policy: AppReleasePolicy, cacheHardPolicy: Bool) {
        if policy.requiresHardUpdate(currentBuild: currentAppBuildNumber) {
            releaseUpdateRequirement = .hard(policy)
            if cacheHardPolicy {
                cacheHardReleasePolicy(policy)
            }
            return
        }

        clearCachedHardReleasePolicy()
        if policy.offersSoftUpdate(currentBuild: currentAppBuildNumber),
           UserDefaults.standard.string(forKey: Self.dismissedSoftReleasePolicyKey) != policy.identity {
            releaseUpdateRequirement = .soft(policy)
        } else {
            releaseUpdateRequirement = .none
        }
    }

    private func applyCachedHardReleasePolicyIfNeeded() {
        guard let policy = cachedHardReleasePolicy(),
              policy.requiresHardUpdate(currentBuild: currentAppBuildNumber)
        else { return }
        releaseUpdateRequirement = .hard(policy)
    }

    private func cacheHardReleasePolicy(_ policy: AppReleasePolicy) {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        UserDefaults.standard.set(data, forKey: Self.cachedHardReleasePolicyKey)
    }

    private func cachedHardReleasePolicy() -> AppReleasePolicy? {
        guard let data = UserDefaults.standard.data(forKey: Self.cachedHardReleasePolicyKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AppReleasePolicy.self, from: data)
    }

    private func clearCachedHardReleasePolicy() {
        UserDefaults.standard.removeObject(forKey: Self.cachedHardReleasePolicyKey)
    }

    private var currentAppBuildNumber: Int? {
        Int(AppClientMetadata.appBuild.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    #if DEBUG
    @discardableResult
    private func applyUITestReleasePolicyOverrideIfNeeded() -> Bool {
        if CommandLine.arguments.contains("RD_UI_TEST_FORCE_HARD_UPDATE")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_FORCE_HARD_UPDATE"] == "1" {
            let nextBuild = (currentAppBuildNumber ?? 63) + 1
            releaseUpdateRequirement = .hard(
                AppReleasePolicy(
                    minimumSupportedBuild: nextBuild,
                    latestBuild: nextBuild,
                    hardUpdateEnabled: true,
                    softUpdateEnabled: false,
                    appStoreURLString: RDConfig.Web.appStoreURL.absoluteString,
                    messageTR: "Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin.",
                    messageEN: "A new version is available. Please update the app to continue.",
                    policyVersion: "ui-test-hard"
                )
            )
            return true
        }

        if CommandLine.arguments.contains("RD_UI_TEST_FORCE_SOFT_UPDATE")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_FORCE_SOFT_UPDATE"] == "1" {
            let nextBuild = (currentAppBuildNumber ?? 63) + 1
            releaseUpdateRequirement = .soft(
                AppReleasePolicy(
                    minimumSupportedBuild: currentAppBuildNumber ?? 1,
                    latestBuild: nextBuild,
                    hardUpdateEnabled: false,
                    softUpdateEnabled: true,
                    appStoreURLString: RDConfig.Web.appStoreURL.absoluteString,
                    messageTR: "Yeni sürüm hazır. Uygulamayı güncel tutarak son geliştirmeleri kullanabilirsin.",
                    messageEN: "A new version is ready.",
                    policyVersion: "ui-test-soft"
                )
            )
            return true
        }

        return false
    }
    #endif

    @discardableResult
    func purchaseSubscription(packageID: String, expectedTier: SubscriptionTier? = nil) async throws -> SubscriptionState {
        try RDLegalReleaseGate.requireAuthAndPurchaseAccess()
        guard let userID = auth.session?.user.id else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("localizable.app.state.abonelik.baslatmadan.once.tekrar.giris.yapman.ge.c8b96341", table: .localizable, fallback: "Abonelik başlatmadan önce tekrar giriş yapman gerekiyor.")]
            )
        }
        await subscriptions.identify(userID: userID)
        let purchasedState = try await subscriptions.purchase(packageID: packageID)
        let assertedTier = expectedTier ?? purchasedState.tier
        guard purchasedState.tier == assertedTier else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.format("localizable.app.state.abonelik.dogrulanamadi.secilen.plan.1.dogrulanan.41b085b6", table: .localizable, fallback: "Abonelik doğrulanamadı. Seçilen plan %1$@, doğrulanan plan %2$@.", arguments: [String(describing: assertedTier.title), String(describing: purchasedState.tier.title)])]
            )
        }
        let backendState = try await syncBackendSubscriptionWithRetry(expectedTier: assertedTier)
        await auth.refreshProfile()
        backendSubscriptionState = backendState
        guard backendState.tier == assertedTier else {
            throw NSError(
                domain: "RiskDetected.Subscription",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("localizable.app.state.abonelik.backend.tarafinda.dogrulanamadi.lutfen..e6a38fc9", table: .localizable, fallback: "Abonelik backend tarafında doğrulanamadı. Lütfen birkaç saniye sonra tekrar dene veya satın alımları geri yükle.")]
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
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("localizable.app.state.satin.alimlari.geri.yuklemek.icin.tekrar.giris.y.a153de84", table: .localizable, fallback: "Satın alımları geri yüklemek için tekrar giriş yapman gerekiyor.")]
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

    var activeSafetyProfile: RDSafetyProfileDefinition? {
        guard RDGlobalLocalizationBuildGate.isEnabled else {
            return RDSafetyProfileCatalog.profile(id: .turkeyCurrentV1)
        }
        return safetyProfileID.map(RDSafetyProfileCatalog.profile(id:))
    }

    private static func compatibleSafetyProfileID(
        _ profileID: RDSafetyProfileID?,
        with appLanguage: RDAppLanguage
    ) -> RDSafetyProfileID? {
        guard let profileID else { return nil }
        let definition = RDSafetyProfileCatalog.profile(id: profileID)
        return definition.language == appLanguage ? profileID : nil
    }

    /// Keeps onboarding selection explicit, while giving users who enter
    /// through the standalone auth flow a deterministic terminology profile.
    private func ensureAuthenticatedSafetyProfileDefaultIfNeeded() {
        guard RDGlobalLocalizationBuildGate.isEnabled,
              isAuthenticated,
              flow != .onboarding || hasSeenOnboarding
        else {
            return
        }

        let appLanguage = languagePreference.appLanguage
        if Self.compatibleSafetyProfileID(
            safetyProfileID,
            with: appLanguage
        ) != nil {
            return
        }

        let fallback: RDSafetyProfileID = appLanguage == .english
            ? RDSafetyProfileCatalog.englishFallbackProfileID
            : RDSafetyProfileCatalog.defaultProfileID
        safetyProfileID = fallback
        UserDefaults.standard.set(
            fallback.rawValue,
            forKey: Self.safetyProfilePreferenceKey
        )
    }

    var requiresExplicitSafetyProfileSelection: Bool {
        RDGlobalLocalizationBuildGate.isEnabled
            && languagePreference == .english
            && safetyProfileID == nil
    }

    var legislationCanvasEnabled: Bool {
        activeSafetyProfile?.legislationCanvasEnabled
            ?? (languagePreference == .turkish)
    }

    var localizationRequestForNewAnalysis: RDAnalysisLocalizationRequest? {
        guard RDGlobalLocalizationBuildGate.isEnabled else { return nil }
        guard let safetyProfile = activeSafetyProfile else { return nil }
        let preferred = profile?.preferredMethod?.localizationMethod
        let method = preferred.flatMap {
            safetyProfile.allowedRiskMethods.contains($0) ? $0 : nil
        } ?? safetyProfile.defaultRiskMethod
        return RDAnalysisLocalizationRequest(
            outputLanguage: safetyProfile.language,
            outputLocale: safetyProfile.contentLocale,
            workJurisdictionCountry: safetyProfile.jurisdictionCountry,
            workJurisdictionRegion: profile?.workJurisdictionRegion,
            safetyProfileID: safetyProfile.id,
            safetyProfileVersion: safetyProfile.profileVersion,
            method: method
        )
    }

    func setSafetyProfile(_ profileID: RDSafetyProfileID) {
        guard RDGlobalLocalizationBuildGate.isEnabled
                || profileID == .turkeyCurrentV1
        else {
            return
        }
        guard RDSafetyProfileCatalog.profile(id: profileID).language
                == languagePreference.appLanguage
        else {
            return
        }
        safetyProfileID = profileID
        UserDefaults.standard.set(
            profileID.rawValue,
            forKey: Self.safetyProfilePreferenceKey
        )
        Task { await syncLocalizationPreferences() }
    }

    /// Re-reads the native per-app language chosen in iOS Settings.
    func refreshNativeLanguageContext() async {
        let nativeLanguage = RDLanguage.current
        if languagePreference != nativeLanguage {
            languagePreference = nativeLanguage
        }
        await syncLocalizationPreferences()
    }

    private func syncLocalizationPreferences() async {
        guard RDGlobalLocalizationBuildGate.isEnabled,
              auth.isAuthenticated
        else {
            return
        }
        ensureAuthenticatedSafetyProfileDefaultIfNeeded()
        do {
            try await auth.updateLocalizationPreferences(
                appLanguage: languagePreference.appLanguage,
                safetyProfileID: safetyProfileID,
                workJurisdictionRegion: profile?.workJurisdictionRegion
            )
        } catch {
            #if DEBUG
            print("Localization preference sync failed: \(error.localizedDescription)")
            #endif
        }
    }

    #if DEBUG
    private static var isUITestResetLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_RESET_STATE")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_RESET_STATE"] == "1"
            || CommandLine.arguments.contains("RD_PREVIEW_ONBOARDING_LOADING")
            || ProcessInfo.processInfo.environment["RD_PREVIEW_ONBOARDING_LOADING"] == "1"
    }

    private static var isUITestMainLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_MAIN")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_MAIN"] == "1"
    }

    private static var isUITestAuthLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_AUTH")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_AUTH"] == "1"
    }

    private static var isUITestFreeTierLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_FREE_TIER")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_FREE_TIER"] == "1"
    }

    private static var isUITestProTierLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_PRO_TIER")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_PRO_TIER"] == "1"
    }

    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
    }

    private static var isRealE2EAnalysisLaunch: Bool {
        CommandLine.arguments.contains("RD_E2E_REAL_3_PHOTO_ANALYSIS")
            || ProcessInfo.processInfo.environment["RD_E2E_REAL_3_PHOTO_ANALYSIS"] == "1"
    }

    private static var isPilotPasswordLoginLaunch: Bool {
        isOSGBPilotBundle
            || CommandLine.arguments.contains("RD_PILOT_PASSWORD_LOGIN")
            || ProcessInfo.processInfo.environment["RD_PILOT_PASSWORD_LOGIN"] == "1"
    }

    /// The dedicated staging pilot must remain usable after a normal icon
    /// launch. Launch-process credentials are still supported for automation,
    /// while people signing in on the device use the scoped password screen.
    private static var isOSGBPilotBundle: Bool {
        Bundle.main.bundleIdentifier == "com.riskdetected.app.osgbpilot"
    }

    private static func prepareForUITestLaunchIfNeeded() {
        guard isUITestResetLaunch || isUITestAuthLaunch || isUITestMainLaunch else { return }
        let defaults = UserDefaults.standard
        if isUITestResetLaunch {
            [
                onboardingCompletedKey,
                "rd.onboarding.v2.pendingAnswers",
                "rd.theme.darkModeEnabled",
                "rd.theme.preference",
                "rd.language.preference",
                safetyProfilePreferenceKey,
                "rd.paywall.funnelSessionID",
                cachedHardReleasePolicyKey,
                dismissedSoftReleasePolicyKey,
            ].forEach { defaults.removeObject(forKey: $0) }
        }

        if CommandLine.arguments.contains("RD_UI_TEST_DARK_MODE")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_DARK_MODE"] == "1" {
            defaults.set(RDThemePreference.dark.rawValue, forKey: themePreferenceKey)
        } else if CommandLine.arguments.contains("RD_UI_TEST_LIGHT_MODE")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_LIGHT_MODE"] == "1" {
            defaults.set(RDThemePreference.light.rawValue, forKey: themePreferenceKey)
        }
    }

    private static func prepareForRealE2ELaunchIfNeeded() {
        guard isRealE2EAnalysisLaunch else { return }
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
    }

    private static func uiTestProfile(tier: SubscriptionTier = .plus) -> UserProfile {
        let isEnglish = RDLanguage.current == .english
        let requestedProfileID = ProcessInfo.processInfo.environment[
            "RD_UI_TEST_SAFETY_PROFILE_ID"
        ].flatMap(RDSafetyProfileID.init(rawValue:))
        let defaultProfileID: RDSafetyProfileID = isEnglish
            ? .englishInternationalGenericV1
            : .turkeyCurrentV1
        let requestedProfile = requestedProfileID.map(
            RDSafetyProfileCatalog.profile(id:)
        )
        let expectedLanguage: RDAppLanguage = isEnglish ? .english : .turkish
        let safetyProfile: RDSafetyProfileDefinition
        if let requestedProfile,
           requestedProfile.language == expectedLanguage {
            safetyProfile = requestedProfile
        } else {
            safetyProfile = RDSafetyProfileCatalog.profile(id: defaultProfileID)
        }
        return UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000f201")!,
            email: "ui-test@riskdetected.app",
            fullName: isEnglish ? "UI Test User" : "UI Test Kullanıcı",
            initials: "UT",
            title: isEnglish
                ? "Safety professional"
                : RDLocalization.string("localizable.app.state.isg.uzmani.a.sinifi.299d0687", table: .localizable, fallback: "İSG Uzmanı · A Sınıfı"),
            certificateNumber: "UI-TEST-001",
            companyName: isEnglish
                ? "RiskDetected Test Company"
                : "RiskDetected Test Firma",
            companyLogoURL: nil,
            avatarURL: nil,
            phone: isEnglish ? "Test profile" : "Test profil",
            tier: tier,
            preferredMethod: .fineKinney,
            dailyQuotaUsed: 0,
            dailyQuotaResetAt: nil,
            subscriptionPeriod: "monthly",
            subscriptionRenewalAt: nil,
            appLanguage: safetyProfile.language,
            preferredContentLocale: safetyProfile.contentLocale,
            workJurisdictionCountry: safetyProfile.jurisdictionCountry,
            workJurisdictionRegion: nil,
            safetyProfileID: safetyProfile.id,
            safetyProfileVersion: safetyProfile.profileVersion,
            legalDocumentSetID: isEnglish ? .englishGlobalV1 : .turkeyCurrent,
            firstSeenDeviceRegionCode: nil,
            firstSeenDeviceRegionAt: nil,
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
                if let profileID = newProfile?.safetyProfileID {
                    if self.flow == .onboarding,
                       Self.compatibleSafetyProfileID(
                           self.safetyProfileID,
                           with: self.languagePreference.appLanguage
                       ) != nil {
                        return
                    }
                    let effectiveProfileID =
                        RDGlobalLocalizationBuildGate.isEnabled
                        ? Self.compatibleSafetyProfileID(
                            profileID,
                            with: self.languagePreference.appLanguage
                        )
                        : .turkeyCurrentV1
                    guard let effectiveProfileID else { return }
                    self.safetyProfileID = effectiveProfileID
                    UserDefaults.standard.set(
                        effectiveProfileID.rawValue,
                        forKey: Self.safetyProfilePreferenceKey
                    )
                }
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
                    self.ensureAuthenticatedSafetyProfileDefaultIfNeeded()
                    NotificationService.shared.prepareForAuthenticatedUser(session.user.id)
                    Task {
                        await LegalAcceptanceService.shared
                            .recordLoginNoticeAcceptanceIfNeeded(userID: session.user.id)
                        await NotificationService.shared.refreshSettings()
                        NotificationService.shared.syncCurrentTokenIfPossible()
                        await self.subscriptions.identify(userID: session.user.id)
                        // A synced onboarding draft can rename the profile; show the new name.
                        let hadDraft = OnboardingAnswersService.shared.pendingDraft() != nil
                        if await OnboardingAnswersService.shared.syncPendingDraftIfPossible(), hadDraft {
                            await self.auth.refreshProfile()
                        }
                        await self.syncLocalizationPreferences()
                        await self.refreshPlanState()
                        await self.sendWelcomeEmailIfPossible()
                    }
                    #if DEBUG && NOVA_PILOT_BUILD
                    // Only a sign-up the funnel itself started keeps the user in
                    // the funnel; any other session is a returning user.
                    if self.novaPilotOnboardingActive { return }
                    NovaPilotEntryGate.markReturningUser()
                    #else
                    if self.flow == .onboarding && !self.hasSeenOnboarding {
                        return
                    }
                    #endif
                    if self.flow != .main {
                        self.flow = .main
                    }
                    self.routePendingNotificationIfReady(defaultTab: .home)
                    self.routePendingReferralIfReady()
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

        NotificationService.shared.$pendingOpenNewAnalysis
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldOpen in
                guard let self, shouldOpen else { return }
                self.activeTab = .home
                if self.flow == .main, self.auth.isAuthenticated {
                    self.requestQuickScan(source: .chooser)
                    NotificationService.shared.pendingOpenNewAnalysis = false
                }
            }
            .store(in: &cancellables)
    }

    private func routePendingReferralIfReady() {
        guard flow == .main,
              isAuthenticated,
              ReferralDeepLinkStore.shared.pendingCode != nil
        else { return }
        requestProfileDestination(.referral)
    }

    private func routePendingNotificationIfReady(defaultTab: RDTab? = nil) {
        guard flow == .main, auth.isAuthenticated else {
            if let defaultTab, pendingNotificationAnalysisID == nil {
                activeTab = defaultTab
            }
            return
        }
        if NotificationService.shared.pendingOpenNewAnalysis {
            activeTab = .home
            requestQuickScan(source: .chooser)
            NotificationService.shared.pendingOpenNewAnalysis = false
            return
        }
        if let analysisID = pendingNotificationAnalysisID {
            pendingAnalysisResultID = analysisID
            activeTab = .home
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
                guard let self else { return }
                self.subscriptionPackages = packages
                if !packages.isEmpty {
                    self.subscriptionOfferingsLoadState = .loaded
                }
            }
            .store(in: &cancellables)
    }

    private func applyTier(_ tier: SubscriptionTier) {
        currentTier = tier
        planCapabilities = PlanCapabilities.forTier(tier)
        isPro = tier == .pro
        Task { [weak self] in
            await self?.refreshRemotePlanCapabilities(for: tier)
        }
    }

    private func refreshRemotePlanCapabilities(for tier: SubscriptionTier) async {
        #if DEBUG
        if Self.isUITestMainLaunch {
            planCapabilities = PlanCapabilities.forTier(tier).applyingPhotoRules(
                maxPhotosPerAnalysis: tier.isPaid ? 3 : 1,
                visiblePhotoSlotsInUI: 3,
                maxFindingsPerPhoto: 13,
                maxFindingsPerAnalysis: tier.isPaid ? 39 : 12,
                canUseMultiPhotoAnalysis: tier.isPaid,
                canEditAIFindings: true,
                canAddManualFindings: false
            )
            return
        }
        #endif

        guard auth.session != nil else { return }
        guard let remoteCapabilities = await loadRemotePlanCapabilities(for: tier) else { return }
        guard currentTier == tier else { return }
        planCapabilities = remoteCapabilities
    }

    private func loadRemotePlanCapabilities(for tier: SubscriptionTier) async -> PlanCapabilities? {
        do {
            let rules: [BackendPlanCapabilityRuleRow] = try await SupabaseService.shared.client
                .from("plan_capability_rules")
                .select("max_photos_per_analysis,visible_photo_slots_in_ui,max_findings_per_photo,max_findings_per_analysis,can_use_multi_photo_analysis,can_edit_ai_findings,can_add_manual_findings")
                .eq("plan", value: tier.rawValue)
                .limit(1)
                .execute()
                .value

            let flagsResult: [BackendFeatureFlagRow] = try await SupabaseService.shared.client
                .from("app_feature_flags")
                .select("value")
                .eq("key", value: "multi_photo_analysis")
                .limit(1)
                .execute()
                .value

            guard let rule = rules.first, let flags = flagsResult.first?.value else {
                return nil
            }

            let base = PlanCapabilities.forTier(tier)
            let paidMultiPhotoEnabled = tier.isPaid
                && flags.effectiveEnableMultiPhotoAnalysis
                && flags.effectiveEnablePlusPro5PhotoLimit
            let flagPhotoLimit: Int = {
                switch tier {
                case .free: return flags.maxPhotoCountFree ?? 1
                case .plus: return flags.maxPhotoCountPlus ?? 1
                case .pro: return flags.maxPhotoCountPro ?? 1
                }
            }()
            let resolvedMaxPhotos = tier.isPaid
                ? (paidMultiPhotoEnabled ? min(rule.maxPhotosPerAnalysis ?? 1, flagPhotoLimit) : 1)
                : min(rule.maxPhotosPerAnalysis ?? 1, flags.maxPhotoCountFree ?? 1)
            let resolvedMaxFindingsPerPhoto = min(
                rule.maxFindingsPerPhoto ?? 12,
                flags.maxFindingsPerPhoto ?? 12
            )
            let resolvedMaxFindingsTotal = min(
                rule.maxFindingsPerAnalysis ?? resolvedMaxFindingsPerPhoto,
                max(1, resolvedMaxPhotos) * max(1, resolvedMaxFindingsPerPhoto)
            )
            let shouldShowPhotoSlots = paidMultiPhotoEnabled
                || (tier == .free && flags.effectiveEnablePhotoLimitLockedSlotsForFree)

            return base.applyingPhotoRules(
                maxPhotosPerAnalysis: resolvedMaxPhotos,
                visiblePhotoSlotsInUI: shouldShowPhotoSlots ? (rule.visiblePhotoSlotsInUI ?? 5) : 1,
                maxFindingsPerPhoto: resolvedMaxFindingsPerPhoto,
                maxFindingsPerAnalysis: resolvedMaxFindingsTotal,
                canUseMultiPhotoAnalysis: paidMultiPhotoEnabled && rule.canUseMultiPhotoAnalysis == true,
                canEditAIFindings: flags.effectiveEnableEditableFindings && rule.canEditAIFindings == true,
                canAddManualFindings: flags.effectiveEnableManualFindingAdd && rule.canAddManualFindings == true
            )
        } catch {
            return nil
        }
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
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("localizable.app.state.abonelik.dogrulamasi.icin.tekrar.giris.yapman.ge.928cbfae", table: .localizable, fallback: "Abonelik doğrulaması için tekrar giriş yapman gerekiyor.")]
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
                userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("localizable.app.state.abonelik.dogrulama.yaniti.okunamadi.bd64dc5e", table: .localizable, fallback: "Abonelik doğrulama yanıtı okunamadı.")]
            )
        }
        guard tier == expectedTier || (!expectedTier.isPaid && !tier.isPaid) else {
            let message: String
            if expectedTier.isPaid && !tier.isPaid {
                message = RDLocalization.format("localizable.app.state.app.store.hesabinda.1.aboneligi.gorunuyor.ancak..43b3d4a8", table: .localizable, fallback: "App Store hesabında %1$@ aboneliği görünüyor, ancak RevenueCat backend doğrulaması henüz ücretli plan döndürmüyor. Güvenlik için plan açılmadı; abonelik RevenueCat/Supabase tarafında eşleşince otomatik açılır.", arguments: [String(describing: expectedTier.title)])
            } else {
                message = RDLocalization.format("localizable.app.state.abonelik.dogrulanamadi.secilen.plan.1.backend.pl.b6752557", table: .localizable, fallback: "Abonelik doğrulanamadı. Seçilen plan %1$@, backend planı %2$@.", arguments: [String(describing: expectedTier.title), String(describing: tier.title)])
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
        let message = nsError.localizedDescription.lowercased(with: .autoupdatingCurrent)
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
