package com.riskdetectedan.core.data.error

import com.riskdetectedan.core.data.billing.PurchaseErrorClassification
import com.riskdetectedan.core.data.billing.PurchaseErrorClassifier
import com.riskdetectedan.core.data.billing.PurchaseErrorKind
import java.util.UUID

/**
 * Mirrors AppErrorMessage.swift — structured Title/Message/Action/Category/SupportID instead of
 * a raw error string, for any `RdResult.Failure.message`/exception this app surfaces to a user.
 * `RDLocalization` isn't ported (Turkish-only hardcoded strings here, same as everywhere else in
 * this port); "App Store"/"Apple ID" wording is mechanically substituted to "Google Play" (same
 * substitution convention as the legal documents — platform-accurate, not new content).
 *
 * The Swift file's private `make(_ error: AnalysisService.AnalysisError, ...)` overload isn't
 * ported — that branches on an iOS-only typed error enum with no Android equivalent (this port's
 * `AnalysisRepository` returns `RdResult.Failure(code, message)` like every other repository
 * here, not a typed sealed error). Its cases (notAuthenticated/quotaExceeded/alreadyCompleted/
 * invalidInput/aiFailed/networkFailed/storageFailed/databaseFailed) mostly just delegate to
 * `make(rawMessage:)` with a specific context string anyway — the message-string classification
 * below (quota/AI/network/etc.) already covers the same ground from the raw message alone.
 */
enum class AppErrorCategory {
    AuthRequired,
    QuotaExceeded,
    NetworkUnavailable,
    StorageDenied,
    AiRateLimited,
    AiUnavailable,
    AiInvalidResponse,
    ReportArchiveFailed,
    PdfRenderFailed,
    ValidationFailed,
    BackgroundAnalysisPending,
    DatabaseFailed,
    Unknown,
}

data class AppErrorMessage(
    val title: String,
    val message: String,
    val action: String,
    val category: AppErrorCategory,
    val supportID: String,
) {
    val fullText: String
        get() = "$message\n\nNe yapabilirsin: $action\n\nDestek kodu: $supportID"
}

object AppErrorMessages {
    private val supportIdPattern = Regex("RD-[A-Z0-9]{8}")

    fun newSupportID(): String = "RD-" + UUID.randomUUID().toString().take(8).uppercase()

    private fun existingSupportID(text: String): String? =
        supportIdPattern.find(text.uppercase())?.value

    // ---- Purchases (feature #27, PurchaseErrorClassifier-backed) --------------------------

    fun makePurchase(
        throwable: Throwable,
        context: String = "Abonelik başlatılamadı",
        fallbackTitle: String = "Abonelik başlatılamadı",
    ): AppErrorMessage = makePurchase(PurchaseErrorClassifier.classify(throwable), context, fallbackTitle)

