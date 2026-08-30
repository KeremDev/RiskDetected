package com.riskdetectedan.core.data.error

import com.riskdetectedan.core.common.RdClientMetadata
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
        get() = if (RdClientMetadata.APP_LANGUAGE == "en") {
            "$message\n\nWhat you can do: $action\n\nSupport code: $supportID"
        } else {
            "$message\n\nNe yapabilirsin: $action\n\nDestek kodu: $supportID"
        }
}

object AppErrorMessages {
    private val supportIdPattern = Regex("RD-[A-Z0-9]{8}")

    private fun localized(tr: String, en: String): String =
        if (RdClientMetadata.APP_LANGUAGE == "en") en else tr

    fun newSupportID(): String = "RD-" + UUID.randomUUID().toString().take(8).uppercase()

    private fun existingSupportID(text: String): String? =
        supportIdPattern.find(text.uppercase())?.value

    // ---- Purchases (feature #27, PurchaseErrorClassifier-backed) --------------------------

    fun makePurchase(
        throwable: Throwable,
        context: String = localized("Abonelik başlatılamadı", "Subscription could not be started"),
        fallbackTitle: String = localized("Abonelik başlatılamadı", "Subscription could not be started"),
    ): AppErrorMessage = makePurchase(PurchaseErrorClassifier.classify(throwable), context, fallbackTitle)

    fun makePurchase(
        classification: PurchaseErrorClassification,
        context: String = localized("Abonelik başlatılamadı", "Subscription could not be started"),
        fallbackTitle: String = localized("Abonelik başlatılamadı", "Subscription could not be started"),
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
                title = localized("Bağlantı sorunu", "Connection problem"),
                message = localized(
                    "İnternet bağlantısı veya abonelik servisi erişimi kesildiği için işlem tamamlanamadı.",
                    "The operation could not be completed because the internet connection or subscription service was unavailable.",
                ),
                action = localized("Bağlantını kontrol edip tekrar dene.", "Check your connection and try again."),
                category = AppErrorCategory.NetworkUnavailable,
                supportID = supportID,
            )

