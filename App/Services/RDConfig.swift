import Foundation

/// RiskDetected — Supabase ve Edge Function konfigürasyonu.
///
/// Production'da bu değerler `xcconfig` veya environment'tan okunmalı; ancak
/// Free tier `anon` / `publishable` key'i client-side kullanım için tasarlandığından
/// repo'da bulunması güvenlik açığı oluşturmaz (RLS tüm istekleri kullanıcı bazlı
/// kısıtlar). Service-role key burada YER ALMAZ — sadece Edge Function üzerinde.
enum RDConfig {
    /// Supabase proje URL'i.
    static let supabaseURL = URL(string: "https://ppcrzemgiztzcgddbins.supabase.co")!

    /// Supabase publishable key (modern format — JWT tabanlı anon key'in yerini alır).
    static let supabasePublishableKey =
        "sb_publishable_cUQq5Lv-zDF1hXqwnmAj1A_LTdk9FJt"

    /// Edge Function endpoint adı.
    static let analyzeFunctionName = "analyze"
    static let firebasePhoneBridgeFunctionName = "firebase-phone-bridge"
    static let sendPushNotificationFunctionName = "send-push-notification"
    static let generateExcelReportFunctionName = "generate-excel-report"

    /// Storage bucket adları.
    enum Bucket {
        static let photos  = "photos"
        static let reports = "reports"
        static let logos   = "logos"
    }

    enum Auth {
        /// Phone sign-in is currently hidden. Primary passwordless auth is email OTP.
        static let useFirebasePhoneBridge = false
    }
}
