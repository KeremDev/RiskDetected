package com.riskdetectedan.app.navigation

import kotlinx.serialization.Serializable

/**
 * Type-safe Navigation Compose routes (review Ç7: kotlinx.serialization routes, not Nav3 —
 * decided as not-yet-GA at plan time). One object per top-level destination; add data classes
 * with typed args here as real flows replace the Faz-1 placeholders.
 */
@Serializable object Onboarding
@Serializable object Auth

/** Mirrors MainTabView.swift's role — the persistent 4-tab shell (Home/Analizler/Raporlar/Profil,
 * see [RdTab]) + floating quick-scan button (RdTabBar.swift). Replaces the old separate
 * `Home`/`Reports`/`Profile` top-level destinations — those are tab *content* switched inside
 * [com.riskdetectedan.app.navigation.MainShell] now, not distinct pushable routes (matching iOS:
 * tabs never show a back button, switching tabs isn't a back-stack operation). */
@Serializable object MainShell
@Serializable object Capture

/** photoPath null until Capture hands off a file — matches Analysis being reachable directly
 * from Home too (sector-first flow) as well as from Capture (photo-first flow). */
@Serializable data class Analysis(val photoPath: String? = null)
@Serializable object Companies
@Serializable object Support
@Serializable object NotificationSettings
@Serializable object DeleteAccount
@Serializable object Paywall
