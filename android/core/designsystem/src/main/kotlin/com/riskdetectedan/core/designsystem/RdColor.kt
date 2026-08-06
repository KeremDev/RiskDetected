package com.riskdetectedan.core.designsystem

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * Ported 1:1 from the iOS token source: App/DesignSystem/RDColor.swift + Color+Hex.swift.
 * Keep these two files in sync by hand until `contracts/design/riskdetected-tokens.json`
 * (see repo root `contracts/`) becomes the single generated source for both platforms.
 */
private fun hex(value: String): Color {
    val cleaned = value.removePrefix("#")
    val argb = when (cleaned.length) {
        6 -> "FF$cleaned"
        8 -> cleaned.substring(6, 8) + cleaned.substring(0, 6)
        else -> "FF000000"
    }
    return Color(android.graphics.Color.parseColor("#$argb"))
}

data class RdColors(
    // Brand
    val black: Color,
    val graphite: Color,
    val onyx: Color = hex("#0B0D0E"),
    val green: Color = hex("#00B82E"),
    val greenDark: Color = hex("#008F24"),
    val greenSoft: Color,
    val planPlus: Color = hex("#F0A400"),
    val planPlusDark: Color = hex("#9A5B00"),
    val planPlusSoft: Color,
    val paper: Color,
    val white: Color,
    val selected: Color,
    val cta: Color,
    val compactCta: Color,

    // Secondary
    val ink: Color,
    val charcoal: Color,
    val slate: Color,
    val line: Color,
    val fog: Color,
    val cloud: Color,

    // Risk semantic
    val critical: Color = hex("#B42318"),
    val high: Color = hex("#C76A00"),
    val medium: Color = hex("#D4A106"),
    val low: Color = hex("#237A3B"),
    val info: Color = hex("#2F6FED"),
    val unknown: Color = hex("#94A3B8"),

    val criticalBg: Color = hex("#FDECEC"),
    val highBg: Color = hex("#FFF4DE"),
    val mediumBg: Color = hex("#FEF9C3"),
    val lowBg: Color = hex("#E8F5EF"),
    val unknownBg: Color = hex("#F1F4F2"),

    val criticalText: Color = hex("#9F2623"),
    val highText: Color = hex("#A45A00"),
    val mediumText: Color = hex("#854D0E"),
    val lowText: Color = hex("#1F6B4A"),
)

val LightRdColors = RdColors(
    black = hex("#0B0D0E"),
    graphite = hex("#1A1D1F"),
    greenSoft = hex("#EAF8EE"),
    planPlusSoft = hex("#FFF3D0"),
    paper = hex("#FAFBFA"),
    white = hex("#FFFFFF"),
    selected = hex("#0B0D0E"),
    cta = hex("#0B0D0E"),
    compactCta = hex("#F1F4F2"),
    ink = hex("#202427"),
    charcoal = hex("#343A40"),
    slate = hex("#6B7280"),
    line = hex("#DDE3E0"),
    fog = hex("#F1F4F2"),
    cloud = hex("#F6F7F6"),
)

val DarkRdColors = RdColors(
    black = hex("#F4F7F5"),
    graphite = hex("#E6ECE8"),
    greenSoft = hex("#092F15"),
    planPlusSoft = hex("#3A2605"),
    paper = hex("#0B0D0E"),
    white = hex("#151819"),
    selected = hex("#00B82E"),
    cta = hex("#00B82E"),
    compactCta = hex("#00B82E"),
    ink = hex("#F0F4F1"),
    charcoal = hex("#CAD3CE"),
    slate = hex("#9AA3AD"),
    line = hex("#2B3032"),
    fog = hex("#202526"),
    cloud = hex("#111415"),
)

val LocalRdColors = staticCompositionLocalOf { LightRdColors }

/** Usage: `RdTheme.colors.critical` inside a `@Composable` under [RdTheme]. */
object RdTheme {
    val colors: RdColors
        @Composable get() = LocalRdColors.current
}

enum class RiskLevel { Critical, High, Medium, Low, Unknown }

/** Maps the DB's `risk_level` enum ("critical"/"high"/"medium"/"low"/"unknown", lowercase) to
 * this token type — kept here (not in core:data) so core:data doesn't need to depend on
 * core:designsystem just for this lookup. */
fun riskLevelFromRaw(value: String?): RiskLevel = when (value) {
    "critical" -> RiskLevel.Critical
    "high" -> RiskLevel.High
    "medium" -> RiskLevel.Medium
    "low" -> RiskLevel.Low
    else -> RiskLevel.Unknown
}

@Composable
fun RiskLevel.color(): Color = when (this) {
    RiskLevel.Critical -> RdTheme.colors.critical
    RiskLevel.High -> RdTheme.colors.high
    RiskLevel.Medium -> RdTheme.colors.medium
    RiskLevel.Low -> RdTheme.colors.low
    RiskLevel.Unknown -> RdTheme.colors.unknown
}

@Composable
fun RiskLevel.backgroundColor(): Color = when (this) {
    RiskLevel.Critical -> RdTheme.colors.criticalBg
    RiskLevel.High -> RdTheme.colors.highBg
    RiskLevel.Medium -> RdTheme.colors.mediumBg
    RiskLevel.Low -> RdTheme.colors.lowBg
    RiskLevel.Unknown -> RdTheme.colors.unknownBg
}
