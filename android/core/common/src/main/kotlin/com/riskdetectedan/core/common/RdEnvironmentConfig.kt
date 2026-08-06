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
    val supabaseAnonKey: String,
    val appVersionName: String,
    val appVersionCode: Int,
    val applicationId: String,
    // supabase/config.toml's auth.external.google.client_id — a *web* OAuth client id, not
    // Android-specific; this is the exact value Credential Manager's GetGoogleIdOption needs
    // to hand Supabase a verifiable ID token. It's already public (committed in config.toml,
    // not a secret) so defaulting production to the real value here is fine.
    val googleWebClientId: String = "200539603330-52rbngma5qs4717qnhff1rgr3pu9rv5i.apps.googleusercontent.com",
    val clientPlatform: String = "android",
    val clientCapabilities: Map<String, Boolean> = emptyMap(),
)
