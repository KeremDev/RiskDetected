import Foundation
import SwiftUI
import UIKit
import UserNotifications
import Supabase
import OSLog

enum NotificationSettingsLoadState: Equatable {
    case loading
    case loaded
    case failed
}

@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastError: String?
    @Published private(set) var lastDeviceToken: String?
    @Published private(set) var isRegistering = false
    @Published private(set) var settingsLoadState: NotificationSettingsLoadState = .loading
    @Published private var notificationPreferences: NotificationPreferencesRow?
    @Published var pendingAnalysisHistoryID: UUID?
    @Published var pendingDestinationTab: RDTab?
    @Published var pendingOpenNewAnalysis = false
    @Published var pendingOpenNotebook = false

    var isLoadingSettings: Bool {
        settingsLoadState == .loading
    }

    var settingsLoadFailed: Bool {
        settingsLoadState == .failed
    }

    var systemAuthorizationGranted: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    var notificationsEnabled: Bool {
        systemAuthorizationGranted && (notificationPreferences?.enabled ?? false)
    }

    var appRemindersEnabled: Bool {
        notificationsEnabled && (notificationPreferences?.appReminders ?? false)
    }

    /// Stable, random per-install identity used to bind a personal reminder to
    /// exactly one server-push registration. It is intentionally not a user or
    /// vendor identifier and a reinstall receives a fresh value.
    var serverPushInstallationID: UUID {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.installationIDKey),
           let value = UUID(uuidString: raw) {
            return value
        }
        let value = UUID()
        defaults.set(value.uuidString.lowercased(), forKey: Self.installationIDKey)
        return value
    }

    enum ProgressPreference {
        case weeklySummary
        case monthlySummary
        case milestones

        fileprivate var columnName: String {
            switch self {
            case .weeklySummary: return "progress_weekly_summary"
            case .monthlySummary: return "progress_monthly_summary"
            case .milestones: return "progress_milestones"
            }
        }
    }

    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "NotificationService")
    private static let installationIDKey = "rd.notification.installation_id"
    private let supabase = SupabaseService.shared
    private var settingsRefreshGeneration = 0
    private var preferencesUserID: UUID?

    private override init() {
        super.init()
    }

    func configure() {
        #if DEBUG
        guard !Self.isUITestLaunch else { return }
        #endif
        UNUserNotificationCenter.current().delegate = self
        Task {
            await refreshSettings()
            await syncEngagementStateIfNeeded()
            syncCurrentTokenIfPossible()
        }
    }

    func refreshSettings() async {
        settingsRefreshGeneration &+= 1
        let generation = settingsRefreshGeneration
        settingsLoadState = .loading

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard generation == settingsRefreshGeneration else { return }
        authorizationStatus = settings.authorizationStatus
        if let token = lastDeviceToken { await syncISGDevicePermission(token) }
        let preferencesLoaded = await refreshPreferences()
        guard generation == settingsRefreshGeneration else { return }
        settingsLoadState = preferencesLoaded ? .loaded : .failed
    }

    func prepareForAuthenticatedUser(_ userID: UUID) {
        guard preferencesUserID != userID else { return }
        settingsRefreshGeneration &+= 1
        notificationPreferences = nil
        settingsLoadState = .loading
    }

    func requestPermissionAndRegister() {
        guard !isRegistering else { return }
        isRegistering = true
        lastError = nil

        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                )
                await refreshSettings()

                guard granted else {
                    await syncEngagementStateIfNeeded(force: true)
                    isRegistering = false
                    return
                }

                try await setMasterPreference(enabled: true)
                await syncEngagementStateIfNeeded(force: true)
                UIApplication.shared.registerForRemoteNotifications()
            } catch {
                Self.logger.error("Notification authorization failed error=\(error.localizedDescription, privacy: .public)")
                lastError = RDLocalization.string("notifications.notification.service.bildirim.izni.alinamadi.lutfen.cihaz.ayarlarinda.acfcc568", table: .notifications, fallback: "Bildirim izni alınamadı. Lütfen cihaz ayarlarından tekrar dene.")
                isRegistering = false
            }
        }
    }

    func requestPermissionAndRegisterFromOnboarding() async {
        guard !Self.isUITestLaunch else {
            await refreshSettings()
            return
        }
        guard !isRegistering else { return }
        isRegistering = true
        lastError = nil

        do {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationStatus = settings.authorizationStatus

            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                )
                await refreshSettings()

                guard granted else {
                    await syncEngagementStateIfNeeded(force: true)
                    isRegistering = false
                    return
                }

                try? await setMasterPreference(enabled: true)
                await syncEngagementStateIfNeeded(force: true)
                UIApplication.shared.registerForRemoteNotifications()

            case .authorized, .provisional, .ephemeral:
                await refreshSettings()
                try? await setMasterPreference(enabled: true)
                await syncEngagementStateIfNeeded(force: true)
                UIApplication.shared.registerForRemoteNotifications()

            case .denied:
                await refreshSettings()
                await syncEngagementStateIfNeeded(force: true)
                isRegistering = false

            @unknown default:
                await refreshSettings()
                isRegistering = false
            }
        } catch {
            Self.logger.error("Onboarding notification authorization failed error=\(error.localizedDescription, privacy: .public)")
            await refreshSettings()
            isRegistering = false
        }
    }

    func disableNotifications() {
        lastError = nil
        Task {
            do {
                try await setMasterPreference(enabled: false)
                await refreshSettings()
            } catch {
                Self.logger.error("Notification preference disable failed error=\(error.localizedDescription, privacy: .public)")
                lastError = RDLocalization.string("notifications.notification.service.bildirim.tercihi.kaydedilemedi.0a3438da", table: .notifications, fallback: "Bildirim tercihi kaydedilemedi.")
            }
        }
    }

    func enableNotifications() {
        guard !isRegistering else { return }
        isRegistering = true
        lastError = nil

        Task {
            do {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                authorizationStatus = settings.authorizationStatus

                switch settings.authorizationStatus {
                case .notDetermined:
                    let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .badge, .sound]
                    )
                    guard granted else {
                        await refreshSettings()
                        await syncEngagementStateIfNeeded(force: true)
                        isRegistering = false
                        return
                    }
                case .authorized, .provisional, .ephemeral:
                    break
                case .denied:
                    await refreshSettings()
                    isRegistering = false
                    return
                @unknown default:
                    await refreshSettings()
                    isRegistering = false
                    return
                }

                try await setMasterPreference(enabled: true)
                await refreshSettings()
                await syncEngagementStateIfNeeded(force: true)
                UIApplication.shared.registerForRemoteNotifications()
                isRegistering = false
            } catch {
                Self.logger.error("Notification preference enable failed error=\(error.localizedDescription, privacy: .public)")
                lastError = RDLocalization.string("notifications.notification.service.bildirim.tercihi.acilmadi.lutfen.tekrar.dene.f4d3fae0", table: .notifications, fallback: "Bildirim tercihi açılmadı. Lütfen tekrar dene.")
                await refreshSettings()
                isRegistering = false
            }
        }
    }

    func syncCurrentTokenIfPossible() {
        guard supabase.currentUserID != nil else {
            Self.logger.info("Push token sync skipped reason=no_user")
            return
        }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            Self.logger.info("Push token sync skipped reason=not_authorized status=\(self.authorizationStatus.rawValue, privacy: .public)")
            return
        }
        Self.logger.info("Push token sync requested")
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleAppBecameActive() async {
        await refreshSettings()
        await syncEngagementStateIfNeeded()
        syncCurrentTokenIfPossible()
    }

    private func syncEngagementStateIfNeeded(force: Bool = false) async {
        guard let userID = supabase.currentUserID else { return }
        let authorizationValue = authorizationStatus.backendValue
        let timezone = TimeZone.current.identifier
        let syncSignature = "\(timezone)|\(authorizationValue)"
        let defaults = UserDefaults.standard
        let timestampKey = "rd.notification.engagement.lastSync.\(userID.uuidString)"
        let signatureKey = "rd.notification.engagement.signature.\(userID.uuidString)"
        let lastSync = defaults.object(forKey: timestampKey) as? Date
        let signatureChanged = defaults.string(forKey: signatureKey) != syncSignature

        if !force,
           !signatureChanged,
           let lastSync,
           Date().timeIntervalSince(lastSync) < 6 * 60 * 60 {
            return
        }

        let payload = EngagementStatePayload(
            timezone: timezone,
            locale: Locale.current.identifier,
            authorizationStatus: authorizationValue,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )

        do {
            try await supabase.client
                .rpc("record_user_engagement_state_v1", params: payload)
                .execute()
            defaults.set(Date(), forKey: timestampKey)
            defaults.set(syncSignature, forKey: signatureKey)
        } catch {
            Self.logger.warning("Engagement heartbeat failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordNotificationOpen(eventID: UUID?) async {
        guard let eventID, supabase.currentUserID != nil else { return }
        do {
            try await supabase.client
                .rpc(
                    "record_notification_open_v1",
                    params: NotificationOpenPayload(notificationEventID: eventID.uuidString)
                )
                .execute()
        } catch {
            Self.logger.warning("Notification open tracking failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            lastDeviceToken = token
            do {
                try await saveDeviceToken(token)
                Self.logger.info("Device token saved environment=\(PushEnvironment.current, privacy: .public)")
                isRegistering = false
            } catch {
                Self.logger.error("Device token save failed error=\(error.localizedDescription, privacy: .public)")
                lastError = RDLocalization.string("notifications.notification.service.bildirim.cihaz.kaydi.tamamlanamadi.cfa13bd9", table: .notifications, fallback: "Bildirim cihaz kaydı tamamlanamadı.")
                isRegistering = false
            }
        }
    }

    nonisolated func didFailToRegisterForRemoteNotifications(error: Error) {
        Task { @MainActor in
            Self.logger.error("APNs registration failed error=\(error.localizedDescription, privacy: .public)")
            lastError = RDLocalization.string("notifications.notification.service.bildirim.cihaz.kaydi.alinamadi.simulatorde.veya..dc4985f5", table: .notifications, fallback: "Bildirim cihaz kaydı alınamadı. Simülatörde veya imza ayarlarında APNs desteklenmeyebilir.")
            isRegistering = false
        }
    }

    private func saveDeviceToken(_ token: String) async throws {
        guard let userID = supabase.currentUserID else { return }
        let preferenceAllowsNotifications = notificationPreferences?.enabled ?? false
        let payload = PushDeviceTokenPayload(
            userID: userID.uuidString,
            token: token,
            platform: "ios",
            environment: PushEnvironment.current,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            deviceModel: UIDevice.current.model,
            notificationsEnabled: preferenceAllowsNotifications,
            lastRegisteredAt: ISO8601DateFormatter().string(from: Date()),
            provider: "apns",
            applicationID: Bundle.main.bundleIdentifier,
            installationID: serverPushInstallationID.uuidString.lowercased(),
            clientBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )

        try await supabase.client
            .from("push_device_tokens")
            .upsert(payload, onConflict: "user_id,provider,application_id,installation_id")
            .execute()
        await syncISGDevicePermission(token)
    }

    // Additive capability sync: unavailable/disabled P12 must not break legacy
    // APNs registration. Permission is per token, never the platform heartbeat.
    private func syncISGDevicePermission(_ token: String) async {
        guard supabase.currentUserID != nil,
              let rawBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              let build = Int32(rawBuild), build > 0 else { return }
        do {
            try await supabase.client.rpc("isg_notification_device_permission_v1", params:
                ISGDevicePermissionPayload(token: token, provider: "apns", build: build,
                    authorized: authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral))
                .execute()
        } catch {
            Self.logger.debug("ISG device permission sync unavailable; legacy registration preserved")
        }
    }

    private func setMasterPreference(enabled: Bool) async throws {
        guard supabase.currentUserID != nil else { return }
        try await supabase.client
            .rpc(
                "set_notification_master_preference_v1",
                params: MasterNotificationPreferencePayload(enabled: enabled)
            )
            .execute()
        await refreshPreferences()
    }

    func progressPreferenceEnabled(_ preference: ProgressPreference) -> Bool {
        guard let notificationPreferences else { return true }
        switch preference {
        case .weeklySummary:
            return notificationPreferences.progressWeeklySummary
        case .monthlySummary:
            return notificationPreferences.progressMonthlySummary
        case .milestones:
            return notificationPreferences.progressMilestones
        }
    }

    func setProgressPreference(_ preference: ProgressPreference, enabled: Bool) {
        Task {
            do {
                guard let userID = supabase.currentUserID else { return }
                if notificationPreferences == nil {
                    try await setMasterPreference(enabled: systemAuthorizationGranted)
                }
                try await supabase.client
                    .from("notification_preferences")
                    .update(ProgressPreferencePayload(preference: preference, enabled: enabled))
                    .eq("user_id", value: userID.uuidString)
                    .execute()
                await refreshPreferences()
            } catch {
                Self.logger.error("Progress notification preference update failed column=\(preference.columnName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                lastError = RDLocalization.string("notifications.notification.service.mesleki.bildirim.tercihi.kaydedilemedi.9b5fbbd3", table: .notifications, fallback: "Mesleki bildirim tercihi kaydedilemedi.")
            }
        }
    }

    func setAppRemindersPreference(enabled: Bool) {
        Task {
            do {
                guard let userID = supabase.currentUserID else { return }
                if notificationPreferences == nil {
                    try await setMasterPreference(enabled: systemAuthorizationGranted)
                }
                try await supabase.client
                    .from("notification_preferences")
                    .update(AppRemindersPreferencePayload(appReminders: enabled))
                    .eq("user_id", value: userID.uuidString)
                    .execute()
                await refreshPreferences()
            } catch {
                Self.logger.error("App reminder preference update failed error=\(error.localizedDescription, privacy: .public)")
                lastError = RDLocalization.string("notifications.notification.service.uygulama.bildirimi.tercihi.kaydedilemedi.2bfbb347", table: .notifications, fallback: "Uygulama bildirimi tercihi kaydedilemedi.")
            }
        }
    }

    @discardableResult
    private func refreshPreferences() async -> Bool {
        guard let userID = supabase.currentUserID else {
            notificationPreferences = nil
            preferencesUserID = nil
            return true
        }
        do {
            let rows: [NotificationPreferencesRow] = try await supabase.client
                .from("notification_preferences")
                .select()
                .eq("user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            notificationPreferences = rows.first
            preferencesUserID = userID
            return true
        } catch {
            Self.logger.error("Notification preferences fetch failed error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static var isUITestLaunch: Bool {
        #if DEBUG
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
        #else
        false
        #endif
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let kind = userInfo["kind"] as? String
        let data = userInfo["data"] as? [String: Any]
        let rawEventID = (userInfo["event_id"] as? String) ??
            (data?["notification_event_id"] as? String)
        await NotificationService.shared.recordNotificationOpen(
            eventID: rawEventID.flatMap(UUID.init(uuidString:))
        )

        if data?["destination"] as? String == "notebook" {
            await MainActor.run { NotificationService.shared.pendingOpenNotebook = true }
            return
        }
        if data?["destination"] as? String == "new_analysis" {
            await MainActor.run {
                NotificationService.shared.pendingOpenNewAnalysis = true
                NotificationService.shared.pendingDestinationTab = .home
            }
            return
        }
        if data?["destination"] as? String == "home" {
            await MainActor.run {
                NotificationService.shared.pendingDestinationTab = .home
            }
            return
        }
        if kind == "report_ready" ||
            data?["destination"] as? String == "reports" {
            await MainActor.run {
                NotificationService.shared.pendingDestinationTab = .reports
            }
            return
        }
        if kind == "account_updates" ||
            kind == "trial_reminder" ||
            kind?.hasPrefix("progress_") == true ||
            data?["destination"] as? String == "profile" {
            await MainActor.run {
                NotificationService.shared.pendingDestinationTab = .profile
            }
            return
        }
        let rawAnalysisID = (data?["analysis_id"] as? String) ??
            (userInfo["analysis_id"] as? String) ??
            ((userInfo["data"] as? String).flatMap { rawData in
                guard let bytes = rawData.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                    return nil
                }
                return json["analysis_id"] as? String
            })
        guard let rawAnalysisID, let analysisID = UUID(uuidString: rawAnalysisID) else { return }
        await MainActor.run {
            NotificationService.shared.pendingAnalysisHistoryID = analysisID
        }
    }
}

final class RDAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MetaAppEventsService.shared.configure(application: application, launchOptions: launchOptions)
        return true
    }

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        if Self.isUITestLaunch {
            UIView.setAnimationsEnabled(false)
        }
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationService.shared.didFailToRegisterForRemoteNotifications(error: error)
    }

    #if DEBUG
    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
    }
    #endif
}

private enum PushEnvironment {
    static var current: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

private struct PushDeviceTokenPayload: Encodable {
    let userID: String
    let token: String
    let platform: String
    let environment: String
    let appVersion: String?
    let deviceModel: String
    let notificationsEnabled: Bool
    let lastRegisteredAt: String
    let provider: String
    let applicationID: String?
    let installationID: String
    let clientBuild: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case token
        case platform
        case environment
        case appVersion = "app_version"
        case deviceModel = "device_model"
        case notificationsEnabled = "notifications_enabled"
        case lastRegisteredAt = "last_registered_at"
        case provider
        case applicationID = "application_id"
        case installationID = "installation_id"
        case clientBuild = "client_build"
    }
}

private struct ISGDevicePermissionPayload: Encodable {
    let token: String
    let provider: String
    let build: Int32
    let authorized: Bool
    enum CodingKeys: String, CodingKey {
        case token = "p_token", provider = "p_provider", build = "p_build", authorized = "p_authorized"
    }
}

private struct MasterNotificationPreferencePayload: Encodable {
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case enabled = "p_enabled"
    }
}

