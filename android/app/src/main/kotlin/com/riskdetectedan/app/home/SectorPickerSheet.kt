package com.riskdetectedan.app.home

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Agriculture
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Construction
import androidx.compose.material.icons.filled.Factory
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.Warehouse
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisSectorBadge
import com.riskdetectedan.core.data.analysis.AnalysisSectorPickerItem
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Real port of `beginPreAnalysisSelection()`'s Home-embedded sector sheet (the first step of the
 * real iOS pre-analysis flow — sector, then [CanvasSheet], matching `RDConfig.Features
 * .activeAnalysisSectorEnabled`'s real real gate, hardcoded on here the same way the Swift flag
 * is hardcoded `true`; there's no remote toggle for it on either platform). Closes the "sector
 * picker lives only inside AnalysisScreen after canvas confirm" ordering gap documented since
 * the Faz M-S plan closed — sector selection itself was never broken, only its position in the
 * flow was.
 *
 * Items come from [com.riskdetectedan.core.data.analysis.AnalysisSectorPreferences.pickerItems] —
 * real onboarding-sectors-first / last-used / catalog-order precedence, not a flat alphabetical
 * list.
 */
@Composable
fun SectorPickerSheet(
    items: List<AnalysisSectorPickerItem>,
    onSelect: (AnalysisSector) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = RdTheme.colors

    Column(modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.sm)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = RdSpacing.lg).padding(bottom = RdSpacing.md),
            verticalAlignment = Alignment.Top,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(stringResource(RdR.string.rd_sektor_sec), style = RdFontStyle.Title2.toTextStyle(), color = colors.black)
                Spacer(Modifier.height(4.dp))
                Text(
                    stringResource(RdR.string.rd_sektor_sec_aciklama),
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.slate,
                )
            }
            IconButton(
                onClick = onDismiss,
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(colors.white)
                    .border(1.dp, colors.line, CircleShape),
            ) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_kapat), tint = colors.black, modifier = Modifier.size(14.dp))
            }
        }

        LazyColumn(
            modifier = Modifier.fillMaxWidth().heightIn(max = 420.dp).padding(horizontal = RdSpacing.lg),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(items, key = { it.sector.id }) { item ->
                SectorRow(item = item, onClick = { onSelect(item.sector) })
            }
        }
        Spacer(Modifier.height(RdSpacing.md))
    }
}

@Composable
private fun SectorRow(item: AnalysisSectorPickerItem, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(RdSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)).background(colors.fog),
            contentAlignment = Alignment.Center,
        ) {
            Icon(sectorIcon(item.sector), contentDescription = null, tint = colors.black, modifier = Modifier.size(17.dp))
        }
        Spacer(Modifier.width(RdSpacing.sm))
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(item.sector.titleTr, style = RdFontStyle.Footnote.toTextStyle(), color = colors.onyx)
                item.badges.firstOrNull()?.let { badge ->
                    Spacer(Modifier.width(6.dp))
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(colors.greenSoft)
                            .padding(horizontal = 6.dp, vertical = 1.dp),
                    ) {
                        Text(
                            stringResource(
                                if (badge == AnalysisSectorBadge.LastUsed) RdR.string.rd_son else RdR.string.rd_onerilen,
                            ),
                            style = RdFontStyle.Caption.toTextStyle(),
                            color = colors.greenDark,
                        )
                    }
                }
            }
            Text(item.sector.subtitleTr, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate, maxLines = 1)
        }
    }
}

private fun sectorIcon(sector: AnalysisSector): ImageVector = when (sector) {
    AnalysisSector.General -> Icons.Filled.Shield
    AnalysisSector.Construction -> Icons.Filled.Construction
    AnalysisSector.Manufacturing -> Icons.Filled.Factory
    AnalysisSector.Mining -> Icons.Filled.Terrain
    AnalysisSector.Energy -> Icons.Filled.Bolt
    AnalysisSector.Office -> Icons.Filled.Business
    AnalysisSector.LogisticsWarehouse -> Icons.Filled.Warehouse
    AnalysisSector.ChemicalLaboratory -> Icons.Filled.Science
    AnalysisSector.Healthcare -> Icons.Filled.LocalHospital
    AnalysisSector.FoodProduction -> Icons.Filled.Restaurant
    AnalysisSector.AgricultureLivestock -> Icons.Filled.Agriculture
    AnalysisSector.Retail -> Icons.Filled.Storefront
    AnalysisSector.MunicipalFieldServices -> Icons.Filled.AccountBalance
    AnalysisSector.Education -> Icons.Filled.School
    AnalysisSector.Hospitality -> Icons.Filled.Hotel
}
