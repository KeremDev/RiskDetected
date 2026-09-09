package com.riskdetectedan.feature.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Help
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.data.progress.ProfessionalProgressTitle
import com.riskdetectedan.core.designsystem.R as RdR
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.professionalProgressTitleLabel
import com.riskdetectedan.core.designsystem.toTextStyle

/** Android counterpart of iOS `ProfessionalProgressTitlesSheet` and its rank guide. */
@Composable
fun ProfessionalProgressTitlesSheet(summary: ProfessionalProgressSummary, onDismiss: () -> Unit) {
    val colors = RdTheme.colors
    var showRankGuide by rememberSaveable { mutableStateOf(false) }

    Column(Modifier.fillMaxWidth().fillMaxHeight().background(colors.white)) {
        ProfessionalProgressSheetHeader(
            title = stringResource(if (showRankGuide) RdR.string.rd_rutbe_puanlama else RdR.string.rd_mesleki_unvanlar),
            onClose = if (showRankGuide) ({ showRankGuide = false }) else onDismiss,
        )
        if (showRankGuide) {
            ProfessionalProgressRankGuide(summary)
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 28.dp),
            ) {
                item { ProfessionalProgressSheetCard(summary, Modifier.padding(start = 24.dp, end = 24.dp, top = 12.dp)) }
                item {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 10.dp)
                            .clip(RoundedCornerShape(14.dp)).background(colors.fog.copy(alpha = .72f))
                            .border(1.dp, colors.line, RoundedCornerShape(14.dp))
                            .clickable { showRankGuide = true }.padding(horizontal = 14.dp).height(42.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Help, null, tint = colors.planPlusDark, modifier = Modifier.size(19.dp))
                        Spacer(Modifier.width(9.dp))
                        Text(stringResource(RdR.string.rd_nasil_rutbe_alirim), style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.black)
                        Spacer(Modifier.weight(1f))
                        Icon(Icons.Filled.KeyboardArrowRight, null, tint = colors.slate, modifier = Modifier.size(20.dp))
                    }
                }
                item { ProfessionalTitleSection(stringResource(RdR.string.rd_temel_rutbeler), ProfessionalProgressTitle.entries.take(3), summary) }
                item { Box(Modifier.fillMaxWidth().height(6.dp).background(colors.fog)) }
                item { ProfessionalTitleSection(stringResource(RdR.string.rd_uzmanlik_rutbeleri), ProfessionalProgressTitle.entries.drop(3).take(3), summary) }
                item { Box(Modifier.fillMaxWidth().height(6.dp).background(colors.fog)) }
                item { ProfessionalTitleSection(stringResource(RdR.string.rd_ustalik), ProfessionalProgressTitle.entries.takeLast(1), summary) }
            }
        }
    }
}

@Composable
private fun ProfessionalProgressSheetHeader(title: String, onClose: () -> Unit) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().height(66.dp).border(.5.dp, colors.line).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onClose) { Icon(Icons.Filled.Close, stringResource(RdR.string.rd_kapat), tint = colors.black) }
        Text(title, Modifier.weight(1f), style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.black, textAlign = TextAlign.Center)
        Spacer(Modifier.size(48.dp))
    }
}

@Composable
private fun ProfessionalProgressSheetCard(summary: ProfessionalProgressSummary, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.white)
            .border(1.5.dp, colors.black, RoundedCornerShape(18.dp)).padding(15.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(summary.profile.totalMdp.toString(), style = RdFontStyle.Title1.toTextStyle().copy(fontSize = 25.sp), color = colors.black)
            Text(" / ${summary.nextTitle?.threshold ?: summary.currentTitle.threshold}", style = RdFontStyle.Subheadline.toTextStyle(), color = colors.slate)
        }
        Text(
            summary.nextTitle?.let { stringResource(RdR.string.rd_next_title_remaining_format, professionalProgressTitleLabel(it.key), summary.nextTitleRemaining) }
                ?: stringResource(RdR.string.rd_highest_title_status),
            style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.slate,
        )
        Box(Modifier.fillMaxWidth().height(14.dp).clip(CircleShape).background(colors.black.copy(alpha = .10f))) {
            Box(Modifier.fillMaxWidth(summary.titleProgress.toFloat()).height(14.dp).clip(CircleShape).background(colors.cta))
        }
    }
}

