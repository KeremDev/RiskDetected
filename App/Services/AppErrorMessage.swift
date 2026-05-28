import Foundation

struct AppErrorMessage: Equatable {
    enum Category: String {
        case authRequired
        case quotaExceeded
        case networkUnavailable
        case storageDenied
        case aiRateLimited
        case aiUnavailable
        case aiInvalidResponse
        case reportArchiveFailed
        case pdfRenderFailed
        case validationFailed
        case databaseFailed
        case unknown
    }

    let title: String
    let message: String
    let action: String
    let category: Category
    let supportID: String

    var fullText: String {
        "\(message)\n\nNe yapabilirsin: \(action)\n\nDestek kodu: \(supportID)"
    }

    static func make(
        _ error: Error,
        context: String? = nil,
        fallbackTitle: String = "İşlem tamamlanamadı"
    ) -> AppErrorMessage {
        if let analysisError = error as? AnalysisService.AnalysisError {
            return make(analysisError, context: context, fallbackTitle: fallbackTitle)
        }
        return make(rawMessage: error.localizedDescription, context: context, fallbackTitle: fallbackTitle)
    }

    static func make(
        rawMessage: String,
        context: String? = nil,
        fallbackTitle: String = "İşlem tamamlanamadı"
    ) -> AppErrorMessage {
        let raw = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased(with: Locale(identifier: "tr_TR"))
        let supportID = Self.existingSupportID(in: raw) ?? Self.newSupportID()

        if isFreeRiskAnalysisTrialExhausted(rawMessage) {
            return AppErrorMessage(
                title: "Risk analizi hakkı kullanıldı",
                message: "Bir kez tanımlanan risk analizi tablosu hakkını kullandın.",
                action: "Risk analizi tablolarını kullanmaya devam etmek için Plus veya Pro'ya geç.",
                category: .quotaExceeded,
                supportID: supportID
            )
        }

        if isReportQuotaExceeded(rawMessage) {
            return AppErrorMessage(
                title: "Rapor limiti doldu",
                message: "Bu plan için rapor oluşturma limitin dolmuş görünüyor.",
                action: "Bir üst plana yükselt veya yeni kota dönemini bekle.",
                category: .quotaExceeded,
                supportID: supportID
            )
        }

        let isDailyQuota = lower.contains("günlük kota") ||
            lower.contains("günlük analiz kot") ||
            lower.contains("günlük detaylı analiz kot") ||
            lower.contains("analiz kotan doldu") ||
            lower.contains("analiz/gün") ||
            lower.contains("quota_exceeded") ||
            lower.contains("ücretsiz analiz hakk")
        if isDailyQuota {
            let isFreeQuota = lower.contains("ücretsiz")
            return AppErrorMessage(
                title: "Analiz hakkı doldu",
                message: raw.components(separatedBy: "\n").first ?? "Analiz kotan dolmuş görünüyor.",
                action: isFreeQuota ? "Plus veya Pro ile devam edebilirsin." : "Plan kotan yenilenene kadar bekle veya daha üst plana geç.",
                category: .quotaExceeded,
                supportID: supportID
            )
        }

        if lower.contains("email_address_invalid") ||
            lower.contains("invalid email") ||
            lower.contains("email address") && lower.contains("invalid")
        {
            return AppErrorMessage(
                title: context ?? "E-posta adresi geçerli değil",
                message: "E-posta adresi doğrulanamadı.",
                action: "Geçerli ve erişebildiğin bir e-posta adresi girip tekrar kod gönder.",
                category: .validationFailed,
                supportID: supportID
            )
        }

        if lower.contains("over_email_send_rate_limit") ||
            lower.contains("email rate limit") ||
            lower.contains("email send rate") ||
            lower.contains("too many requests") && lower.contains("email")
        {
            return AppErrorMessage(
                title: context ?? "Kod gönderme sınırı",
                message: "Kısa süre içinde çok fazla e-posta kodu istendiği için yeni kod gönderilemiyor.",
                action: "Birkaç dakika bekleyip tekrar dene. Gerekirse son gönderilen kodu kontrol et.",
                category: .validationFailed,
                supportID: supportID
            )
        }

        if lower.contains("otp_expired") ||
            lower.contains("token expired") ||
            lower.contains("token has expired") ||
            lower.contains("expired or is invalid") ||
            lower.contains("expired") && lower.contains("otp")
        {
            return AppErrorMessage(
                title: context ?? "Kodun süresi doldu",
                message: "Girdiğin doğrulama kodu artık geçerli değil.",
                action: "Yeni bir kod isteyip e-postana gelen son kodla tekrar dene.",
                category: .authRequired,
                supportID: supportID
            )
        }

        if lower.contains("invalid token") ||
            lower.contains("token_invalid") ||
            lower.contains("invalid otp") ||
            lower.contains("otp") && lower.contains("invalid")
        {
            return AppErrorMessage(
                title: context ?? "Kod doğrulanamadı",
                message: "Girdiğin doğrulama kodu eşleşmedi.",
                action: "Kodu e-postadaki son haliyle kontrol et veya yeni kod iste.",
                category: .authRequired,
                supportID: supportID
            )
        }

        if lower.contains("429") ||
            lower.contains("rate") ||
            lower.contains("resource_exhausted") ||
            lower.contains("gemini kotası") ||
            lower.contains("ai sağlayıcısı")
        {
            return AppErrorMessage(
                title: "AI servisi yoğun",
                message: "AI sağlayıcısı şu anda isteği kabul etmedi. Bu genellikle geçici kota veya yoğunluk durumlarında olur.",
                action: "Biraz bekleyip tekrar dene. Tekrar ederse farklı analiz odağıyla veya daha küçük fotoğrafla deneyebilirsin.",
                category: .aiRateLimited,
                supportID: supportID
            )
        }

        if lower.contains("503") || lower.contains("unavailable") || lower.contains("yoğun") || lower.contains("timeout") || lower.contains("timed out") {
            return AppErrorMessage(
                title: "AI servisi geçici olarak yanıt vermiyor",
                message: "Analiz modeli şu anda yoğun veya geçici olarak erişilemiyor.",
                action: "Kısa süre sonra tekrar dene. Fotoğraf ve seçtiğin analiz odağı korunuyorsa işlemi yeniden başlatabilirsin.",
                category: .aiUnavailable,
                supportID: supportID
            )
        }

        if lower.contains("yanıtı işlenemedi") ||
            lower.contains("yaniti islenemedi") ||
            lower.contains("ai_invalid_response") ||
            lower.contains("json") && lower.contains("ai")
        {
            return AppErrorMessage(
                title: "AI yanıtı işlenemedi",
                message: "Analiz modeli yanıt verdi ancak sonuç beklenen formatta işlenemedi.",
                action: "Aynı analizi tekrar dene. Tekrar ederse destek koduyla birlikte bildir.",
                category: .aiInvalidResponse,
                supportID: supportID
            )
        }

        if lower.contains("row-level security") || lower.contains("rls") || lower.contains("unauthorized") || lower.contains("403") {
            return AppErrorMessage(
                title: "Yetki kontrolü nedeniyle işlem yapılamadı",
                message: "Bu işlem için oturum veya veri erişim izni doğrulanamadı.",
                action: "Çıkış yapıp tekrar giriş yap. Sorun devam ederse destek koduyla birlikte bildir.",
                category: .storageDenied,
                supportID: supportID
            )
        }

        if lower.contains("network") || lower.contains("internet") || lower.contains("offline") || lower.contains("connection") {
            return AppErrorMessage(
                title: "Bağlantı sorunu",
                message: "İnternet bağlantısı veya servis erişimi kesildiği için işlem tamamlanamadı.",
                action: "Bağlantını kontrol edip tekrar dene.",
                category: .networkUnavailable,
                supportID: supportID
            )
        }

        if lower.contains("fotoğraf") && (lower.contains("indirilemedi") || lower.contains("download")) {
            return AppErrorMessage(
                title: context ?? "Fotoğraf yüklenemedi",
                message: "Analiz fotoğrafı şu anda indirilemedi. Ekran yedek görselle açılabilir.",
                action: "Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir.",
                category: .storageDenied,
                supportID: supportID
            )
        }

        if lower.contains("veri dışa aktar") || lower.contains("dışa aktarımı") || lower.contains("export") {
            return AppErrorMessage(
                title: context ?? "Veri dışa aktarımı oluşturulamadı",
                message: "Verilerinin dışa aktarım dosyası hazırlanamadı.",
                action: "Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir.",
                category: .databaseFailed,
                supportID: supportID
            )
        }

        if lower.contains("hesap silme talebi") || lower.contains("account deletion") {
            return AppErrorMessage(
                title: context ?? "Hesap silme talebi kaydedilemedi",
                message: "Hesap silme talebin sunucuya kaydedilemedi.",
                action: "Kısa süre sonra tekrar dene. Sorun devam ederse destek koduyla bildir.",
                category: .databaseFailed,
                supportID: supportID
            )
        }

        if lower.contains("indirilemedi") || lower.contains("download") {
            return AppErrorMessage(
                title: context ?? "Rapor indirilemedi",
                message: "Kayıtlı PDF raporu indirilemedi veya paylaşım için hazırlanamadı.",
                action: "Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir.",
                category: .reportArchiveFailed,
                supportID: supportID
            )
        }

        if lower.contains("analiz") && (lower.contains("silinemedi") || lower.contains("delete")) {
            return AppErrorMessage(
                title: context ?? "Analiz silinemedi",
                message: "Analiz ve ilişkili kayıtlar silinemedi.",
                action: "Liste korunur. Kısa süre sonra tekrar dene; sorun devam ederse destek koduyla bildir.",
                category: .databaseFailed,
                supportID: supportID
            )
        }

        if lower.contains("rapor") && (lower.contains("silinemedi") || lower.contains("delete")) {
            return AppErrorMessage(
                title: context ?? "Rapor silinemedi",
                message: "PDF raporu veya rapor arşiv kaydı silinemedi.",
                action: "Kısa süre sonra tekrar dene. Sorun devam ederse destek koduyla bildir.",
                category: .reportArchiveFailed,
                supportID: supportID
            )
        }

        if lower.contains("arşiv") || lower.contains("archive") || lower.contains("kaydedilemedi") {
            return AppErrorMessage(
                title: context ?? "Rapor arşive kaydedilemedi",
                message: "PDF oluşturuldu ancak rapor arşivine kaydedilemedi.",
                action: "PDF açıldıysa dosyayı paylaşabilir, arşiv kaydı için daha sonra yeniden oluşturabilirsin.",
                category: .reportArchiveFailed,
                supportID: supportID
            )
        }

        if lower.contains("pdf") || lower.contains("rapor") {
            return AppErrorMessage(
                title: context ?? "PDF oluşturulamadı",
                message: "PDF hazırlanırken bir sorun oluştu.",
                action: "Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir.",
                category: .pdfRenderFailed,
                supportID: supportID
            )
        }

        if lower.contains("veritaban") || lower.contains("database") || lower.contains("schema") || lower.contains("constraint") || lower.contains("enum") {
            return AppErrorMessage(
                title: "Veri kaydı tamamlanamadı",
                message: "Sunucuda veri kaydı veya veri okuma sırasında bir sorun oluştu.",
                action: "Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir.",
                category: .databaseFailed,
                supportID: supportID
            )
        }

        if !raw.isEmpty && raw.count < 140 && !raw.contains("{") && !raw.contains("HTTP") {
            return AppErrorMessage(
                title: fallbackTitle,
                message: raw,
                action: "Girdiğini kontrol edip tekrar dene.",
                category: .validationFailed,
                supportID: supportID
            )
        }

        return AppErrorMessage(
            title: fallbackTitle,
            message: "Beklenmeyen bir sorun oluştu ve işlem tamamlanamadı.",
            action: "Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir.",
            category: .unknown,
            supportID: supportID
        )
    }

