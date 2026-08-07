package com.riskdetectedan.core.data.billing

import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesException
import com.revenuecat.purchases.PurchasesTransactionException

enum class PurchaseErrorKind {
    Cancelled,
    Network,
    ExistingSubscription,
    ReceiptConflict,
    StoreUnavailable,
    ProductUnavailable,
    PurchaseNotAllowed,
    Configuration,
    BackendVerification,
    PackageUnavailable,
    OperationInProgress,
    PaymentPending,
    Unknown,
}

data class PurchaseErrorClassification(
    val kind: PurchaseErrorKind,
    val rawMessage: String,
    val codeName: String?,
)

/**
 * Mirrors PurchaseErrorClassifier.swift's `Kind` taxonomy, but the Android SDK makes this
 * genuinely simpler to implement correctly, not just to port: RevenueCat's Android
 * [PurchasesException] hands back a typed [PurchasesErrorCode] enum directly, so there's no
 * NSError-domain/userInfo digging to reverse-engineer (iOS's `kind(forRevenueCatCode:)` numeric
 * fallback table — StoreKit/RevenueCat-iOS-specific raw NSError codes — has NO Android
 * equivalent and isn't ported; those numbers aren't meaningful on this platform, porting them
 * would silently misclassify real Android errors). [PurchasesTransactionException.userCancelled]
 * is an explicit boolean RevenueCat Android gives purchase-cancellation callers — more precise
 * than iOS's `CancellationError`-type-check + code-1 guessing.
 *
 * `classify(rawMessage:)` IS ported verbatim (same Turkish substring matches) — that function
 * classifies our own backend's/RevenueCat webhook's error strings, which are platform-neutral;
 * nothing about it is iOS-specific.
 */
object PurchaseErrorClassifier {
    fun classify(throwable: Throwable): PurchaseErrorClassification {
        if (throwable is PurchasesTransactionException && throwable.userCancelled) {
            return PurchaseErrorClassification(PurchaseErrorKind.Cancelled, "", null)
        }
        if (throwable is PurchasesException) {
            val codeName = throwable.code.name
            val kind = kindForErrorCode(throwable.code)
                ?: classifyRawMessage(throwable.message ?: "").kind
            return PurchaseErrorClassification(kind, (throwable.message ?: "").trim(), codeName)
        }
        return classifyRawMessage(throwable.message ?: "")
    }

    fun classifyRawMessage(rawMessage: String): PurchaseErrorClassification {
        val raw = rawMessage.trim()
        val lower = raw.lowercase()
        val kind = when {
            lower.contains("bu öğeye abonesiniz") ||
                lower.contains("bu ogeye abonesiniz") ||
                lower.contains("already subscribed") ||
                lower.contains("currently subscribed") ||
                lower.contains("already purchased") ||
                lower.contains("aktif bir riskdetected aboneliği") ||
                lower.contains("aktif bir riskdetected aboneligi") ||
                lower.contains("item already") ||
                lower.contains("product already") -> PurchaseErrorKind.ExistingSubscription

            lower.contains("revenuecat_owner_mismatch") ||
                lower.contains("revenuecat_purchase_predates_account") ||
                lower.contains("revenuecat_transfer_conflict") ||
                lower.contains("receipt_already_in_use") ||
                lower.contains("receipt in use") ||
                lower.contains("belongs to other user") ||
                lower.contains("farklı bir riskdetected hesab") ||
                lower.contains("farkli bir riskdetected hesab") ||
                lower.contains("başka bir hesap") ||
                lower.contains("baska bir hesap") -> PurchaseErrorKind.ReceiptConflict

            lower.contains("revenuecat_tier_mismatch") ||
                (lower.contains("seçilen plan") && lower.contains("doğrulanan plan")) ||
                (lower.contains("secilen plan") && lower.contains("dogrulanan plan")) ||
                lower.contains("backend tarafında doğrulanamadı") ||
                lower.contains("backend tarafinda dogrulanamadi") ||
                lower.contains("satın alma başarısı olarak işaretlemedi") ||
                lower.contains("satin alma basarisi olarak isaretlemedi") -> PurchaseErrorKind.BackendVerification

            lower.contains("abonelik paketi") && (
                lower.contains("bulunamadı") ||
                    lower.contains("bulunamadi") ||
                    lower.contains("hazırlanamadı") ||
                    lower.contains("hazirlanamadi")
                ) -> PurchaseErrorKind.PackageUnavailable

            else -> PurchaseErrorKind.Unknown
        }
        return PurchaseErrorClassification(kind, raw, null)
    }

    private fun kindForErrorCode(code: PurchasesErrorCode): PurchaseErrorKind? = when (code) {
        PurchasesErrorCode.PurchaseCancelledError -> PurchaseErrorKind.Cancelled
        PurchasesErrorCode.NetworkError -> PurchaseErrorKind.Network
        PurchasesErrorCode.ProductAlreadyPurchasedError -> PurchaseErrorKind.ExistingSubscription
        PurchasesErrorCode.ReceiptAlreadyInUseError -> PurchaseErrorKind.ReceiptConflict
        PurchasesErrorCode.StoreProblemError,
        PurchasesErrorCode.UnexpectedBackendResponseError,
        PurchasesErrorCode.UnknownBackendError,
        -> PurchaseErrorKind.StoreUnavailable
        PurchasesErrorCode.ProductNotAvailableForPurchaseError -> PurchaseErrorKind.ProductUnavailable
        PurchasesErrorCode.PurchaseNotAllowedError,
        PurchasesErrorCode.InsufficientPermissionsError,
        -> PurchaseErrorKind.PurchaseNotAllowed
        PurchasesErrorCode.InvalidCredentialsError,
        PurchasesErrorCode.ConfigurationError,
        PurchasesErrorCode.InvalidAppUserIdError,
        PurchasesErrorCode.InvalidAppleSubscriptionKeyError,
        -> PurchaseErrorKind.Configuration
        PurchasesErrorCode.InvalidReceiptError,
        PurchasesErrorCode.MissingReceiptFileError,
        PurchasesErrorCode.SignatureVerificationError,
        -> PurchaseErrorKind.BackendVerification
        PurchasesErrorCode.OperationAlreadyInProgressError -> PurchaseErrorKind.OperationInProgress
        PurchasesErrorCode.PaymentPendingError -> PurchaseErrorKind.PaymentPending
        else -> null
    }
}
