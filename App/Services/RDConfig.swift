import Foundation

/// RiskDetected — Supabase ve Edge Function konfigürasyonu.
///
/// Production'da bu değerler `xcconfig` veya environment'tan okunmalı; ancak
/// Free tier `anon` / `publishable` key'i client-side kullanım için tasarlandığından
/// repo'da bulunması güvenlik açığı oluşturmaz (RLS tüm istekleri kullanıcı bazlı
/// kısıtlar). Service-role key burada YER ALMAZ — sadece Edge Function üzerinde.
enum RDConfig {
    private static func configuredString(
        bundleKey: String,
        environmentKey: String,
        defaultValue: String
    ) -> String {
        if let environmentValue = ProcessInfo.processInfo.environment[environmentKey],
           !environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentValue
        }

        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: bundleKey) as? String {
            let trimmed = bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains("$(") {
                return trimmed
            }
        }

        return defaultValue
    }

    /// Public web presence and legal page URLs.
    enum Web {
        static let websiteURL = URL(string: "https://riskdetected.com")!
        static let supportURL = URL(string: "https://riskdetected.com")!
        static let privacyPolicyURL = URL(string: "https://riskdetected.com/gizlilik")!
        static let termsURL = URL(string: "https://riskdetected.com/kullanim-kosullari")!
        static let kvkkURL = URL(string: "https://riskdetected.com/kvkk")!
        static let explicitConsentURL = URL(string: "https://riskdetected.com/acik-riza-beyani")!
        static let legalDocumentsBaseURL = URL(string: "https://riskdetected.com/legal-documents/")!
    }

    private static let productionSupabaseURLString = "https://ppcrzemgiztzcgddbins.supabase.co"
    private static let defaultSupabaseURLString = productionSupabaseURLString
    private static let defaultSupabasePublishableKey = "sb_publishable_cUQq5Lv-zDF1hXqwnmAj1A_LTdk9FJt"
    private static let defaultRevenueCatAPIKey = "appl_mckFFxUrvtNqzjShezjMIrFmItA"
    private static let defaultRevenueCatOfferingIdentifier = "default"

    /// Supabase proje URL'i.
    static let supabaseURL = URL(
        string: configuredString(
            bundleKey: "RDSupabaseURL",
            environmentKey: "RISKDETECTED_SUPABASE_URL",
            defaultValue: defaultSupabaseURLString
        )
    )!

    /// Supabase publishable key (modern format — JWT tabanlı anon key'in yerini alır).
    static let supabasePublishableKey =
        configuredString(
            bundleKey: "RDSupabasePublishableKey",
            environmentKey: "RISKDETECTED_SUPABASE_PUBLISHABLE_KEY",
            defaultValue: defaultSupabasePublishableKey
        )

    /// Edge Function endpoint adı.
    static let analyzeFunctionName = "analyze"
    static let sendPushNotificationFunctionName = "send-push-notification"
    static let sendReportReadyNotificationFunctionName = "send-report-ready-notification"
    static let generateExcelReportFunctionName = "generate-excel-report"
    static let registerReportFunctionName = "register-report"
    static let revenueCatWebhookFunctionName = "revenuecat-webhook"
    static let syncRevenueCatSubscriptionFunctionName = "sync-revenuecat-subscription"
    static let supportContactFunctionName = "support-contact"
    static let sendWelcomeEmailFunctionName = "send-welcome-email"
    static let accountDeletionRequestFunctionName = "request-account-deletion"

    /// RevenueCat client-side public SDK config. This key is intentionally public;
    /// subscription truth for backend limits must still be synced server-side.
    enum Subscription {
        static let revenueCatAPIKey = RDConfig.configuredString(
            bundleKey: "RDRevenueCatAPIKey",
            environmentKey: "RISKDETECTED_REVENUECAT_API_KEY",
            defaultValue: defaultRevenueCatAPIKey
        )
        static let offeringIdentifier = RDConfig.configuredString(
            bundleKey: "RDRevenueCatOfferingIdentifier",
            environmentKey: "RISKDETECTED_REVENUECAT_OFFERING_IDENTIFIER",
            defaultValue: defaultRevenueCatOfferingIdentifier
        )
        static let plusEntitlementID = "plus"
        static let proEntitlementID = "pro"
    }

    /// Storage bucket adları.
    enum Bucket {
        static let photos  = "photos"
        static let reports = "reports"
        static let logos   = "logos"
        static let avatars = "avatars"
        static let legalDocuments = "legal-documents"
    }

    enum Auth {
        static let redirectURL = URL(string: "io.supabase.riskdetected://login-callback")!
        static let emailOTPLength = 6
    }

    enum Security {
        static let certificatePinningEnabled = true
        static let pinnedHosts: Set<String> = [supabaseURL.host ?? ""]
            .filter { !$0.isEmpty }
            .reduce(into: Set<String>()) { $0.insert($1) }

        // Supabase currently serves a Google Trust Services chain. Pin the stable
        // intermediate/root certificates, not the short-lived leaf certificate.
        static let pinnedCertificateSHA256Hashes: Set<String> = [
            "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=", // Google Trust Services WE1
            "drJ7gKWAJ9w88dpo2sFwEO2TmX0LYD4vrb6FASSTtac="  // GTS Root R4 cross-signed
        ]
    }

    enum Quota {
        static let businessTimeZoneIdentifier = "Europe/Istanbul"
        static var businessTimeZone: TimeZone {
            TimeZone(identifier: businessTimeZoneIdentifier) ?? .current
        }
    }

    enum Features {
        static let professionalProgressEnabled = true
        static let activeAnalysisSectorEnabled = true
    }
}
