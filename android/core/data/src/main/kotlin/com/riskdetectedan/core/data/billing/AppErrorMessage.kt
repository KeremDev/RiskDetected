package com.riskdetectedan.core.data.billing

import java.util.UUID

/**
 * Mirrors AppErrorMessage.swift — structured Title/Message/Action/Category/SupportID instead of
 * a raw error string. **Only the `makePurchase` path is ported in this slice** (paywall's
 * purchase/restore errors): the Swift file's general `make(rawMessage:)` (~30 substring
 * classifiers spanning quota/network/AI/storage/database/export/pdf/report-archive/auth) is a
 * much larger, screen-spanning error-UX system that would need wiring into every Android screen
 * that currently shows a raw `RdResult.Failure.message` — a bigger, separate slice, not silently
 * dropped, just not yet started. `RDLocalization` isn't ported either (Turkish-only hardcoded
 * strings here, same as everywhere else in this port); "App Store"/"Apple ID" wording is
 * mechanically substituted to "Google Play" (same substitution convention as the legal documents
 * — platform-accurate, not new content).
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
}
