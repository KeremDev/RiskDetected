package com.riskdetectedan.core.data.billing

import android.app.Activity
import android.content.Context
import com.riskdetectedan.core.common.RdEnvironment
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.revenuecat.purchases.CacheFetchPolicy
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitLogIn
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/** A purchasable package as this client actually needs it — trimmed mirror of
 * SubscriptionManager.swift's `SubscriptionPlanPackage`. [revenueCatPackage] is kept alongside
 * so [BillingRepository.purchase] can hand it straight back to the SDK without a second lookup. */
data class BillingPackage(
    val id: String,
    val tier: SubscriptionTier,
    val productId: String,
    val formattedPrice: String,
    val revenueCatPackage: Package,
)

/**
 * Wraps the RevenueCat Android SDK, mirroring `SubscriptionManager.swift`'s contract closely
 * enough that both platforms grant the same entitlement for the same purchase: same appUserID
 * convention (the Supabase user's UUID, lowercased — required for a Plus/Pro purchase made on
 * one platform to be recognized on the other), same entitlement identifiers ("plus"/"pro"),
 * same product-identifier fallback ("riskdetected_plus_monthly"/"_yearly",
 * "riskdetected_pro_monthly"/"_yearly" — DEC-14: Play product IDs must be identical to the App
 * Store ones already live on iOS).
 *
 * **Client-side signal only** — matches the "backend is the single entitlement authority"
 * invariant repeated across this port (master §37): what this repository resolves from
 * [CustomerInfo] is for immediate UI feedback (e.g. "you're Pro now" right after a purchase),
 * never the source of truth for gating a feature. The real `profiles.tier` a paid feature
 * actually checks is written server-side by the RevenueCat webhook, same as iOS.
 */
