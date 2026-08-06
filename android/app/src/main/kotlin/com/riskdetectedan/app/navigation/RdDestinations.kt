package com.riskdetectedan.app.navigation

import kotlinx.serialization.Serializable

/**
 * Type-safe Navigation Compose routes (review Ç7: kotlinx.serialization routes, not Nav3 —
 * decided as not-yet-GA at plan time). One object per top-level destination; add data classes
 * with typed args here as real flows replace the Faz-1 placeholders.
 */
@Serializable object Onboarding
@Serializable object Auth
@Serializable object Home
@Serializable object Capture

/** photoPath null until Capture hands off a file — matches Analysis being reachable directly
 * from Home too (sector-first flow) as well as from Capture (photo-first flow). */
@Serializable data class Analysis(val photoPath: String? = null)
@Serializable object Reports
@Serializable object Profile
@Serializable object Companies
@Serializable object Paywall
