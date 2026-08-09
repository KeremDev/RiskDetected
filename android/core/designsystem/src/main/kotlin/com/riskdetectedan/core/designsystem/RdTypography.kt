package com.riskdetectedan.core.designsystem

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Ported from App/DesignSystem/RDFont.swift + RDFontScale.swift (same size/weight table). */
enum class RdFontStyle(val baseSize: Float, val weight: FontWeight, val mono: Boolean = false) {
    LargeTitle(34f, FontWeight.Bold),
    Title1(28f, FontWeight.Bold),
    Title2(22f, FontWeight.Bold),
    Title3(20f, FontWeight.SemiBold),
    Body(17f, FontWeight.Normal),
    Callout(16f, FontWeight.Medium),
    Subheadline(15f, FontWeight.Normal),
    Footnote(13f, FontWeight.Medium),
    Caption(12f, FontWeight.Medium),
    Data(13f, FontWeight.Medium, mono = true),
    SectionHeader(13f, FontWeight.SemiBold),
}

/** Same downward-scale curve as RDFontScale.size(_:) on iOS — keeps type density visually aligned. */
fun rdFontScale(base: Float): Float = when {
    base >= 28f -> base - 3f
    base >= 22f -> base - 2f
    base >= 17f -> base - 1.5f
    base >= 13f -> base - 1f
    base >= 12f -> base - 0.5f
    else -> base
}

fun RdFontStyle.toTextStyle(): TextStyle = TextStyle(
    fontSize = rdFontScale(baseSize).sp,
    lineHeight = (rdFontScale(baseSize) * when (this) {
        RdFontStyle.LargeTitle, RdFontStyle.Title1, RdFontStyle.Title2, RdFontStyle.Title3 -> 1.12f
        RdFontStyle.Caption, RdFontStyle.Data, RdFontStyle.SectionHeader -> 1.16f
        else -> 1.22f
    }).sp,
    letterSpacing = when (this) {
        RdFontStyle.LargeTitle, RdFontStyle.Title1 -> (-0.35f).sp
        RdFontStyle.Title2, RdFontStyle.Title3 -> (-0.2f).sp
        RdFontStyle.SectionHeader -> 0.55f.sp
        else -> 0.sp
    },
    fontWeight = weight,
    // SF Pro / SF Pro Rounded cannot be redistributed in the Android bundle. Android's
    // platform sans family is the safe system counterpart; explicit metrics below remove
    // Roboto's extra vertical padding and match the live iOS optical sizes more closely.
    fontFamily = FontFamily.SansSerif,
    fontFeatureSettings = if (mono) "tnum" else null,
    platformStyle = PlatformTextStyle(includeFontPadding = false),
)
