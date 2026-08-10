package com.riskdetectedan.core.data.attribution

import android.content.Context
import android.net.Uri
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import com.revenuecat.purchases.Purchases
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Reads Play Install Referrer once without requesting AD_ID. Only allow-listed UTM values are
 * retained; the raw referrer is never logged or sent to crash reporting. RevenueCat receives the
 * same campaign fields after it has been configured with the Supabase user id.
 */
@Singleton
class InstallAttributionRepository @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun collectOnce() {
        if (preferences.getBoolean(KEY_CAPTURED, false)) return
        val client = InstallReferrerClient.newBuilder(context).build()
        runCatching {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    try {
                        when (responseCode) {
                            InstallReferrerClient.InstallReferrerResponse.OK -> {
                                val raw = runCatching { client.installReferrer.installReferrer }.getOrNull()
                                persist(parseInstallReferrer(raw))
                                preferences.edit().putBoolean(KEY_CAPTURED, true).apply()
                            }
                            InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED -> {
                                preferences.edit().putBoolean(KEY_CAPTURED, true).apply()
                            }
                        }
                    } finally {
                        client.endConnection()
                    }
                }

                override fun onInstallReferrerServiceDisconnected() = Unit
            })
        }.onFailure {
            runCatching { client.endConnection() }
        }
    }

    fun applyToRevenueCatIfConfigured() {
        val attributes = savedAttributes()
        if (attributes.isEmpty() || !Purchases.isConfigured) return
        val purchases = Purchases.sharedInstance
        attributes["utm_source"]?.let(purchases::setMediaSource)
        attributes["utm_campaign"]?.let(purchases::setCampaign)
        attributes["utm_term"]?.let(purchases::setKeyword)
        attributes["utm_content"]?.let(purchases::setCreative)
        attributes["utm_medium"]?.let { purchases.setAttributes(mapOf("utm_medium" to it)) }
    }

    fun savedAttributes(): Map<String, String> = ALLOWED_INSTALL_REFERRER_KEYS.mapNotNull { key ->
        preferences.getString(key, null)?.let { key to it }
    }.toMap()

    private fun persist(values: Map<String, String>) {
        preferences.edit().apply {
            values.forEach { (key, value) -> putString(key, value) }
        }.apply()
    }

    private companion object {
        const val PREFERENCES = "rd_install_attribution"
        const val KEY_CAPTURED = "captured"
    }
}

private val ALLOWED_INSTALL_REFERRER_KEYS =
    listOf("utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content")

internal fun parseInstallReferrer(raw: String?): Map<String, String> {
    if (raw.isNullOrBlank()) return emptyMap()
    val uri = runCatching { Uri.parse("https://riskdetected.invalid/?$raw") }.getOrNull()
        ?: return emptyMap()
    return ALLOWED_INSTALL_REFERRER_KEYS.mapNotNull { key ->
        uri.getQueryParameter(key)?.sanitizeAttributionValue()
            ?.takeIf(String::isNotBlank)
            ?.let { key to it }
    }.toMap()
}

private fun String.sanitizeAttributionValue(): String = trim()
    .replace(Regex("[^\\p{L}\\p{N} ._:@/+\\-]"), "")
    .take(120)
