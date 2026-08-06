package com.riskdetectedan.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

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

    val materialColorScheme = if (darkTheme) {
        darkColorScheme(
            primary = rdColors.cta,
            background = rdColors.paper,
            surface = rdColors.white,
            onBackground = rdColors.ink,
            onSurface = rdColors.ink,
            error = rdColors.critical,
        )
    } else {
        lightColorScheme(
            primary = rdColors.cta,
            background = rdColors.paper,
            surface = rdColors.white,
            onBackground = rdColors.ink,
            onSurface = rdColors.ink,
            error = rdColors.critical,
        )
    }

    CompositionLocalProvider(LocalRdColors provides rdColors) {
        MaterialTheme(
            colorScheme = materialColorScheme,
            content = content,
        )
    }
}
