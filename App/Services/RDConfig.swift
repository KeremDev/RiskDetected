import Foundation

/// RiskDetected — Supabase ve Edge Function konfigürasyonu.
///
/// Production'da bu değerler `xcconfig` veya environment'tan okunmalı; ancak
/// Free tier `anon` / `publishable` key'i client-side kullanım için tasarlandığından
/// repo'da bulunması güvenlik açığı oluşturmaz (RLS tüm istekleri kullanıcı bazlı
/// kısıtlar). Service-role key burada YER ALMAZ — sadece Edge Function üzerinde.
enum RDConfig {
    /// Public web presence and legal page URLs.
    enum Web {
        static let websiteURL = URL(string: "https://riskdetected.com")!
        static let supportURL = URL(string: "https://riskdetected.com")!
        static let privacyPolicyURL = URL(string: "https://riskdetected.com/gizlilik")!
        static let termsURL = URL(string: "https://riskdetected.com/kullanim-kosullari")!
        static let kvkkURL = URL(string: "https://riskdetected.com/kvkk")!
    }

    /// Supabase proje URL'i.
    static let supabaseURL = URL(string: "https://ppcrzemgiztzcgddbins.supabase.co")!

    /// Supabase publishable key (modern format — JWT tabanlı anon key'in yerini alır).
    static let supabasePublishableKey =
        "sb_publishable_cUQq5Lv-zDF1hXqwnmAj1A_LTdk9FJt"

    /// Edge Function endpoint adı.
    static let analyzeFunctionName = "analyze"
    static let sendPushNotificationFunctionName = "send-push-notification"
    static let generateExcelReportFunctionName = "generate-excel-report"
    static let revenueCatWebhookFunctionName = "revenuecat-webhook"
    static let syncRevenueCatSubscriptionFunctionName = "sync-revenuecat-subscription"
    static let supportContactFunctionName = "support-contact"

    /// RevenueCat client-side public SDK config. This key is intentionally public;
    /// subscription truth for backend limits must still be synced server-side.
    enum Subscription {
        // Debug builds use the same App Store RevenueCat project as TestFlight.
        // The previous Test Store key had no products in its offering, which left
        // the paywall waiting forever for packages in simulator/debug builds.
        static let revenueCatAPIKey = "appl_mckFFxUrvtNqzjShezjMIrFmItA"
        static let plusEntitlementID = "plus"
        static let proEntitlementID = "pro"
    }

    /// Storage bucket adları.
    enum Bucket {
        static let photos  = "photos"
        static let reports = "reports"
        static let logos   = "logos"
    }

    enum Auth {
        static let redirectURL = URL(string: "io.supabase.riskdetected://login-callback")!
    }
}