    static func isReportQuotaExceeded(_ rawMessage: String) -> Bool {
        let lower = rawMessage.lowercased(with: Locale(identifier: "tr_TR"))
        return lower.contains("report_quota_exceeded") ||
            lower.contains("free_risk_analysis_trial_exhausted") ||
            lower.contains("risk analizi") && lower.contains("deneme hakk") ||
            lower.contains("aylık rapor kot") ||
            lower.contains("standart rapor hakk") ||
            lower.contains("rapor") && lower.contains("limit") && lower.contains("dol")
    }

    static func isFreeRiskAnalysisTrialExhausted(_ rawMessage: String) -> Bool {
        let lower = rawMessage.lowercased(with: Locale(identifier: "tr_TR"))
        return lower.contains("free_risk_analysis_trial_exhausted") ||
            lower.contains("risk analizi") && lower.contains("deneme hakk")
    }

    private static func make(
        _ error: AnalysisService.AnalysisError,
        context: String?,
        fallbackTitle: String
    ) -> AppErrorMessage {
        let supportID = Self.existingSupportID(in: error.localizedDescription) ?? Self.newSupportID()
        switch error {
        case .notAuthenticated:
            return AppErrorMessage(
                title: "Oturum gerekli",
                message: "Bu işlem için aktif bir kullanıcı oturumu bulunamadı.",
                action: "Tekrar giriş yapıp işlemi yeniden başlat.",
                category: .authRequired,
                supportID: supportID
            )
        case .quotaExceeded(let message, let tier):
            let isFree = tier == "free" || message.localizedCaseInsensitiveContains("ücretsiz")
            return AppErrorMessage(
                title: "Analiz hakkı doldu",
                message: message,
                action: isFree ? "Plus veya Pro ile devam edebilirsin." : "Plan kotan yenilenene kadar bekle veya daha üst plana geç.",
                category: .quotaExceeded,
                supportID: supportID
            )
        case .alreadyCompleted:
            return AppErrorMessage(
                title: "Analiz zaten tamamlandı",
                message: "Bu analiz daha önce tamamlanmış.",
                action: "Sonuçlar ekranından analizi açabilir veya yeni bir analiz başlatabilirsin.",
                category: .validationFailed,
                supportID: supportID
            )
        case .invalidInput(let message):
            return AppErrorMessage(
                title: "Eksik bilgi",
                message: message,
                action: "Girdiyi tamamlayıp tekrar dene.",
                category: .validationFailed,
                supportID: supportID
            )
        case .aiFailed(let message):
            return make(rawMessage: message, context: context ?? "AI analizi tamamlanamadı", fallbackTitle: "AI analizi tamamlanamadı")
        case .storageFailed(let message):
            return make(rawMessage: message, context: context ?? "Dosya işlemi tamamlanamadı", fallbackTitle: "Dosya işlemi tamamlanamadı")
        case .databaseFailed(let message):
            return make(rawMessage: message, context: context ?? "Veri işlemi tamamlanamadı", fallbackTitle: "Veri işlemi tamamlanamadı")
        }
    }

    static func newSupportID() -> String {
        "RD-\(UUID().uuidString.prefix(8).uppercased())"
    }

    private static func existingSupportID(in text: String) -> String? {
        let upper = text.uppercased()
        let pattern = #"RD-[A-Z0-9]{8}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
        guard let match = regex.firstMatch(in: upper, range: range),
              let swiftRange = Range(match.range, in: upper) else {
            return nil
        }
        return String(upper[swiftRange])
    }
}
