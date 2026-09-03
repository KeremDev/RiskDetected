package com.riskdetectedan.core.designsystem

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.core.view.WindowCompat

internal val LocalRdDarkTheme = staticCompositionLocalOf { false }

/**
 * Material3's default typography uses Roboto.  That was easy to miss because most RD surfaces
 * provide an explicit [RdFontStyle], while stock buttons, dialogs, text fields and less prominent
 * labels inherit Material's typography.  Keep those components on the same Mulish contract as
 * iOS by mapping each Material role to the closest RD role.
 */
private val RdMaterialTypography = Typography(
    displayLarge = RdFontStyle.LargeTitle.toTextStyle(),
    displayMedium = RdFontStyle.Title1.toTextStyle(),
    displaySmall = RdFontStyle.Title2.toTextStyle(),
    headlineLarge = RdFontStyle.Title1.toTextStyle(),
    headlineMedium = RdFontStyle.Title2.toTextStyle(),
    headlineSmall = RdFontStyle.Title3.toTextStyle(),
    titleLarge = RdFontStyle.Title2.toTextStyle(),
    titleMedium = RdFontStyle.Title3.toTextStyle(),
    titleSmall = RdFontStyle.Subheadline.toTextStyle(),
    bodyLarge = RdFontStyle.Body.toTextStyle(),
    bodyMedium = RdFontStyle.Callout.toTextStyle(),
    bodySmall = RdFontStyle.Footnote.toTextStyle(),
    labelLarge = RdFontStyle.Callout.toTextStyle(),
    labelMedium = RdFontStyle.Footnote.toTextStyle(),
    labelSmall = RdFontStyle.Caption.toTextStyle(),
)

/**
 * Root theme wrapper — every screen in every `feature:*` module renders under this.
 * Provides both the RD semantic token set ([LocalRdColors] / [RdTheme.colors]) and a
 * matching Material3 [MaterialTheme] so stock M3 components (buttons, sheets, etc.) don't
 * clash with the brand palette.
 */
@Composable
fun RiskDetectedTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val rdColors = if (darkTheme) DarkRdColors else LightRdColors
    val parentDarkTheme = LocalRdDarkTheme.current

    SystemBarAppearanceEffect(darkTheme = darkTheme, restoreDarkTheme = parentDarkTheme)

    val materialColorScheme = if (darkTheme) {
        darkColorScheme(
            primary = rdColors.cta,
            onPrimary = Color.White,
            primaryContainer = rdColors.greenSoft,
            onPrimaryContainer = rdColors.black,
            secondary = rdColors.graphite,
            onSecondary = rdColors.paper,
            secondaryContainer = rdColors.fog,
            onSecondaryContainer = rdColors.black,
            tertiary = rdColors.planPlus,
            onTertiary = Color.White,
            background = rdColors.paper,
            surface = rdColors.white,
            surfaceVariant = rdColors.fog,
            onBackground = rdColors.ink,
            onSurface = rdColors.ink,
            onSurfaceVariant = rdColors.charcoal,
            outline = rdColors.line,
            error = rdColors.critical,
            onError = Color.White,
        )
    } else {
        lightColorScheme(
            primary = rdColors.cta,
            onPrimary = Color.White,
            primaryContainer = rdColors.greenSoft,
            onPrimaryContainer = rdColors.black,
            secondary = rdColors.graphite,
            onSecondary = rdColors.paper,
            secondaryContainer = rdColors.fog,
            onSecondaryContainer = rdColors.black,
            tertiary = rdColors.planPlus,
            onTertiary = Color.White,
            background = rdColors.paper,
            surface = rdColors.white,
            surfaceVariant = rdColors.fog,
            onBackground = rdColors.ink,
            onSurface = rdColors.ink,
            onSurfaceVariant = rdColors.charcoal,
            outline = rdColors.line,
            error = rdColors.critical,
            onError = Color.White,
        )
    }

    CompositionLocalProvider(
        LocalRdColors provides rdColors,
        LocalRdDarkTheme provides darkTheme,
    ) {
        MaterialTheme(
            colorScheme = materialColorScheme,
            typography = RdMaterialTypography,
            content = content,
        )
    }
}

/** Live iOS explicitly pins onboarding, authentication and in-app paywall surfaces to light
 * appearance. Use this nested provider for those product surfaces so a dark system/app setting
 * cannot leak through while the rest of the application remains appearance-aware. */
@Composable
fun RiskDetectedLightOnlyTheme(content: @Composable () -> Unit) {
    RiskDetectedTheme(darkTheme = false, content = content)
}

/**
 * Keeps status/navigation-bar icons readable when the in-app preference differs from the phone
 * setting. A nested light-only product surface (onboarding/auth/paywall) restores its parent
 * appearance when it leaves composition, matching SwiftUI's nested preferredColorScheme calls.
 */
@Composable
private fun SystemBarAppearanceEffect(darkTheme: Boolean, restoreDarkTheme: Boolean) {
    val view = LocalView.current
    if (view.isInEditMode) return

    DisposableEffect(view, darkTheme, restoreDarkTheme) {
        val activity = view.context.findActivity()
        fun apply(isDark: Boolean) {
            activity?.window?.let { window ->
                val systemBarColor = if (isDark) DarkRdColors.paper else LightRdColors.paper
                // A light-only nested surface (auth/onboarding/paywall) can be presented from
                // the dark app shell. Updating only icon appearance left black status-bar icons
                // on the shell's near-black background. Keep the bar surface and icon contrast
                // in the same theme transaction, then restore both on dispose.
                @Suppress("DEPRECATION")
                run {
                    window.statusBarColor = systemBarColor.toArgb()
                    window.navigationBarColor = systemBarColor.toArgb()
                }
                WindowCompat.getInsetsController(window, view).apply {
                    isAppearanceLightStatusBars = !isDark
                    isAppearanceLightNavigationBars = !isDark
                }
            }
        }

        apply(darkTheme)
        onDispose { apply(restoreDarkTheme) }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