@Composable
private fun ProfessionalTitleSection(title: String, titles: List<ProfessionalProgressTitle>, summary: ProfessionalProgressSummary) {
    val colors = RdTheme.colors
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, style = RdFontStyle.Title3.toTextStyle().copy(fontSize = 16.sp, fontWeight = FontWeight.SemiBold), color = colors.black)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            titles.forEach { ProfessionalTitleTile(it, summary, Modifier.weight(1f)) }
            repeat((3 - titles.size).coerceAtLeast(0)) { Spacer(Modifier.weight(1f)) }
        }
    }
}

@Composable
private fun ProfessionalTitleTile(title: ProfessionalProgressTitle, summary: ProfessionalProgressSummary, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    val earned = summary.profile.totalMdp >= title.threshold
    val current = title == summary.currentTitle
    Column(modifier.padding(vertical = 2.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Box(Modifier.size(62.dp), contentAlignment = Alignment.Center) {
            Box(
                Modifier.size(if (current) 58.dp else 50.dp).clip(CircleShape)
                    .background(if (earned) colors.selected else colors.fog)
                    .border(if (current) 3.dp else 1.dp, if (current) colors.planPlus else colors.line, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.MilitaryTech, null, tint = if (earned) Color.White else colors.slate.copy(alpha = .45f), modifier = Modifier.size(22.dp))
            }
            if (current || !earned) Icon(
                if (current) Icons.Filled.CheckCircle else Icons.Filled.Lock, null,
                tint = if (current) colors.planPlus else colors.slate,
                modifier = Modifier.align(Alignment.TopEnd).size(if (current) 18.dp else 15.dp),
            )
        }
        Text(
            professionalProgressTitleLabel(title.key),
            style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.SemiBold, fontSize = 10.5.sp),
            color = if (earned) colors.black else colors.slate,
            textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
        Text(stringResource(RdR.string.rd_mdp_format, title.threshold), style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 9.sp), color = colors.slate)
    }
}

