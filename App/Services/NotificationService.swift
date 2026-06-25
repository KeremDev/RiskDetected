import Foundation
import SwiftUI
import UIKit
import UserNotifications
import Supabase
import OSLog

@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastError: String?
    @Published private(set) var lastDeviceToken: String?
    @Published private(set) var isRegistering = false
    @Published private var notificationPreferences: NotificationPreferencesRow?
    @Published var pendingAnalysisHistoryID: UUID?
    @Published var pendingDestinationTab: RDTab?

    var systemAuthorizationGranted: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    var notificationsEnabled: Bool {
        systemAuthorizationGranted && (notificationPreferences?.enabled ?? true)
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
    private let supabase = SupabaseService.shared

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
            syncCurrentTokenIfPossible()
        }
    }

    func refreshSettings() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        await refreshPreferences()
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
                    try await setPreference(enabled: false)
                    isRegistering = false
                    return
                }

                UIApplication.shared.registerForRemoteNotifications()
            } catch {
                Self.logger.error("Notification authorization failed error=\(error.localizedDescription, privacy: .public)")
                lastError = "Bildirim izni alınamadı. Lütfen cihaz ayarlarından tekrar dene."
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
                    try? await setPreference(enabled: false)
                    isRegistering = false
                    return
                }

                UIApplication.shared.registerForRemoteNotifications()

            case .authorized, .provisional, .ephemeral:
                await refreshSettings()
                UIApplication.shared.registerForRemoteNotifications()

            case .denied:
                try? await setPreference(enabled: false)
                await refreshSettings()
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
                try await setPreference(enabled: false)
                await refreshSettings()
            } catch {
                Self.logger.error("Notification preference disable failed error=\(error.localizedDescription, privacy: .public)")
                lastError = "Bildirim tercihi kaydedilemedi."
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
                        try await setPreference(enabled: false)
                        await refreshSettings()
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

                try await setPreference(enabled: true)
                await refreshSettings()
                UIApplication.shared.registerForRemoteNotifications()
                isRegistering = false
            } catch {
                Self.logger.error("Notification preference enable failed error=\(error.localizedDescription, privacy: .public)")
                lastError = "Bildirim tercihi açılmadı. Lütfen tekrar dene."
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

    nonisolated func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            lastDeviceToken = token
            do {
                try await saveDeviceToken(token)
                if notificationPreferences?.enabled != false {
                    try await setPreference(enabled: true)
                }
                Self.logger.info("Device token saved environment=\(PushEnvironment.current, privacy: .public)")
                isRegistering = false
            } catch {
                Self.logger.error("Device token save failed error=\(error.localizedDescription, privacy: .public)")
                lastError = "Bildirim cihaz kaydı tamamlanamadı."
                isRegistering = false
            }
        }
    }

    nonisolated func didFailToRegisterForRemoteNotifications(error: Error) {
        Task { @MainActor in
            Self.logger.error("APNs registration failed error=\(error.localizedDescription, privacy: .public)")
            lastError = "Bildirim cihaz kaydı alınamadı. Simülatörde veya imza ayarlarında APNs desteklenmeyebilir."
            isRegistering = false
        }
    }

    private func saveDeviceToken(_ token: String) async throws {
        guard let userID = supabase.currentUserID else { return }
        let preferenceAllowsNotifications = notificationPreferences?.enabled ?? true
        let payload = PushDeviceTokenPayload(
            userID: userID.uuidString,
            token: token,
            platform: "ios",
            environment: PushEnvironment.current,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            deviceModel: UIDevice.current.model,
            notificationsEnabled: preferenceAllowsNotifications,
            lastRegisteredAt: ISO8601DateFormatter().string(from: Date())
        )

        try await supabase.client
            .from("push_device_tokens")
            .upsert(payload, onConflict: "user_id,token")
            .execute()
    }

    private func setPreference(enabled: Bool) async throws {
        guard let userID = supabase.currentUserID else { return }
        let payload = NotificationPreferencePayload(
            userID: userID.uuidString,
            enabled: enabled,
            analysisComplete: enabled,
            reportReady: enabled,
            accountUpdates: enabled,
            marketing: false,
            trialReminder: enabled,
            progressWeeklySummary: enabled,
            progressMonthlySummary: enabled,
            progressMilestones: enabled
        )

        try await supabase.client
            .from("notification_preferences")
            .upsert(payload, onConflict: "user_id")
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
                    try await setPreference(enabled: authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral)
                }
                try await supabase.client
                    .from("notification_preferences")
                    .update(ProgressPreferencePayload(preference: preference, enabled: enabled))
                    .eq("user_id", value: userID.uuidString)
                    .execute()
                await refreshPreferences()
            } catch {
                Self.logger.error("Progress notification preference update failed column=\(preference.columnName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                lastError = "Mesleki bildirim tercihi kaydedilemedi."
            }
        }
    }

    private func refreshPreferences() async {
        guard let userID = supabase.currentUserID else {
            notificationPreferences = nil
            return
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
        } catch {
            Self.logger.error("Notification preferences fetch failed error=\(error.localizedDescription, privacy: .public)")
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

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case token
        case platform
        case environment
        case appVersion = "app_version"
        case deviceModel = "device_model"
        case notificationsEnabled = "notifications_enabled"
        case lastRegisteredAt = "last_registered_at"
    }
}

private struct NotificationPreferencePayload: Encodable {
    let userID: String
    let enabled: Bool
    let analysisComplete: Bool
    let reportReady: Bool
    let accountUpdates: Bool
    let marketing: Bool
    let trialReminder: Bool
    let progressWeeklySummary: Bool
    let progressMonthlySummary: Bool
    let progressMilestones: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case enabled
        case analysisComplete = "analysis_complete"
        case reportReady = "report_ready"
        case accountUpdates = "account_updates"
        case marketing
        case trialReminder = "trial_reminder"
        case progressWeeklySummary = "progress_weekly_summary"
        case progressMonthlySummary = "progress_monthly_summary"
        case progressMilestones = "progress_milestones"
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
    let progressWeeklySummary: Bool
    let progressMonthlySummary: Bool
    let progressMilestones: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case progressWeeklySummary = "progress_weekly_summary"
        case progressMonthlySummary = "progress_monthly_summary"
        case progressMilestones = "progress_milestones"
    }
}