@Singleton
class BillingRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val environmentConfig: RdEnvironmentConfig,
) {
    private var isConfigured = false
    private var currentAppUserId: String? = null

    /** Idempotent, same shape as `configureIfNeeded(appUserID:)` — configures once per process
     * with the signed-in user's id as the RevenueCat appUserID, or logs in if a different user
     * is now signed in (matches iOS's currentAppUserID-diffing branch in `identify(userID:)`). */
    suspend fun configure(userId: String): RdResult<Unit> {
        if (environmentConfig.revenueCatPublicKey.isBlank()) {
            return RdResult.Failure(
                code = "billing_not_configured",
                message = "Bu ortam için RevenueCat yapılandırması tamamlanmamış.",
            )
        }
        val appUserId = userId.lowercase()
        if (!isConfigured) {
            if (environmentConfig.environment == RdEnvironment.Staging) {
                Purchases.logLevel = LogLevel.DEBUG
            }
            Purchases.configure(
                PurchasesConfiguration.Builder(context, environmentConfig.revenueCatPublicKey)
                    .appUserID(appUserId)
                    .build(),
            )
            isConfigured = true
            currentAppUserId = appUserId
            return RdResult.Success(Unit)
        }
        if (currentAppUserId == appUserId) return RdResult.Success(Unit)
        return try {
            Purchases.sharedInstance.awaitLogIn(appUserId)
            currentAppUserId = appUserId
            RdResult.Success(Unit)
        } catch (t: Throwable) {
            RdResult.Failure("billing_login_failed", t.message ?: "billing_login_failed", t)
        }
    }

    /** Mirrors `loadOfferings()` — reads the pinned offering id (not "current"), same as iOS. */
    suspend fun fetchPackages(): RdResult<List<BillingPackage>> = try {
        val offerings = Purchases.sharedInstance.awaitOfferings()
        val offeringId = environmentConfig.revenueCatOfferingIdentifier.trim()
        val offering = offeringId.ifEmpty { null }?.let { offerings.get(it) } ?: offerings.current
        val packages = offering?.availablePackages.orEmpty().mapNotNull { pkg ->
            val tier = tierForProductId(pkg.product.id) ?: return@mapNotNull null
            BillingPackage(
                id = pkg.identifier,
                tier = tier,
                productId = pkg.product.id,
                formattedPrice = pkg.product.price.formatted,
                revenueCatPackage = pkg,
            )
        }
        RdResult.Success(packages)
    } catch (t: Throwable) {
        RdResult.Failure("billing_offerings_failed", t.message ?: "billing_offerings_failed", t)
    }

    /** [activity] is required by RevenueCat's own `PurchaseParams.Builder` (launches Google
     * Play's billing sheet) — this is the one billing call that can't stay Activity-free, same
     * reasoning as `GoogleAuthClient.requestIdToken(context)` in feature:onboarding: the
     * Activity is supplied by the caller at the point of use, not held or injected here. */
    suspend fun purchase(activity: Activity, billingPackage: BillingPackage): RdResult<SubscriptionTier> = try {
        preCheckAlreadyEntitled(billingPackage.tier)?.let { return it }

        val result = Purchases.sharedInstance.awaitPurchase(
            PurchaseParams.Builder(activity, billingPackage.revenueCatPackage).build(),
        )
        val tier = tierFromCustomerInfo(result.customerInfo)
        validateReceiptOwner(result.customerInfo, tier) ?: RdResult.Success(tier)
    } catch (t: Throwable) {
        RdResult.Failure("billing_purchase_failed", t.message ?: "billing_purchase_failed", t)
    }

    /**
     * Real port of `purchase(packageID:)`'s pre-purchase reconciliation — previously documented
     * as a deliberately deferred gap alongside [validateReceiptOwner] (that one shipped first as
     * the safety-critical half; this is the UX-polish half). Two real cases this avoids: buying a
     * tier the account already has (a real, if harmless, double-charge risk without this check —
     * Google Play would likely reject it as `ProductAlreadyPurchasedError`, but surfacing that as
     * a *success* the way iOS does is a better experience than a purchase-failed error for
     * something that isn't actually a failure), and buying a *lower* tier while a higher one is
     * already active (Free-tier confusion the user almost certainly didn't intend). Not merged
     * into [validateReceiptOwner] — that one validates *after* a purchase/restore attempt
     * resolves; this one runs *before*, deciding whether to attempt the purchase call at all.
     */
    private suspend fun preCheckAlreadyEntitled(expectedTier: SubscriptionTier): RdResult<SubscriptionTier>? {
        val customerInfo = try {
            Purchases.sharedInstance.awaitCustomerInfo(CacheFetchPolicy.FETCH_CURRENT)
        } catch (t: Throwable) {
            return null
        }
        val currentTier = tierFromCustomerInfo(customerInfo)
        if (!currentTier.isPaid) return null
        validateReceiptOwner(customerInfo, currentTier)?.let { return it }

        if (currentTier == expectedTier) return RdResult.Success(currentTier)
        if (currentTier.rank > expectedTier.rank) {
            return RdResult.Failure(
                code = "billing_higher_tier_already_active",
                message = "Bu Google Play hesabında zaten daha üst bir RiskDetected aboneliği (${currentTier.name}) aktif.",
            )
        }
        return null
    }

    suspend fun restorePurchases(): RdResult<SubscriptionTier> = try {
        val customerInfo = Purchases.sharedInstance.awaitRestore()
        val tier = tierFromCustomerInfo(customerInfo)
        validateReceiptOwner(customerInfo, tier) ?: RdResult.Success(tier)
    } catch (t: Throwable) {
        RdResult.Failure("billing_restore_failed", t.message ?: "billing_restore_failed", t)
    }

    suspend fun currentTier(): RdResult<SubscriptionTier> = try {
        val customerInfo = Purchases.sharedInstance.awaitCustomerInfo()
        val tier = tierFromCustomerInfo(customerInfo)
        validateReceiptOwner(customerInfo, tier) ?: RdResult.Success(tier)
    } catch (t: Throwable) {
        RdResult.Failure("billing_customer_info_failed", t.message ?: "billing_customer_info_failed", t)
    }

    /**
     * Real port of `SubscriptionManager.swift`'s `validateReceiptOwner` — previously entirely
     * missing on Android (a real gap, not a deliberate simplification). Without this, a paid
     * tier resolved from [CustomerInfo] could silently belong to a *different* RiskDetected
     * account than the one currently signed in (e.g. a shared/reused Google Play account whose
     * subscription was originally purchased under someone else's account) — this app would then
     * show "you're Pro" client-side for the wrong user. The real feature gate
     * (`profiles.tier`) is written server-side by the RevenueCat webhook using RevenueCat's own
     * account-linking data, so this can't actually smuggle a paid feature past the backend
     * (master §37, "backend is sole authority" — unaffected either way) — but leaving the
     * mismatch undetected client-side would let a confusing, wrong "you're Pro!" UI moment
     * happen with no explanation and no path to resolve it, which is the real problem this
     * guard exists to catch and message clearly instead.
     *
     * The message text ("revenuecat_owner_mismatch: ...") is deliberately the exact magic
     * substring [PurchaseErrorClassifier.classifyRawMessage] already recognizes (mapped to
     * [PurchaseErrorKind.ReceiptConflict], with a ready Turkish message in
     * `AppErrorMessages.makePurchase` since feature #27) — that plumbing existed already and was
     * simply never triggered from anywhere; this is the missing trigger, not new UI.
     */
    private fun validateReceiptOwner(customerInfo: CustomerInfo, tier: SubscriptionTier): RdResult.Failure? {
        if (tier == SubscriptionTier.Free) return null
        val appUserId = currentAppUserId ?: return null
        val original = customerInfo.originalAppUserId.lowercase()
        if (original.startsWith("\$rcanonymousid:")) return null
        if (original == appUserId) return null
        return RdResult.Failure(
            code = "billing_receipt_owner_mismatch",
            message = "revenuecat_owner_mismatch: bu Google Play hesabındaki abonelik başka bir " +
                "RiskDetected hesabına bağlı.",
        )
    }

    /** Same precedence as `SubscriptionManager.swift`'s `state(from:)`: entitlement check first
     * ("pro" before "plus", higher tier wins), product-id fallback isn't needed here since
     * [tierForProductId] already only feeds tier-tagged packages into [fetchPackages] — this
     * mirrors the entitlement-only branch of the Swift function. */
    private fun tierFromCustomerInfo(customerInfo: CustomerInfo): SubscriptionTier = when {
        customerInfo.entitlements.active.containsKey(PRO_ENTITLEMENT_ID) -> SubscriptionTier.Pro
        customerInfo.entitlements.active.containsKey(PLUS_ENTITLEMENT_ID) -> SubscriptionTier.Plus
        else -> SubscriptionTier.Free
    }

    /** Prefix match, not exact — Android Billing Library 5+ subscriptions have base plans, and
     * RevenueCat's `StoreProduct.id` on Google Play can come back as `"$productId:$basePlanId"`
     * rather than the bare product id iOS's StoreKit uses. Play Console products are still
     * created with the exact `riskdetected_{plus,pro}_{monthly,yearly}` ids (DEC-14 parity with
     * the live App Store ids) — this just doesn't assume Android echoes that id back unchanged. */
    private fun tierForProductId(productId: String): SubscriptionTier? = when {
        productId.startsWith("riskdetected_pro") -> SubscriptionTier.Pro
        productId.startsWith("riskdetected_plus") -> SubscriptionTier.Plus
        else -> null
    }

    private companion object {
        const val PLUS_ENTITLEMENT_ID = "plus"
        const val PRO_ENTITLEMENT_ID = "pro"
    }
}
