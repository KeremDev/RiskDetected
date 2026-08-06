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
    val clientPlatform: String = "android",
    val clientCapabilities: Map<String, Boolean> = emptyMap(),
)
