package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.progress.ProfessionalProgressCompetency
import com.riskdetectedan.core.data.progress.ProfessionalProgressCompetencyStat
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.core.designsystem.professionalProgressCompetencyLabel

/**
 * Real port of `ProfessionalProgressCompetencyMapView.swift` — donut chart + legend chips
 * (`compact = true`, Profile's inline preview card) or a full scored-row list with risk-level
 * chips (`compact = false`, the "Tümü" full-screen sheet). All 11 [ProfessionalProgressCompetency]
 * entries are always represented (zero-signal ones synthesized inline, matching `displayRows`'s
 * `statsByKey` fallback) — never a partial catalog.
 */
@Composable
fun ProfessionalProgressCompetencyMapView(
    competencies: List<ProfessionalProgressCompetencyStat>,
    compact: Boolean = false,
) {
    val colors = RdTheme.colors
    val statsByKey = remember(competencies) { competencies.associateBy { it.competencyKey } }
    val allRows = ProfessionalProgressCompetency.entries.map { competency ->
        statsByKey[competency.key] ?: ProfessionalProgressCompetencyStat(
            userId = "",
            competencyKey = competency.key,
        )
    }
    val rows = if (compact) {
        allRows
            .filter { it.signalCount > 0 || it.onboardingSeed }
            .sortedWith(
                compareByDescending<ProfessionalProgressCompetencyStat> { it.signalCount }
                    .thenByDescending { it.score },
            )
            .take(4)
    } else {
        allRows
    }

    Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
        if (!compact) {
            Text(stringResource(RdR.string.rd_yetkinlik_haritasi), style = RdFontStyle.Title2.toTextStyle(), color = colors.black)
        }
        if (compact) {
            CompactCompetencyChart(rows)
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                rows.forEach { stat -> CompetencyRow(stat) }
            }
        }
    }
}

private fun chartWeight(stat: ProfessionalProgressCompetencyStat): Int =
    maxOf(stat.signalCount, if (stat.onboardingSeed) 1 else 0)

@Composable
private fun CompactCompetencyChart(rows: List<ProfessionalProgressCompetencyStat>) {
    val colors = RdTheme.colors
    val total = maxOf(rows.sumOf(::chartWeight), 1)

    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(modifier = Modifier.size(118.dp), contentAlignment = Alignment.Center) {
            Canvas(modifier = Modifier.size(118.dp)) {
                val strokeWidthPx = 16.dp.toPx()
                drawArc(
                    color = colors.fog,
                    startAngle = 0f,
                    sweepAngle = 360f,
                    useCenter = false,
                    style = Stroke(width = strokeWidthPx),
                )
                var startAngle = -90f
                rows.forEach { stat ->
                    val sweep = 360f * chartWeight(stat) / total.toFloat()
                    if (sweep > 0f) {
                        val gap = if (rows.size > 1) 1.2f else 0f
                        drawArc(
                            color = competencyAccent(stat.competency ?: ProfessionalProgressCompetency.Fire, colors),
                            startAngle = startAngle + gap,
                            sweepAngle = (sweep - gap * 2f).coerceAtLeast(0.6f),
                            useCenter = false,
                            style = Stroke(width = strokeWidthPx, cap = StrokeCap.Round),
                        )
                    }
                    startAngle += sweep
                }
            }
            Box(
                modifier = Modifier
                    .size(66.dp)
                    .clip(CircleShape)
                    .background(colors.white)
                    .border(1.dp, colors.line.copy(alpha = 0.72f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(stringResource(RdR.string.rd_sayi_format, rows.size), style = RdFontStyle.Title3.toTextStyle(), color = colors.black)
                    Text(stringResource(RdR.string.rd_alan), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                }
            }
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Text(stringResource(RdR.string.rd_yetkinlik_dagilimi), style = RdFontStyle.Footnote.toTextStyle(), color = colors.black)
            val chunks = rows.chunked(2)
            chunks.forEach { chunk ->
                Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    chunk.forEach { stat -> CompetencyLegendChip(stat, total, Modifier.weight(1f)) }
                    if (chunk.size < 2) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun CompetencyLegendChip(stat: ProfessionalProgressCompetencyStat, total: Int, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    val competency = stat.competency ?: ProfessionalProgressCompetency.Fire
    val accent = competencyAccent(competency, colors)
    val percent = Math.round(chartWeight(stat) * 100f / total)

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(accent.copy(alpha = 0.10f))
            .padding(horizontal = 7.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = Modifier.size(7.dp).clip(CircleShape).background(accent))
        Spacer(Modifier.width(5.dp))
        Text(
            professionalProgressCompetencyLabel(competency.key),
            style = RdFontStyle.Caption.toTextStyle(),
            color = colors.black,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        Text(stringResource(RdR.string.rd_yuzde_deger_format, percent), style = RdFontStyle.Caption.toTextStyle(), color = colors.black)
    }
}

@Composable
private fun CompetencyRow(stat: ProfessionalProgressCompetencyStat) {
    val colors = RdTheme.colors
    val competency = stat.competency ?: ProfessionalProgressCompetency.Fire
    val accent = competencyAccent(competency, colors)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(RdRadius.md))
            .clip(RoundedCornerShape(RdRadius.md))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(32.dp).clip(RoundedCornerShape(RdRadius.sm)).background(accent.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(competencyIcon(competency), contentDescription = null, tint = accent, modifier = Modifier.size(14.dp))
            }
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        professionalProgressCompetencyLabel(competency.key),
                        style = RdFontStyle.Callout.toTextStyle(),
                        color = colors.black,
                    )
                    if (stat.onboardingSeed && stat.signalCount == 0) {
                        Spacer(Modifier.width(6.dp))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .background(colors.greenSoft)
                                .padding(horizontal = 6.dp, vertical = 3.dp),
                        ) {
                            Text(stringResource(RdR.string.rd_beyan_edilen_alan), style = RdFontStyle.Caption.toTextStyle(), color = colors.greenDark)
                        }
                    }
                }
                Text(
                    stringResource(RdR.string.rd_bulgu_rapor_format, stat.findingCount, stat.reportCount),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                )
            }
            Spacer(Modifier.width(8.dp))
            Text(stringResource(RdR.string.rd_sayi_format, stat.score), style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
        }

        Box(modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)).background(colors.fog)) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(stat.score / 100f)
                    .height(6.dp)
                    .clip(RoundedCornerShape(50))
                    .background(accent),
            )
        }

        if (stat.findingCount > 0) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                RiskChip(stringResource(RdR.string.rd_risk_kritik), stat.criticalCount, colors.critical)
                RiskChip(stringResource(RdR.string.rd_risk_yuksek), stat.highCount, colors.high)
                RiskChip(stringResource(RdR.string.rd_risk_orta), stat.mediumCount, colors.medium)
                RiskChip(stringResource(RdR.string.rd_risk_dusuk), stat.lowCount, colors.low)
            }
        }
    }
}

@Composable
private fun RiskChip(label: String, count: Int, color: Color) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = 0.11f))
            .padding(horizontal = 7.dp, vertical = 4.dp),
    ) {
        Text(stringResource(RdR.string.rd_etiket_sayi_format, label, count), style = RdFontStyle.Caption.toTextStyle(), color = color)
    }
}