@Composable
private fun ProfessionalProgressRankGuide(summary: ProfessionalProgressSummary) {
    val colors = RdTheme.colors
    val hint = when {
        summary.weeklyTracking.reportsCount == 0 && summary.weeklyTracking.analysesCount > 0 -> stringResource(RdR.string.rd_progress_hint_analysis_to_report_format, summary.weeklyTracking.analysesCount)
        summary.weeklyTracking.reportsCount == 0 -> stringResource(RdR.string.rd_progress_hint_first_report)
        summary.profile.highFindings + summary.profile.criticalFindings == 0 -> stringResource(RdR.string.rd_progress_hint_high_risk)
        else -> stringResource(RdR.string.rd_progress_hint_new_work)
    }
    LazyColumn(
        Modifier.fillMaxWidth().background(colors.paper),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.white).border(1.dp, colors.line, RoundedCornerShape(18.dp)).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(colors.planPlus.copy(alpha = .16f)), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.LocalFireDepartment, null, tint = colors.planPlusDark, modifier = Modifier.size(24.dp))
                    }
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(professionalProgressTitleLabel(summary.currentTitle.key), style = RdFontStyle.Title3.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.black)
                        Text(
                            summary.nextTitle?.let { stringResource(RdR.string.rd_next_title_remaining_format, professionalProgressTitleLabel(it.key), summary.nextTitleRemaining) }
                                ?: stringResource(RdR.string.rd_highest_title_status),
                            style = RdFontStyle.Caption.toTextStyle(), color = colors.slate,
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    RankStat(summary.profile.totalMdp.toString(), stringResource(RdR.string.rd_toplam_mdp), Modifier.weight(1f))
                    RankStat(summary.nextTitleRemaining.toString(), stringResource(RdR.string.rd_kalan_mdp), Modifier.weight(1f))
                }
            }
        }
        item {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.greenSoft.copy(alpha = .64f))
                    .border(1.dp, colors.green.copy(alpha = .16f), RoundedCornerShape(18.dp)).padding(14.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Icon(Icons.Filled.KeyboardArrowRight, null, tint = colors.greenDark, modifier = Modifier.size(30.dp))
                Spacer(Modifier.width(10.dp))
                Column {
                    Text(stringResource(RdR.string.rd_sana_en_yakin_adim), style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.slate)
                    Text(hint, style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.black)
                }
            }
        }
        item {
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.white).border(1.dp, colors.line, RoundedCornerShape(18.dp)).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(stringResource(RdR.string.rd_mdp_nasil_kazanilir), style = RdFontStyle.Title3.toTextStyle().copy(fontSize = 17.sp, fontWeight = FontWeight.Bold), color = colors.black)
                ScoreRow(Icons.Filled.Description, RdR.string.rd_score_report_title, "+60 MDP", RdR.string.rd_score_report_detail)
                ScoreRow(Icons.Filled.TableChart, RdR.string.rd_score_risk_report_title, "+90 MDP", RdR.string.rd_score_risk_report_detail)
                ScoreRow(Icons.Filled.Shield, RdR.string.rd_score_high_risk_title, "+120 MDP", RdR.string.rd_score_high_risk_detail)
                ScoreRow(Icons.Filled.Search, RdR.string.rd_score_detailed_analysis_title, "+70 MDP", RdR.string.rd_score_detailed_analysis_detail)
                ScoreRow(Icons.Filled.GridView, RdR.string.rd_score_first_competency_title, "+20 MDP", RdR.string.rd_score_first_competency_detail)
                ScoreRow(Icons.Filled.CalendarMonth, RdR.string.rd_score_first_weekly_report_title, "+25 MDP", RdR.string.rd_score_first_weekly_report_detail)
            }
        }
        item {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.fog.copy(alpha = .72f)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.CheckCircle, null, tint = colors.slate, modifier = Modifier.size(17.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(RdR.string.rd_points_from_real_work), style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.black)
                }
                Text(stringResource(RdR.string.rd_points_guardrail), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }
        }
    }
}

@Composable
private fun RankStat(value: String, label: String, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    Column(modifier.clip(RoundedCornerShape(12.dp)).background(colors.fog.copy(alpha = .72f)).padding(horizontal = 12.dp, vertical = 10.dp)) {
        Text(value, style = RdFontStyle.Data.toTextStyle().copy(fontSize = 17.sp, fontWeight = FontWeight.Bold), color = colors.black)
        Text(label, style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 10.5.sp, fontWeight = FontWeight.SemiBold), color = colors.slate)
    }
}

@Composable
private fun ScoreRow(icon: ImageVector, titleRes: Int, points: String, detailRes: Int) {
    val colors = RdTheme.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(30.dp).clip(RoundedCornerShape(10.dp)).background(colors.fog), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = colors.black, modifier = Modifier.size(16.dp))
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(stringResource(titleRes), style = RdFontStyle.Callout.toTextStyle().copy(fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold), color = colors.black)
            Text(stringResource(detailRes), style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 11.5.sp), color = colors.slate)
        }
        Spacer(Modifier.width(8.dp))
        Text(
            points,
            style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 12.5.sp, fontWeight = FontWeight.Bold),
            color = colors.planPlusDark,
            modifier = Modifier.clip(CircleShape).background(colors.planPlus.copy(alpha = .14f)).padding(horizontal = 9.dp, vertical = 6.dp),
        )
    }
}