private struct AppRemindersPreferencePayload: Encodable {
    let appReminders: Bool

    enum CodingKeys: String, CodingKey {
        case appReminders = "app_reminders"
    }
}

private struct EngagementStatePayload: Encodable {
    let timezone: String
    let locale: String
    let authorizationStatus: String
    let appVersion: String?
    let appBuild: String?

    enum CodingKeys: String, CodingKey {
        case timezone = "p_timezone"
        case locale = "p_locale"
        case authorizationStatus = "p_authorization_status"
        case appVersion = "p_app_version"
        case appBuild = "p_app_build"
    }
}

private struct NotificationOpenPayload: Encodable {
    let notificationEventID: String

    enum CodingKeys: String, CodingKey {
        case notificationEventID = "p_notification_event_id"
    }
}

private struct ProgressPreferencePayload: Encodable {
    let preference: NotificationService.ProgressPreference
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case progressWeeklySummary = "progress_weekly_summary"
        case progressMonthlySummary = "progress_monthly_summary"
        case progressMilestones = "progress_milestones"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch preference {
        case .weeklySummary:
            try container.encode(enabled, forKey: .progressWeeklySummary)
        case .monthlySummary:
            try container.encode(enabled, forKey: .progressMonthlySummary)
        case .milestones:
            try container.encode(enabled, forKey: .progressMilestones)
        }
    }
}

private struct NotificationPreferencesRow: Decodable {
    let enabled: Bool
    let appReminders: Bool
    let progressWeeklySummary: Bool
    let progressMonthlySummary: Bool
    let progressMilestones: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case appReminders = "app_reminders"
        case progressWeeklySummary = "progress_weekly_summary"
        case progressMonthlySummary = "progress_monthly_summary"
        case progressMilestones = "progress_milestones"
    }
}

private extension UNAuthorizationStatus {
    var backendValue: String {
        switch self {
        case .notDetermined:
            return "not_determined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        @unknown default:
            return "not_determined"
        }
    }
}
