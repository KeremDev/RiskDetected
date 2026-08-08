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

/** Reached via [Capture]'s quick-scan single-shot flow (adds its one photo to the list itself,
 * navigates here directly) — a second route, same [com.riskdetectedan.feature.capture.CaptureScreen]
 * composable, wired (Faz O) to add its photo to the shared [com.riskdetectedan.app.home.PhotoTrayViewModel]
 * and pop back to [MainShell]'s photo tray instead, matching iOS's real camera-returns-to-tray flow. */
@Serializable object CaptureForTray

/** photoPaths empty until Capture/the photo tray hands off files — matches Analysis being
 * reachable directly from Home too (sector-first flow) as well as from Capture (photo-first
 * flow). Supports the real multi-photo flow (Faz O) — up to 3 photos, iOS's own hard cap
 * regardless of tier (`PlanCapabilities.safeMaxPhotosPerAnalysis`). */
@Serializable data class Analysis(
    val photoPaths: List<String> = emptyList(),
    val canvasIds: List<String> = listOf("general"),
    val analysisMode: String = "standard",
)
@Serializable object Companies
@Serializable object Support
@Serializable object NotificationSettings
@Serializable object DeleteAccount
@Serializable object Paywall
