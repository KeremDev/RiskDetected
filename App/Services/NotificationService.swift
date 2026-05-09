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

    private static let logger = Logger(subsystem: "com.riskdetected.app", category: "NotificationService")
    private let supabase = SupabaseService.shared

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshSettings() }
    }

    func refreshSettings() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
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

    func disableNotifications() {
        Task {
            do {
                try await setPreference(enabled: false)
            } catch {
                Self.logger.error("Notification preference disable failed error=\(error.localizedDescription, privacy: .public)")
                lastError = "Bildirim tercihi kaydedilemedi."
            }
        }
    }

    func syncCurrentTokenIfPossible() {
        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    nonisolated func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            lastDeviceToken = token
            do {
                try await saveDeviceToken(token)
                try await setPreference(enabled: true)
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
        let payload = PushDeviceTokenPayload(
            userID: userID.uuidString,
            token: token,
            platform: "ios",
            environment: PushEnvironment.current,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            deviceModel: UIDevice.current.model,
            notificationsEnabled: true
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
            marketing: false
        )

        try await supabase.client
            .from("notification_preferences")
            .upsert(payload, onConflict: "user_id")
            .execute()
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

final class RDAppDelegate: NSObject, UIApplicationDelegate {
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

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case token
        case platform
        case environment
        case appVersion = "app_version"
        case deviceModel = "device_model"
        case notificationsEnabled = "notifications_enabled"
    }
}

private struct NotificationPreferencePayload: Encodable {
    let userID: String
    let enabled: Bool
    let analysisComplete: Bool
    let reportReady: Bool
    let accountUpdates: Bool
    let marketing: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case enabled
        case analysisComplete = "analysis_complete"
        case reportReady = "report_ready"
        case accountUpdates = "account_updates"
        case marketing
    }
}
