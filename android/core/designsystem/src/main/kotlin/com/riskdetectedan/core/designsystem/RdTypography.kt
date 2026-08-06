package com.riskdetectedan.core.designsystem

import androidx.compose.ui.text.TextStyle
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
    fontWeight = weight,
    fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default,
)
