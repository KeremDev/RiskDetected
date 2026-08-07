package com.riskdetectedan.core.data.billing

import android.app.Activity
import android.content.Context
import com.riskdetectedan.core.common.RdEnvironment
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.profile.SubscriptionTier
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
        val result = Purchases.sharedInstance.awaitPurchase(
            PurchaseParams.Builder(activity, billingPackage.revenueCatPackage).build(),
        )
        RdResult.Success(tierFromCustomerInfo(result.customerInfo))
    } catch (t: Throwable) {
        RdResult.Failure("billing_purchase_failed", t.message ?: "billing_purchase_failed", t)
    }

    suspend fun restorePurchases(): RdResult<SubscriptionTier> = try {
        val customerInfo = Purchases.sharedInstance.awaitRestore()
        RdResult.Success(tierFromCustomerInfo(customerInfo))
    } catch (t: Throwable) {
        RdResult.Failure("billing_restore_failed", t.message ?: "billing_restore_failed", t)
    }

    suspend fun currentTier(): RdResult<SubscriptionTier> = try {
        val customerInfo = Purchases.sharedInstance.awaitCustomerInfo()
        RdResult.Success(tierFromCustomerInfo(customerInfo))
    } catch (t: Throwable) {
        RdResult.Failure("billing_customer_info_failed", t.message ?: "billing_customer_info_failed", t)
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