    fun makePurchase(
        classification: PurchaseErrorClassification,
        context: String = "Abonelik başlatılamadı",
        fallbackTitle: String = "Abonelik başlatılamadı",
    ): AppErrorMessage {
        val raw = classification.rawMessage
        val supportID = existingSupportID(raw) ?: newSupportID()

        return when (classification.kind) {
            PurchaseErrorKind.Cancelled -> AppErrorMessage(
                title = context,
                message = "",
                action = "",
                category = AppErrorCategory.Unknown,
                supportID = supportID,
            )

            PurchaseErrorKind.Network -> AppErrorMessage(
                title = "Bağlantı sorunu",
                message = "İnternet bağlantısı veya abonelik servisi erişimi kesildiği için işlem tamamlanamadı.",
                action = "Bağlantını kontrol edip tekrar dene.",
                category = AppErrorCategory.NetworkUnavailable,
                supportID = supportID,
            )

            PurchaseErrorKind.ExistingSubscription -> AppErrorMessage(
                title = context,
                message = "Bu Google Play hesabında aktif bir RiskDetected aboneliği görünüyor. " +
                    "Abonelik başka bir RiskDetected hesabına bağlıysa ücretli plan bu kullanıcıya otomatik açılmaz.",
                action = "Aboneliği satın aldığın RiskDetected hesabıyla giriş yapıp Geri yükle seçeneğini kullan " +
                    "veya destekle iletişime geç.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.ReceiptConflict -> AppErrorMessage(
                title = context,
                message = "Bu Google Play aboneliği başka bir RiskDetected hesabına bağlı. " +
                    "Lütfen aboneliği satın aldığın hesapla giriş yap veya destekle iletişime geç.",
                action = "Doğru RiskDetected hesabıyla giriş yapıp Geri yükle seçeneğini kullan. " +
                    "Emin değilsen destek koduyla bize ulaş.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.BackendVerification -> AppErrorMessage(
                title = context,
                message = raw.ifEmpty {
                    "Google Play aboneliği doğrulandı ancak uygulama planı güvenli şekilde eşleştirilemedi."
                },
                action = "Birkaç saniye sonra tekrar dene veya Geri yükle seçeneğiyle aboneliği doğrula.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.PackageUnavailable -> AppErrorMessage(
                title = context,
                message = "Seçilen abonelik paketi şu an hazırlanamadı.",
                action = "Kısa süre sonra tekrar dene. Sorun devam ederse Geri yükle veya destek ile iletişime geç.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.StoreUnavailable -> AppErrorMessage(
                title = context,
                message = "Google Play abonelik servisi şu anda satın alma işlemini tamamlayamadı.",
                action = "Kısa süre sonra tekrar dene. Google Play ödeme penceresi açılmıyorsa abonelik durumunu kontrol et.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.ProductUnavailable -> AppErrorMessage(
                title = context,
                message = "Seçilen abonelik ürünü Google Play tarafından satın almaya uygun görünmüyor.",
                action = "Biraz sonra tekrar dene. Sorun devam ederse ürün yapılandırması kontrol edilmelidir.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.PurchaseNotAllowed -> AppErrorMessage(
                title = context,
                message = "Bu cihaz veya Google Play hesabı şu anda uygulama içi satın almaya izin vermiyor.",
                action = "Google Play hesap, ödeme ve ebeveyn denetimi ayarlarını kontrol edip tekrar dene.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.Configuration -> AppErrorMessage(
                title = context,
                message = "Abonelik doğrulaması için gerekli Google Play veya RevenueCat yapılandırması tamamlanamadı.",
                action = "Uygulamayı kapatıp açarak tekrar dene. Devam ederse destek koduyla bildir.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.OperationInProgress -> AppErrorMessage(
                title = context,
                message = "Bu abonelik için başka bir satın alma işlemi hâlâ devam ediyor.",
                action = "Google Play penceresinin tamamlanmasını bekle veya birkaç saniye sonra tekrar dene.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.PaymentPending -> AppErrorMessage(
                title = context,
                message = "Satın alma Google Play tarafında beklemede görünüyor.",
                action = "Ödeme onayı tamamlandığında aboneliğin otomatik güncellenir. Gerekirse Geri yükle seçeneğini kullan.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.Unknown -> AppErrorMessage(
                title = fallbackTitle,
                message = raw.ifEmpty { "Satın alma işlemi tamamlanamadı." },
                action = "Tekrar dene. Sorun devam ederse destek koduyla birlikte bize ulaş.",
                category = AppErrorCategory.Unknown,
                supportID = supportID,
            )
        }
    }

    // ---- General app-wide classifier (mirrors AppErrorMessage.swift's `make(rawMessage:)`) --

    fun make(
        throwable: Throwable,
        context: String? = null,
        fallbackTitle: String = "İşlem tamamlanamadı",
    ): AppErrorMessage = make(throwable.message ?: "", context, fallbackTitle)

