package com.riskdetectedan.app.navigation

import kotlinx.serialization.Serializable

/**
 * Type-safe Navigation Compose routes (review Ç7: kotlinx.serialization routes, not Nav3 —
 * decided as not-yet-GA at plan time). One object per top-level destination; add data classes
 * with typed args here as real flows replace the Faz-1 placeholders.
 */
@Serializable object Splash
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

/** Real port of `AnnotateView.swift`'s per-photo markup step (`showAnnotate`) — reached right
 * after a camera capture ([CaptureForTray]) or gallery pick ([com.riskdetectedan.app.home
 * .HomeScreen]'s `onAnnotatePhotos`) lands a photo, before it's added to the shared
 * [com.riskdetectedan.app.home.PhotoTrayViewModel]. [queuedPaths] carries any remaining
 * not-yet-annotated photos from the same multi-select gallery pick — real port of iOS's
 * `queuedAnnotatePhotoIDs` sequential-annotation queue, encoded as nav args instead of a shared
 * ViewModel since there's no natural owner for that queue's lifetime otherwise. */
@Serializable data class Annotate(
    val photoPath: String,
    val queuedPaths: List<String> = emptyList(),
)

/** photoPaths empty until Capture/the photo tray hands off files — matches Analysis being
 * reachable directly from Home too (sector-first flow) as well as from Capture (photo-first
 * flow). Supports the real multi-photo flow (Faz O) — up to 3 photos, iOS's own hard cap
 * regardless of tier (`PlanCapabilities.safeMaxPhotosPerAnalysis`). */
/** [resume] = true reaches this route via [com.riskdetectedan.app.home.HomeScreen]'s real port of
 * `resumeInFlightAnalysisIfNeeded` — an in-flight analysis found for the current user (survived
 * an app-process death mid-submit/mid-poll) skips the sector picker and jumps straight into
 * polling for that existing analysis instead of configuring a new one. */
/** [sectorId] — real port of `beginPreAnalysisSelection()`'s Home-embedded sector sheet
 * (see [com.riskdetectedan.app.home.SectorPickerSheet]): the sector is now chosen *before*
 * reaching this screen, matching iOS's real sector-sheet-then-canvas-sheet order. Null falls
 * back to this screen's own in-screen picker (e.g. [resume] mode, or any future entry point that
 * hasn't gone through the Home sheet). */
@Serializable data class Analysis(
    val photoPaths: List<String> = emptyList(),
    val canvasIds: List<String> = listOf("general"),
    val analysisMode: String = "standard",
    val resume: Boolean = false,
    val sectorId: String? = null,
)
@Serializable object Companies
@Serializable object Support
@Serializable object NotificationSettings
@Serializable object AppearanceSettings
@Serializable object DataManagement
@Serializable data class AnalysisReports(val analysisId: String)
@Serializable data class AnalysisResult(val analysisId: String)
@Serializable object DeleteAccount
@Serializable object Paywall
@Serializable data class PaywallForTier(
    val tier: String,
    val resultAnalysisId: String? = null,
    val resultSection: String? = null,
    val resultFunnelSessionId: String? = null,
)
