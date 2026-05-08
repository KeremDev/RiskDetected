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

        let isDailyQuota = lower.contains("günlük kota") ||
            lower.contains("analiz/gün") ||
            lower.contains("quota_exceeded") ||
            lower.contains("ücretsiz analiz hakk")
        if isDailyQuota {
            return AppErrorMessage(
                title: "Günlük limit doldu",
                message: "Bugünkü ücretsiz analiz hakkın dolmuş görünüyor.",
                action: "Yarın tekrar deneyebilir veya Pro ile sınırsız analiz akışına geçebilirsin.",
                category: .quotaExceeded,
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

        if lower.contains("pdf") || lower.contains("rapor") {
            return AppErrorMessage(
                title: context ?? "PDF oluşturulamadı",
                message: "PDF hazırlanırken veya rapor arşivine kaydedilirken bir sorun oluştu.",
                action: "Tekrar dene. PDF açıldıysa dosyayı paylaşabilir, arşiv kaydı için daha sonra yeniden oluşturabilirsin.",
                category: lower.contains("arşiv") || lower.contains("archive") ? .reportArchiveFailed : .pdfRenderFailed,
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
        case .quotaExceeded:
            return AppErrorMessage(
                title: "Günlük limit doldu",
                message: "Bugünkü ücretsiz analiz hakkın dolmuş görünüyor.",
                action: "Yarın tekrar deneyebilir veya Pro ile devam edebilirsin.",
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
