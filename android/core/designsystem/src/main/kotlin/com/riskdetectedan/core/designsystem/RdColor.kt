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

    // Adaptive result surfaces — App/DesignSystem/RDColor.swift build-88 source of truth.
    val resultBackground: Color,
    val resultSurface: Color,
    val resultElevatedSurface: Color,
    val resultPrimaryText: Color,
    val resultSecondaryText: Color,
    val resultTertiaryText: Color,
    val resultLine: Color,
    val resultSubtleSurface: Color,
    val resultGreenTint: Color,
    val resultGreenTintStrong: Color,
    val resultAmberTint: Color,
    val resultMintTint: Color,
    val resultBlueTint: Color,
    val resultKhakiTint: Color,
    val resultSelectedSurface: Color,
    val resultGreen: Color,
    val resultGreenDark: Color,
    val resultGreenMuted: Color,

    // Result-section identities.
    val sectionRiskStart: Color = hex("#94606D"),
    val sectionRiskEnd: Color = hex("#74404F"),
    val sectionRiskAccent: Color = hex("#A9717D"),
    val sectionRiskIcon: Color = hex("#F6DCE2"),
    val sectionExpertStart: Color = hex("#9C6517"),
    val sectionExpertEnd: Color = hex("#654006"),
    val sectionExpertAccent: Color,
    val sectionExpertStrong: Color,
    val sectionExpertIcon: Color = hex("#FBE4B0"),
    val sectionExpertTint: Color,
    val sectionTrainingStart: Color = hex("#73549A"),
    val sectionTrainingEnd: Color = hex("#493165"),
    val sectionTrainingAccent: Color,
    val sectionTrainingStrong: Color,
    val sectionTrainingIcon: Color = hex("#EEE3FA"),
    val sectionTrainingTint: Color,
    val sectionNotebookStart: Color = hex("#8A4051"),
    val sectionNotebookEnd: Color = hex("#572432"),
    val sectionNotebookAccent: Color,
    val sectionNotebookStrong: Color,
    val sectionNotebookIcon: Color = hex("#F5DFE4"),
    val sectionNotebookTint: Color,

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
    resultBackground = hex("#FFFFFF"),
    resultSurface = hex("#FFFFFF"),
    resultElevatedSurface = hex("#FFFFFF"),
    resultPrimaryText = hex("#1A1A1A"),
    resultSecondaryText = hex("#6D6D6D"),
    resultTertiaryText = hex("#9A9A9A"),
    resultLine = hex("#E6E6E6"),
    resultSubtleSurface = hex("#F4F4F4"),
    resultGreenTint = hex("#EDF8F0"),
    resultGreenTintStrong = hex("#F1FAEA"),
    resultAmberTint = hex("#FFF8E8"),
    resultMintTint = hex("#EFF8F4"),
    resultBlueTint = hex("#EFF6FB"),
    resultKhakiTint = hex("#F1EFE7"),
    resultSelectedSurface = hex("#F4FAEC"),
    resultGreen = hex("#35774A"),
    resultGreenDark = hex("#2E6B41"),
    resultGreenMuted = hex("#5D9670"),
    sectionExpertAccent = hex("#B7791F"),
    sectionExpertStrong = hex("#754A0B"),
    sectionExpertTint = hex("#FFF6E2"),
    sectionTrainingAccent = hex("#7653A6"),
    sectionTrainingStrong = hex("#58387E"),
    sectionTrainingTint = hex("#F5EFFB"),
    sectionNotebookAccent = hex("#985164"),
    sectionNotebookStrong = hex("#6B2C3C"),
    sectionNotebookTint = hex("#F9EEF1"),
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
    resultBackground = hex("#090C0B"),
    resultSurface = hex("#151A18"),
    resultElevatedSurface = hex("#1B211E"),
    resultPrimaryText = hex("#F3F7F4"),
    resultSecondaryText = hex("#B2BBB6"),
    resultTertiaryText = hex("#87918B"),
    resultLine = hex("#303735"),
    resultSubtleSurface = hex("#202623"),
    resultGreenTint = hex("#102A19"),
    resultGreenTintStrong = hex("#142D18"),
    resultAmberTint = hex("#30240D"),
    resultMintTint = hex("#102820"),
    resultBlueTint = hex("#102632"),
    resultKhakiTint = hex("#2B291F"),
    resultSelectedSurface = hex("#152B19"),
    resultGreen = hex("#63C680"),
    resultGreenDark = hex("#7AD496"),
    resultGreenMuted = hex("#9AC7A8"),
    sectionExpertAccent = hex("#D9A441"),
    sectionExpertStrong = hex("#F0BE5A"),
    sectionExpertTint = hex("#31230D"),
    sectionTrainingAccent = hex("#A98BD0"),
    sectionTrainingStrong = hex("#C5A8E8"),
    sectionTrainingTint = hex("#281D33"),
    sectionNotebookAccent = hex("#C98294"),
    sectionNotebookStrong = hex("#E0A1B0"),
    sectionNotebookTint = hex("#321820"),
)

val LocalRdColors = staticCompositionLocalOf { LightRdColors }

/** Usage: `RdTheme.colors.critical` inside a `@Composable` under [RdTheme]. */
object RdTheme {
    val colors: RdColors
        @Composable get() = LocalRdColors.current

    /** The resolved app appearance, including an explicit in-app override. */
    val isDark: Boolean
        @Composable get() = LocalRdDarkTheme.current
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