            PurchaseErrorKind.ExistingSubscription -> AppErrorMessage(
                title = context,
                message = localized(
                    "Bu Google Play hesabında aktif bir RiskDetected aboneliği görünüyor. Abonelik başka bir RiskDetected hesabına bağlıysa ücretli plan bu kullanıcıya otomatik açılmaz.",
                    "This Google Play account already has an active RiskDetected subscription. If it is linked to another RiskDetected account, the paid plan cannot be activated automatically for this user.",
                ),
                action = localized(
                    "Aboneliği satın aldığın RiskDetected hesabıyla giriş yapıp Geri yükle seçeneğini kullan veya destekle iletişime geç.",
                    "Sign in with the RiskDetected account used for the purchase and select Restore, or contact support.",
                ),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.ReceiptConflict -> AppErrorMessage(
                title = context,
                message = localized(
                    "Bu Google Play aboneliği başka bir RiskDetected hesabına bağlı. Lütfen aboneliği satın aldığın hesapla giriş yap veya destekle iletişime geç.",
                    "This Google Play subscription is linked to another RiskDetected account. Sign in with the account used for the purchase or contact support.",
                ),
                action = localized(
                    "Doğru RiskDetected hesabıyla giriş yapıp Geri yükle seçeneğini kullan. Emin değilsen destek koduyla bize ulaş.",
                    "Sign in with the correct RiskDetected account and select Restore. If unsure, contact us with the support code.",
                ),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.BackendVerification -> AppErrorMessage(
                title = context,
                message = raw.ifEmpty {
                    localized(
                        "Google Play aboneliği doğrulandı ancak uygulama planı güvenli şekilde eşleştirilemedi.",
                        "The Google Play subscription was verified, but the app plan could not be matched securely.",
                    )
                },
                action = localized(
                    "Birkaç saniye sonra tekrar dene veya Geri yükle seçeneğiyle aboneliği doğrula.",
                    "Try again in a few seconds or verify the subscription with Restore.",
                ),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.PackageUnavailable -> AppErrorMessage(
                title = context,
                message = localized("Seçilen abonelik paketi şu an hazırlanamadı.", "The selected subscription package is currently unavailable."),
                action = localized("Kısa süre sonra tekrar dene. Sorun devam ederse Geri yükle veya destek ile iletişime geç.", "Try again shortly. If the problem continues, use Restore or contact support."),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.StoreUnavailable -> AppErrorMessage(
                title = context,
                message = localized("Google Play abonelik servisi şu anda satın alma işlemini tamamlayamadı.", "Google Play could not complete the purchase at this time."),
                action = localized("Kısa süre sonra tekrar dene. Google Play ödeme penceresi açılmıyorsa abonelik durumunu kontrol et.", "Try again shortly. If the Google Play payment window does not open, check your subscription status."),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.ProductUnavailable -> AppErrorMessage(
                title = context,
                message = localized("Seçilen abonelik ürünü Google Play tarafından satın almaya uygun görünmüyor.", "The selected subscription product is not currently available for purchase on Google Play."),
                action = localized("Biraz sonra tekrar dene. Sorun devam ederse ürün yapılandırması kontrol edilmelidir.", "Try again later. If the problem continues, the product configuration may need to be checked."),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.PurchaseNotAllowed -> AppErrorMessage(
                title = context,
                message = localized("Bu cihaz veya Google Play hesabı şu anda uygulama içi satın almaya izin vermiyor.", "This device or Google Play account does not currently allow in-app purchases."),
                action = localized("Google Play hesap, ödeme ve ebeveyn denetimi ayarlarını kontrol edip tekrar dene.", "Check the Google Play account, payment, and parental-control settings, then try again."),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.Configuration -> AppErrorMessage(
                title = context,
                message = localized("Abonelik doğrulaması için gerekli Google Play veya RevenueCat yapılandırması tamamlanamadı.", "The Google Play or RevenueCat configuration required to verify the subscription is incomplete."),
                action = localized("Uygulamayı kapatıp açarak tekrar dene. Devam ederse destek koduyla bildir.", "Restart the app and try again. If it continues, report it with the support code."),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.OperationInProgress -> AppErrorMessage(
                title = context,
                message = localized("Bu abonelik için başka bir satın alma işlemi hâlâ devam ediyor.", "Another purchase for this subscription is still in progress."),
                action = localized("Google Play penceresinin tamamlanmasını bekle veya birkaç saniye sonra tekrar dene.", "Wait for the Google Play window to finish or try again in a few seconds."),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.PaymentPending -> AppErrorMessage(
                title = context,
                message = localized("Satın alma Google Play tarafında beklemede görünüyor.", "The purchase is pending on Google Play."),
                action = localized("Ödeme onayı tamamlandığında aboneliğin otomatik güncellenir. Gerekirse Geri yükle seçeneğini kullan.", "Your subscription will update automatically after payment approval. Use Restore if needed."),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )

            PurchaseErrorKind.Unknown -> AppErrorMessage(
                title = fallbackTitle,
                message = if (RdClientMetadata.APP_LANGUAGE == "en") {
                    localized("Satın alma işlemi tamamlanamadı.", "The purchase could not be completed.")
                } else {
                    raw.ifEmpty { "Satın alma işlemi tamamlanamadı." }
                },
                action = localized("Tekrar dene. Sorun devam ederse destek koduyla birlikte bize ulaş.", "Try again. If the problem continues, contact us with the support code."),
                category = AppErrorCategory.Unknown,
                supportID = supportID,
            )
        }
    }

    // ---- General app-wide classifier (mirrors AppErrorMessage.swift's `make(rawMessage:)`) --

    fun make(
        throwable: Throwable,
        context: String? = null,
        fallbackTitle: String = localized("İşlem tamamlanamadı", "Operation could not be completed"),
    ): AppErrorMessage = make(throwable.message ?: "", context, fallbackTitle)

    fun make(
        rawMessage: String,
        context: String? = null,
        fallbackTitle: String = localized("İşlem tamamlanamadı", "Operation could not be completed"),
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
                title = context ?: localized("Bağlantı sorunu", "Connection problem"),
                message = localized("Sunucuya bağlanırken zaman aşımı oluştu.", "The connection to the server timed out."),
                action = localized("Bağlantını kontrol edip tekrar dene.", "Check your connection and try again."),
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
                title = context ?: localized("Kod gönderilemedi", "Code could not be sent"),
                message = localized("Doğrulama kodu gönderilirken sunucu tarafında geçici bir sorun oluştu.", "A temporary server problem occurred while sending the verification code."),
                action = localized("Birkaç saniye bekleyip tekrar dene.", "Wait a few seconds and try again."),
                category = AppErrorCategory.Unknown,
                supportID = supportID,
            )
        }

        if (isFreeRiskAnalysisTrialExhausted(rawMessage)) {
            return AppErrorMessage(
                title = localized("Risk analizi hakkı kullanıldı", "Risk assessment allowance used"),
                message = localized("Bir kez tanımlanan risk analizi tablosu hakkını kullandın.", "You have used the one-time risk assessment table allowance."),
                action = localized("Risk analizi tablolarını kullanmaya devam etmek için Plus veya Pro'ya geç.", "Upgrade to Plus or Pro to continue using risk assessment tables."),
                category = AppErrorCategory.QuotaExceeded,
                supportID = supportID,
            )
        }

        if (isReportQuotaExceeded(rawMessage)) {
            return AppErrorMessage(
                title = localized("Rapor limiti doldu", "Report limit reached"),
                message = localized("Bu plan için rapor oluşturma limitin dolmuş görünüyor.", "The report creation limit for this plan has been reached."),
                action = localized("Bir üst plana yükselt veya yeni kota dönemini bekle.", "Upgrade your plan or wait for the next quota period."),
                category = AppErrorCategory.QuotaExceeded,
                supportID = supportID,
            )
        }

        if (lower.contains("arka planda devam ediyor") ||
            lower.contains("geçmiş analizler") ||
            lower.contains("gecmis analizler") ||
            lower.contains("continuing in the background") ||
            lower.contains("analysis history")
        ) {
            return AppErrorMessage(
                title = localized("Analiz arka planda devam ediyor", "Analysis is continuing in the background"),
                message = if (RdClientMetadata.APP_LANGUAGE == "en") {
                    "The analysis is still continuing in the background."
                } else {
                    raw.lineSequence().firstOrNull() ?: "Analiz arka planda devam ediyor."
                },
                action = localized("Aynı analizi tekrar başlatmadan önce Geçmiş analizler ekranını birkaç dakika sonra yenile.", "Refresh Analysis History in a few minutes before starting the same analysis again."),
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
            lower.contains("ücretsiz analiz hakk") ||
            lower.contains("daily analysis quota") ||
            lower.contains("free analysis allowance")
        if (isDailyQuota) {
            val isFreeQuota = lower.contains("ücretsiz") || lower.contains("free")
            return AppErrorMessage(
                title = localized("Analiz hakkı doldu", "Analysis limit reached"),
                message = if (RdClientMetadata.APP_LANGUAGE == "en") {
                    "Your analysis quota appears to be exhausted."
                } else {
                    raw.lineSequence().firstOrNull() ?: "Analiz kotan dolmuş görünüyor."
                },
                action = if (isFreeQuota) {
                    localized("Plus veya Pro ile devam edebilirsin.", "You can continue with Plus or Pro.")
                } else {
                    localized("Plan kotan yenilenene kadar bekle veya daha üst plana geç.", "Wait for your plan quota to renew or upgrade to a higher plan.")
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
                title = context ?: localized("E-posta adresi geçerli değil", "Email address is not valid"),
                message = localized("E-posta adresi doğrulanamadı.", "The email address could not be validated."),
                action = localized("Geçerli ve erişebildiğin bir e-posta adresi girip tekrar kod gönder.", "Enter a valid email address you can access and send the code again."),
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
                title = context ?: localized("Kod gönderme sınırı", "Code request limit"),
                message = localized("Kısa süre içinde çok fazla e-posta kodu istendiği için yeni kod gönderilemiyor.", "A new code cannot be sent because too many email codes were requested in a short time."),
                action = localized("Birkaç dakika bekleyip tekrar dene. Gerekirse son gönderilen kodu kontrol et.", "Wait a few minutes and try again. You can also check the most recently sent code."),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("cannot find a matching credential") ||
            lower.contains("no matching credential") ||
            lower.contains("no credential available") ||
            (lower.contains("one tap") && lower.contains("credential"))
        ) {
            return AppErrorMessage(
                title = context ?: localized("Google ile giriş yapılamadı", "Could not sign in with Google"),
                message = localized("Bu cihazda seçilebilecek bir Google hesabı bulunamadı.", "No selectable Google account was found on this device."),
                action = localized("Cihaza bir Google hesabı ekleyip tekrar dene veya e-posta ile giriş yap.", "Add a Google account to the device and try again, or sign in by email."),
                category = AppErrorCategory.AuthRequired,
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
                title = context ?: localized("Kodun süresi doldu", "Code expired"),
                message = localized("Girdiğin doğrulama kodu artık geçerli değil.", "The verification code you entered is no longer valid."),
                action = localized("Yeni bir kod isteyip e-postana gelen son kodla tekrar dene.", "Request a new code and try again with the latest code in your email."),
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
                title = context ?: localized("Kod doğrulanamadı", "Code could not be verified"),
                message = localized("Girdiğin doğrulama kodu eşleşmedi.", "The verification code you entered did not match."),
                action = localized("Kodu e-postadaki son haliyle kontrol et veya yeni kod iste.", "Check the latest code in your email or request a new one."),
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
                title = localized("AI servisi yoğun", "AI service is busy"),
                message = localized("AI sağlayıcısı şu anda isteği kabul etmedi. Bu genellikle geçici kota veya yoğunluk durumlarında olur.", "The AI provider did not accept the request. This is usually caused by temporary rate limits or high demand."),
                action = localized("Biraz bekleyip tekrar dene. Tekrar ederse farklı analiz odağıyla veya daha küçük fotoğrafla deneyebilirsin.", "Wait briefly and try again. If it repeats, try a different analysis focus or a smaller photo."),
                category = AppErrorCategory.AiRateLimited,
                supportID = supportID,
            )
        }

        if (lower.contains("503") || lower.contains("unavailable") || lower.contains("yoğun") ||
            lower.contains("timeout") || lower.contains("timed out")
        ) {
            return AppErrorMessage(
                title = localized("AI servisi geçici olarak yanıt vermiyor", "AI service is temporarily unavailable"),
                message = localized("Analiz modeli şu anda yoğun veya geçici olarak erişilemiyor.", "The analysis model is busy or temporarily unavailable."),
                action = localized("Kısa süre sonra tekrar dene. Fotoğraf ve seçtiğin analiz odağı korunuyorsa işlemi yeniden başlatabilirsin.", "Try again shortly. If your photo and analysis focus are still available, restart the operation."),
                category = AppErrorCategory.AiUnavailable,
                supportID = supportID,
            )
        }

        if (lower.contains("output_language_contract_failed")) {
            return AppErrorMessage(
                title = localized("AI yanıtı işlenemedi", "AI response could not be processed"),
                message = localized("Analiz, seçilen çıktı diliyle güvenli biçimde tamamlanamadı. Lütfen tekrar dene.", "The analysis could not be completed safely in the selected output language. Please try again."),
                action = localized("Aynı analizi tekrar dene. Tekrar ederse destek koduyla birlikte bildir.", "Try the same analysis again. If it repeats, report it with the support code."),
                category = AppErrorCategory.AiInvalidResponse,
                supportID = supportID,
            )
        }

        if (lower.contains("yanıtı işlenemedi") ||
            lower.contains("yaniti islenemedi") ||
            lower.contains("ai_invalid_response")
        ) {
            return AppErrorMessage(
                title = localized("AI yanıtı işlenemedi", "AI response could not be processed"),
                message = localized("Analiz modeli yanıt verdi ancak sonuç beklenen formatta işlenemedi.", "The analysis model responded, but the result was not in the expected format."),
                action = localized("Aynı analizi tekrar dene. Tekrar ederse destek koduyla birlikte bildir.", "Try the same analysis again. If it repeats, report it with the support code."),
                category = AppErrorCategory.AiInvalidResponse,
                supportID = supportID,
            )
        }

        if (lower.contains("row-level security") || lower.contains("rls") ||
            lower.contains("unauthorized") || lower.contains("403")
        ) {
            return AppErrorMessage(
                title = localized("Yetki kontrolü nedeniyle işlem yapılamadı", "Operation blocked by access control"),
                message = localized("Bu işlem için oturum veya veri erişim izni doğrulanamadı.", "The session or data-access permission for this operation could not be verified."),
                action = localized("Çıkış yapıp tekrar giriş yap. Sorun devam ederse destek koduyla birlikte bildir.", "Sign out and sign in again. If the problem continues, report it with the support code."),
                category = AppErrorCategory.StorageDenied,
                supportID = supportID,
            )
        }

        if (lower.contains("network") || lower.contains("internet") || lower.contains("offline") ||
            lower.contains("connection")
        ) {
            return AppErrorMessage(
                title = localized("Bağlantı sorunu", "Connection problem"),
                message = localized("İnternet bağlantısı veya servis erişimi kesildiği için işlem tamamlanamadı.", "The operation could not be completed because the internet connection or service was unavailable."),
                action = localized("Bağlantını kontrol edip tekrar dene.", "Check your connection and try again."),
                category = AppErrorCategory.NetworkUnavailable,
                supportID = supportID,
            )
        }

        if (lower.contains("fotoğraf") && (lower.contains("indirilemedi") || lower.contains("download"))) {
            return AppErrorMessage(
                title = context ?: localized("Fotoğraf yüklenemedi", "Photo could not be loaded"),
                message = localized("Analiz fotoğrafı şu anda indirilemedi. Ekran yedek görselle açılabilir.", "The analysis photo could not be downloaded. The screen may open with a fallback image."),
                action = localized("Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir.", "Check your connection and try again. If the problem continues, report it with the support code."),
                category = AppErrorCategory.StorageDenied,
                supportID = supportID,
            )
        }

        if (lower.contains("veri dışa aktar") || lower.contains("dışa aktarımı") || lower.contains("export")) {
            return AppErrorMessage(
                title = context ?: localized("Veri dışa aktarımı oluşturulamadı", "Data export could not be created"),
                message = localized("Verilerinin dışa aktarım dosyası hazırlanamadı.", "Your data export file could not be prepared."),
                action = localized("Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir.", "Check your connection and try again. If the problem continues, report it with the support code."),
                category = AppErrorCategory.DatabaseFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("hesap silme talebi") || lower.contains("account deletion")) {
            return AppErrorMessage(
                title = context ?: localized("Hesap silme talebi kaydedilemedi", "Account deletion request could not be saved"),
                message = localized("Hesap silme talebin sunucuya kaydedilemedi.", "Your account deletion request could not be saved on the server."),
                action = localized("Kısa süre sonra tekrar dene. Sorun devam ederse destek koduyla bildir.", "Try again shortly. If the problem continues, report it with the support code."),
                category = AppErrorCategory.DatabaseFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("indirilemedi") || lower.contains("download")) {
            return AppErrorMessage(
                title = context ?: localized("Rapor indirilemedi", "Report could not be downloaded"),
                message = localized("Kayıtlı PDF raporu indirilemedi veya paylaşım için hazırlanamadı.", "The saved PDF report could not be downloaded or prepared for sharing."),
                action = localized("Bağlantını kontrol edip tekrar dene. Sorun devam ederse destek koduyla bildir.", "Check your connection and try again. If the problem continues, report it with the support code."),
                category = AppErrorCategory.ReportArchiveFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("analiz") && (lower.contains("silinemedi") || lower.contains("delete"))) {
            return AppErrorMessage(
                title = context ?: localized("Analiz silinemedi", "Analysis could not be deleted"),
                message = localized("Analiz ve ilişkili kayıtlar silinemedi.", "The analysis and its related records could not be deleted."),
                action = localized("Liste korunur. Kısa süre sonra tekrar dene; sorun devam ederse destek koduyla bildir.", "The list remains unchanged. Try again shortly; if the problem continues, report it with the support code."),
                category = AppErrorCategory.DatabaseFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("rapor") && (lower.contains("silinemedi") || lower.contains("delete"))) {
            return AppErrorMessage(
                title = context ?: localized("Rapor silinemedi", "Report could not be deleted"),
                message = localized("PDF raporu veya rapor arşiv kaydı silinemedi.", "The PDF report or report archive record could not be deleted."),
                action = localized("Kısa süre sonra tekrar dene. Sorun devam ederse destek koduyla bildir.", "Try again shortly. If the problem continues, report it with the support code."),
                category = AppErrorCategory.ReportArchiveFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("arşiv") || lower.contains("archive") || lower.contains("kaydedilemedi")) {
            return AppErrorMessage(
                title = context ?: localized("Rapor arşive kaydedilemedi", "Report could not be saved to the archive"),
                message = localized("PDF oluşturuldu ancak rapor arşivine kaydedilemedi.", "The PDF was created but could not be saved to the report archive."),
                action = localized("PDF açıldıysa dosyayı paylaşabilir, arşiv kaydı için daha sonra yeniden oluşturabilirsin.", "If the PDF opened, you can share it and recreate it later to save an archive record."),
                category = AppErrorCategory.ReportArchiveFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("pdf") || lower.contains("rapor")) {
            return AppErrorMessage(
                title = context ?: localized("PDF oluşturulamadı", "PDF could not be created"),
                message = localized("PDF hazırlanırken bir sorun oluştu.", "A problem occurred while preparing the PDF."),
                action = localized("Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir.", "Try again. If the problem continues, report it with the support code."),
                category = AppErrorCategory.PdfRenderFailed,
                supportID = supportID,
            )
        }

        if (lower.contains("veritaban") || lower.contains("database") || lower.contains("schema") ||
            lower.contains("constraint") || lower.contains("enum")
        ) {
            return AppErrorMessage(
                title = localized("Veri kaydı tamamlanamadı", "Data operation could not be completed"),
                message = localized("Sunucuda veri kaydı veya veri okuma sırasında bir sorun oluştu.", "A problem occurred while saving or reading data on the server."),
                action = localized("Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir.", "Try again. If the problem continues, report it with the support code."),
                category = AppErrorCategory.DatabaseFailed,
                supportID = supportID,
            )
        }

        if (raw.isNotEmpty() && raw.length < 140 && !raw.contains("{") && !raw.contains("HTTP")) {
            return AppErrorMessage(
                title = fallbackTitle,
                message = if (RdClientMetadata.APP_LANGUAGE == "en") {
                    localized("İşlem tamamlanamadı.", "The operation could not be completed.")
                } else {
                    raw
                },
                action = localized("Girdiğini kontrol edip tekrar dene.", "Check your input and try again."),
                category = AppErrorCategory.ValidationFailed,
                supportID = supportID,
            )
        }

        return AppErrorMessage(
            title = fallbackTitle,
            message = localized("Beklenmeyen bir sorun oluştu ve işlem tamamlanamadı.", "An unexpected problem occurred and the operation could not be completed."),
            action = localized("Tekrar dene. Sorun devam ederse destek koduyla birlikte bildir.", "Try again. If the problem continues, report it with the support code."),
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
            lower.contains("monthly report quota") ||
            lower.contains("report allowance") ||
            (lower.contains("rapor") && lower.contains("limit") && lower.contains("dol"))
    }

    fun isFreeRiskAnalysisTrialExhausted(rawMessage: String): Boolean {
        val lower = rawMessage.lowercase()
        return lower.contains("free_risk_analysis_trial_exhausted") ||
            (lower.contains("risk analizi") && lower.contains("deneme hakk")) ||
            (lower.contains("risk assessment") && lower.contains("trial allowance"))
    }
}
