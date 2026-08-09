package com.riskdetectedan.core.common

enum class RdEnvironment { Staging, Production }

/**
 * Composition-root-provided config — populated by `:app`'s Hilt module from per-build-type
 * `BuildConfig` fields (master plan §9.2/§9.1: debug/qa -> staging, release -> production).
 * `core:*` modules only ever see this interface, never `BuildConfig` directly, so a `release`
 * build physically cannot resolve a staging URL and vice versa (§9.1 build-time assertion).
 *
 * [clientPlatform] is always `"android"` — sent on every backend request so `analyze` and
 * friends can do platform-aware allowlist matching (review doc F3: `clientBuildMatches` is
 * platform-aware; an Android client that ever sent platform-less requests would be the exact
 * bug F3 fixed). [clientCapabilities] mirrors the iOS `client_capabilities` contract (F5) —
 * starts empty until `contracts/mobile/api/client-capabilities.md` defines real keys in Faz 2.
 */
data class RdEnvironmentConfig(
    val environment: RdEnvironment,
    val supabaseUrl: String,
    val supabasePublishableKey: String,
    val appVersionName: String,
    val appVersionCode: Int,
    val applicationId: String,
    // supabase/config.toml's auth.external.google.client_id — a *web* OAuth client id, not
    // Android-specific; this is the exact value Credential Manager's GetGoogleIdOption needs
    // to hand Supabase a verifiable ID token. It's already public (committed in config.toml,
    // not a secret) so defaulting production to the real value here is fine.
    val googleWebClientId: String,
    val clientPlatform: String = "android",
    val clientCapabilities: Map<String, Boolean> = emptyMap(),
    // RevenueCat's Android *public* SDK key — same "already public, safe to default here" case
    // as googleWebClientId above (RDConfig.swift's own doc comment calls the iOS equivalent
    // "intentionally public"; subscription truth for backend limits is still synced
    // server-side via the RevenueCat webhook, this key alone can't grant entitlements).
    // Registered against the real Play Console app (com.riskdetectedan.app) 2026-08-07.
    val revenueCatPublicKey: String,
    // Matches RDConfig.Subscription.offeringIdentifier's default — "" would mean "use
    // whatever RevenueCat marks as current", but iOS pins an explicit id, so Android does too.
    val revenueCatOfferingIdentifier: String = "default",
    // Firebase project id (from google-services.json's project_info.project_id) — same shared
    // "riskdetected" Firebase project iOS already uses (its own APNs/phone-verification setup
    // predates Android). Stored on push_device_tokens.provider_environment (Android/FCM-only
    // column — "which Firebase project this token belongs to", per that column's own comment
    // in the migration) alongside every registered token, matches how iOS's environment column
    // records the APNs sandbox/production split. Not a secret — the project id also appears
    // plainly inside the committed google-services.json.
    val firebaseProjectId: String,
)
