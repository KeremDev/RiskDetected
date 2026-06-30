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
        latestBuild: 74,
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
        let trimmed = (messageTR ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin."
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
    private static let languagePreferenceKey = "rd.language.preference"
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
        if Self.isRealE2EAnalysisLaunch {
            Task { await bootstrapRealE2EAnalysis() }
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

            await loadSubscriptionOfferings(retryOnce: true, identifyUserID: nil)

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

    #if DEBUG
    private func bootstrapRealE2EAnalysis() async {
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)

        if !auth.isAuthenticated {
            let environment = ProcessInfo.processInfo.environment
            let email = environment["RD_E2E_EMAIL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let password = environment["RD_E2E_PASSWORD"] ?? ""
            guard !email.isEmpty, !password.isEmpty else {
                authError = "RD_E2E_EMAIL ve RD_E2E_PASSWORD olmadan gerçek E2E login başlatılamaz."
                flow = .auth
                return
            }

            do {
                try await auth.signInWithPassword(email: email, password: password)
            } catch {
                authError = "Gerçek E2E login başarısız: \(error.localizedDescription)"
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
            subscriptionOfferingsLoadState = .failed("App Store fiyatları için tekrar giriş yapman gerekiyor.")
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
        return "App Store abonelik fiyatları şu an alınamadı. İnternet bağlantını kontrol edip tekrar dene."
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

    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
    }

    private static var isRealE2EAnalysisLaunch: Bool {
        CommandLine.arguments.contains("RD_E2E_REAL_5_PHOTO_ANALYSIS")
            || ProcessInfo.processInfo.environment["RD_E2E_REAL_5_PHOTO_ANALYSIS"] == "1"
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
                cachedHardReleasePolicyKey,
                dismissedSoftReleasePolicyKey,
            ].forEach { defaults.removeObject(forKey: $0) }
        }

        if CommandLine.arguments.contains("RD_UI_TEST_DARK_MODE")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_DARK_MODE"] == "1" {
            defaults.set(RDThemePreference.dark.rawValue, forKey: themePreferenceKey)
        }
    }

    private static func prepareForRealE2ELaunchIfNeeded() {
        guard isRealE2EAnalysisLaunch else { return }
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
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
                maxPhotosPerAnalysis: tier.isPaid ? 5 : 1,
                visiblePhotoSlotsInUI: 5,
                maxFindingsPerPhoto: 12,
                maxFindingsPerAnalysis: tier.isPaid ? 60 : 12,
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