    fun make(
        rawMessage: String,
        context: String? = null,
        fallbackTitle: String = "İşlem tamamlanamadı",
    ): AppErrorMessage {
        val raw = rawMessage.trim()
        val lower = raw.lowercase()
        val supportID = existingSupportID(raw) ?: newSupportID()

        // Real bug caught via live on-device testing (2026-08-08): a client-side ktor
        // HttpRequestTimeoutException's message is "Request timeout has expired [url=.../auth/v1/
        // otp, ...]" — the request URL itself contains "otp", so the *later*, more specific
        // `(lower.contains("expired") && lower.contains("otp"))` branch below was matching first
        // in effect (both conditions true) and mislabeling a plain network timeout as "your
        // verification code expired, request a new one" — actively misleading for a failure the
        // user hasn't even received a code for yet. A raw client-side timeout should always win
        // over a content-based guess at what a response *would* have said, so this check runs
        // first, ahead of every other classification in this cascade.
        if (lower.contains("request timeout has expired") ||
            lower.contains("httprequesttimeoutexception") ||
            lower.contains("connecttimeoutexception") ||
            lower.contains("sockettimeoutexception")
        ) {
            return AppErrorMessage(
                title = context ?: "Bağlantı sorunu",
                message = "Sunucuya bağlanırken zaman aşımı oluştu.",
                action = "Bağlantını kontrol edip tekrar dene.",
                category = AppErrorCategory.NetworkUnavailable,
                supportID = supportID,
            )
        }

        // Real bug caught live (2026-08-09): auth-send-email-hook (Supabase Edge Function that
        // actually delivers OTP/login-code emails) failing — a transient DB/network blip claiming
        // its idempotency lease, see the function's own doc comment — surfaces here as GoTrue's
        // generic 500 wrapper message, "...Service currently unavailable due to hook...", which
        // contains both "503"-adjacent wording and literally "unavailable". Without this check
        // that message falls through to the AI-provider classifier below (line ~353's bare
        // "unavailable"/"503"/"timeout" substring match, meant for the *analyze* pipeline) and
        // shows a wildly wrong "Analiz modeli şu anda yoğun..." message for what is actually a
        // failed login-code send — same bug *class* as the OTP-timeout/token-expired collision
        // documented in the client-side-timeout check above, same fix: a narrower, more specific
        // check runs first so a broad downstream substring match never gets the chance to
        // mislabel it. Real, honest fallback message this time (not the OTP-specific one above,
        // since this is the sender failing, not an entered code being wrong/expired).
        if (lower.contains("unavailable due to hook") ||
            lower.contains("error running hook") ||
            (lower.contains("hook") && (lower.contains("503") || lower.contains("unavailable")))
        ) {
            return AppErrorMessage(
                title = context ?: "Kod gönderilemedi",
                message = "Doğrulama kodu gönderilirken sunucu tarafında geçici bir sorun oluştu.",
                action = "Birkaç saniye bekleyip tekrar dene.",
                category = AppErrorCategory.Unknown,
                supportID = supportID,
            )
        }

        if (isFreeRiskAnalysisTrialExhausted(rawMessage)) {
            return AppErrorMessage(
                title = "Risk analizi hakkı kullanıldı",
                message = "Bir kez tanımlanan risk analizi tablosu hakkını kullandın.",
                action = "Risk analizi tablolarını kullanmaya devam etmek için Plus veya Pro'ya geç.",
                category = AppErrorCategory.QuotaExceeded,
                supportID = supportID,
            )
        }

        if (isReportQuotaExceeded(rawMessage)) {
            return AppErrorMessage(
                title = "Rapor limiti doldu",
                message = "Bu plan için rapor oluşturma limitin dolmuş görünüyor.",
                action = "Bir üst plana yükselt veya yeni kota dönemini bekle.",
                category = AppErrorCategory.QuotaExceeded,
                supportID = supportID,
            )
        }

        if (lower.contains("arka planda devam ediyor") ||
            lower.contains("geçmiş analizler") ||
            lower.contains("gecmis analizler")
        ) {
            return AppErrorMessage(
                title = "Analiz arka planda devam ediyor",
                message = raw.lineSequence().firstOrNull() ?: "Analiz arka planda devam ediyor.",
                action = "Aynı analizi tekrar başlatmadan önce Geçmiş analizler ekranını birkaç dakika sonra yenile.",
                category = AppErrorCategory.BackgroundAnalysisPending,
                supportID = supportID,
            )
        }

        val isDailyQuota = lower.contains("günlük kota") ||
            lower.contains("günlük analiz kot") ||
            lower.contains("günlük detaylı analiz kot") ||
            lower.contains("analiz kotan doldu") ||
            lower.contains("analiz/gün") ||
            lower.contains("quota_exceeded") ||
            lower.contains("ücretsiz analiz hakk")
        if (isDailyQuota) {
            val isFreeQuota = lower.contains("ücretsiz")
            return AppErrorMessage(
                title = "Analiz hakkı doldu",
                message = raw.lineSequence().firstOrNull() ?: "Analiz kotan dolmuş görünüyor.",
                action = if (isFreeQuota) {
                    "Plus veya Pro ile devam edebilirsin."
                } else {
                    "Plan kotan yenilenene kadar bekle veya daha üst plana geç."
                },
                category = AppErrorCategory.QuotaExceeded,
                supportID = supportID,
            )
        }

        if (lower.contains("email_address_invalid") ||
            lower.contains("invalid email") ||
            (lower.contains("email address") && lower.contains("invalid"))
        ) {
            return AppErrorMessage(
                title = context ?: "E-posta adresi geçerli değil",
                message = "E-posta adresi doğrulanamadı.",
                action = "Geçerli ve erişebildiğin bir e-posta adresi girip tekrar kod gönder.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("over_email_send_rate_limit") ||
            lower.contains("email rate limit") ||
            lower.contains("email send rate") ||
            (lower.contains("too many requests") && lower.contains("email"))
        ) {
            return AppErrorMessage(
                title = context ?: "Kod gönderme sınırı",
                message = "Kısa süre içinde çok fazla e-posta kodu istendiği için yeni kod gönderilemiyor.",
                action = "Birkaç dakika bekleyip tekrar dene. Gerekirse son gönderilen kodu kontrol et.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("otp_expired") ||
            lower.contains("token expired") ||
            lower.contains("token has expired") ||
            lower.contains("expired or is invalid") ||
            (lower.contains("expired") && lower.contains("otp"))
        ) {
            return AppErrorMessage(
                title = context ?: "Kodun süresi doldu",
                message = "Girdiğin doğrulama kodu artık geçerli değil.",
                action = "Yeni bir kod isteyip e-postana gelen son kodla tekrar dene.",
                category = AppErrorCategory.AuthRequired,
                supportID = supportID,
            )
        }

        if (lower.contains("invalid token") ||
            lower.contains("token_invalid") ||
            lower.contains("invalid otp") ||
            (lower.contains("otp") && lower.contains("invalid"))
        ) {
            return AppErrorMessage(
                title = context ?: "Kod doğrulanamadı",
                message = "Girdiğin doğrulama kodu eşleşmedi.",
                action = "Kodu e-postadaki son haliyle kontrol et veya yeni kod iste.",
                category = AppErrorCategory.AuthRequired,
                supportID = supportID,
            )
        }

        if (lower.contains("429") ||
            lower.contains("rate") ||
            lower.contains("resource_exhausted") ||
            lower.contains("gemini kotası") ||
            lower.contains("ai sağlayıcısı")
        ) {
            return AppErrorMessage(
                title = "AI servisi yoğun",
                message = "AI sağlayıcısı şu anda isteği kabul etmedi. Bu genellikle geçici kota veya yoğunluk durumlarında olur.",
                action = "Biraz bekleyip tekrar dene. Tekrar ederse farklı analiz odağıyla veya daha küçük fotoğrafla deneyebilirsin.",
                category = AppErrorCategory.AiRateLimited,
                supportID = supportID,
            )
        }

        if (lower.contains("503") || lower.contains("unavailable") || lower.contains("yoğun") ||
            lower.contains("timeout") || lower.contains("timed out")
        ) {
            return AppErrorMessage(
                title = "AI servisi geçici olarak yanıt vermiyor",
                message = "Analiz modeli şu anda yoğun veya geçici olarak erişilemiyor.",
                action = "Kısa süre sonra tekrar dene. Fotoğraf ve seçtiğin analiz odağı korunuyorsa işlemi yeniden başlatabilirsin.",
                category = AppErrorCategory.AiUnavailable,
                supportID = supportID,
            )
        }

        if (lower.contains("output_language_contract_failed")) {
            return AppErrorMessage(
                title = "AI yanıtı işlenemedi",
                message = "Analiz, seçilen çıktı diliyle güvenli biçimde tamamlanamadı. Lütfen tekrar dene.",
                action = "Aynı analizi tekrar dene. Tekrar ederse destek koduyla birlikte bildir.",
                category = AppErrorCategory.AiInvalidResponse,
                supportID = supportID,
            )
        }

        if (lower.contains("yanıtı işlenemedi") ||
            lower.contains("yaniti islenemedi") ||
            lower.contains("ai_invalid_response")
        ) {
            return AppErrorMessage(
                title = "AI yanıtı işlenemedi",
                message = "Analiz modeli yanıt verdi ancak sonuç beklenen formatta işlenemedi.",
                action = "Aynı analizi tekrar dene. Tekrar ederse destek koduyla birlikte bildir.",
                category = AppErrorCategory.AiInvalidResponse,
                supportID = supportID,
            )
        }

        if (lower.contains("row-level security") || lower.contains("rls") ||
            lower.contains("unauthorized") || lower.contains("403")
        ) {
            return AppErrorMessage(
                title = "Yetki kontrolü nedeniyle işlem yapılamadı",
                message = "Bu işlem için oturum veya veri erişim izni doğrulanamadı.",
                action = "Çıkış yapıp tekrar giriş yap. Sorun devam ederse destek koduyla birlikte bildir.",
                category = AppErrorCategory.StorageDenied,
                supportID = supportID,
            )
        }

        if (lower.contains("network") || lower.contains("internet") || lower.contains("offline") ||
            lower.contains("connection")
        ) {
            return AppErrorMessage(
                title = "Bağlantı sorunu",
                message = "İnternet bağlantısı veya servis erişimi kesildiği için işlem tamamlanamadı.",
                action = "Bağlantını kontrol edip tekrar dene.",
                category = AppErrorCategory.NetworkUnavailable,
                supportID = supportID,
            )
        }

        if (lower.contains("fotoğraf") && (lower.contains("indirilemedi") || lower.contains("download"))) {
            return AppErrorMessage(
                title = context ?: "Fotoğraf yüklenemedi",
                message = "Analiz fotoğrafı şu anda indirilemedi. Ekran yedek görselle açılabilir.",
                action = "Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir.",
                category = AppErrorCategory.StorageDenied,
                supportID = supportID,
            )
        }

        if (lower.contains("veri dışa aktar") || lower.contains("dışa aktarımı") || lower.contains("export")) {
            return AppErrorMessage(
                title = context ?: "Veri dışa aktarımı oluşturulamadı",
                message = "Verilerinin dışa aktarım dosyası hazırlanamadı.",
                action = "Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir.",
                category = AppErrorCategory.DatabaseFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("hesap silme talebi") || lower.contains("account deletion")) {
            return AppErrorMessage(
                title = context ?: "Hesap silme talebi kaydedilemedi",
                message = "Hesap silme talebin sunucuya kaydedilemedi.",
                action = "Kısa süre sonra tekrar dene. Sorun devam ederse destek koduyla bildir.",
                category = AppErrorCategory.DatabaseFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("indirilemedi") || lower.contains("download")) {
            return AppErrorMessage(
                title = context ?: "Rapor indirilemedi",
                message = "Kayıtlı PDF raporu indirilemedi veya paylaşım için hazırlanamadı.",
                action = "Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir.",
                category = AppErrorCategory.ReportArchiveFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("analiz") && (lower.contains("silinemedi") || lower.contains("delete"))) {
            return AppErrorMessage(
                title = context ?: "Analiz silinemedi",
                message = "Analiz ve ilişkili kayıtlar silinemedi.",
                action = "Liste korunur. Kısa süre sonra tekrar dene; sorun devam ederse destek koduyla bildir.",
                category = AppErrorCategory.DatabaseFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("rapor") && (lower.contains("silinemedi") || lower.contains("delete"))) {
            return AppErrorMessage(
                title = context ?: "Rapor silinemedi",
                message = "PDF raporu veya rapor arşiv kaydı silinemedi.",
                action = "Kısa süre sonra tekrar dene. Sorun devam ederse destek koduyla bildir.",
                category = AppErrorCategory.ReportArchiveFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("arşiv") || lower.contains("archive") || lower.contains("kaydedilemedi")) {
            return AppErrorMessage(
                title = context ?: "Rapor arşive kaydedilemedi",
                message = "PDF oluşturuldu ancak rapor arşivine kaydedilemedi.",
                action = "PDF açıldıysa dosyayı paylaşabilir, arşiv kaydı için daha sonra yeniden oluşturabilirsin.",
                category = AppErrorCategory.ReportArchiveFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("pdf") || lower.contains("rapor")) {
            return AppErrorMessage(
                title = context ?: "PDF oluşturulamadı",
                message = "PDF hazırlanırken bir sorun oluştu.",
                action = "Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir.",
                category = AppErrorCategory.PdfRenderFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("veritaban") || lower.contains("database") || lower.contains("schema") ||
            lower.contains("constraint") || lower.contains("enum")
        ) {
            return AppErrorMessage(
                title = "Veri kaydı tamamlanamadı",
                message = "Sunucuda veri kaydı veya veri okuma sırasında bir sorun oluştu.",
                action = "Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir.",
                category = AppErrorCategory.DatabaseFailed,
                supportID = supportID,
            )
        }

        if (raw.isNotEmpty() && raw.length < 140 && !raw.contains("{") && !raw.contains("HTTP")) {
            return AppErrorMessage(
                title = fallbackTitle,
                message = raw,
                action = "Girdiğini kontrol edip tekrar dene.",
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )
        }

        return AppErrorMessage(
            title = fallbackTitle,
            message = "Beklenmeyen bir sorun oluştu ve işlem tamamlanamadı.",
            action = "Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir.",
            category = AppErrorCategory.Unknown,
            supportID = supportID,
        )
    }

    fun isReportQuotaExceeded(rawMessage: String): Boolean {
        val lower = rawMessage.lowercase()
        return lower.contains("report_quota_exceeded") ||
            lower.contains("free_risk_analysis_trial_exhausted") ||
            (lower.contains("risk analizi") && lower.contains("deneme hakk")) ||
            lower.contains("aylık rapor kot") ||
            lower.contains("standart rapor hakk") ||
            (lower.contains("rapor") && lower.contains("limit") && lower.contains("dol"))
    }

    fun isFreeRiskAnalysisTrialExhausted(rawMessage: String): Boolean {
        val lower = rawMessage.lowercase()
        return lower.contains("free_risk_analysis_trial_exhausted") ||
            (lower.contains("risk analizi") && lower.contains("deneme hakk"))
    }
}
