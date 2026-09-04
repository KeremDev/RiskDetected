package com.riskdetectedan.app.home

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Agriculture
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Business
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisSectorBadge
import com.riskdetectedan.core.data.analysis.AnalysisSectorPickerItem
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.core.designsystem.rdAnalysisSectorTitle

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
) {
    val colors = RdTheme.colors
    var selected by remember(items) { mutableStateOf<AnalysisSector?>(null) }

    Column(modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.sm)) {
        Column(modifier = Modifier.fillMaxWidth().padding(horizontal = RdSpacing.lg).padding(bottom = 14.dp)) {
            Text(stringResource(RdR.string.rd_analiz_kapsamini_sec), style = RdFontStyle.Title2.toTextStyle(), color = colors.black)
            Spacer(Modifier.height(6.dp))
            Text(
                stringResource(RdR.string.rd_analiz_sektor_aciklama),
                style = RdFontStyle.Footnote.toTextStyle(),
                color = colors.slate,
            )
        }

        val columnCount = when {
            LocalConfiguration.current.screenWidthDp >= 600 -> 4
            else -> 3
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(columnCount),
            modifier = Modifier.fillMaxWidth().heightIn(max = 420.dp).padding(horizontal = RdSpacing.lg).selectableGroup(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(items, key = { it.sector.id }) { item ->
                SectorCard(item = item, selected = selected == item.sector, onClick = { selected = item.sector })
            }
        }
        Spacer(Modifier.height(RdSpacing.sm))
        RdPrimaryButton(
            text = stringResource(RdR.string.rd_devam_et),
            onClick = { selected?.let(onSelect) },
            enabled = selected != null,
            modifier = Modifier.padding(horizontal = RdSpacing.lg),
        )
        Spacer(Modifier.height(14.dp))
    }
}

@Composable
private fun SectorCard(item: AnalysisSectorPickerItem, selected: Boolean, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 74.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(if (selected) colors.selected else colors.white)
            .border(1.dp, if (selected) colors.selected else colors.line, RoundedCornerShape(14.dp))
            .selectable(selected = selected, onClick = onClick, role = Role.RadioButton)
            .padding(horizontal = 8.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                sectorIcon(item.sector),
                contentDescription = null,
                tint = if (selected) androidx.compose.ui.graphics.Color.White else sectorColor(item.sector),
                modifier = Modifier.size(14.dp),
            )
            item.badges.firstOrNull()?.let { badge ->
                Spacer(Modifier.width(6.dp))
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(if (selected) colors.white.copy(alpha = 0.86f) else colors.fog)
                        .padding(horizontal = 5.dp, vertical = 2.dp),
                ) {
                    Text(
                        stringResource(
                            if (badge == AnalysisSectorBadge.LastUsed) RdR.string.rd_son else RdR.string.rd_onerilen,
                        ),
                        style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 8.sp, lineHeight = 9.sp),
                        color = if (selected) colors.black else colors.slate,
                        maxLines = 1,
                    )
                }
            }
        }
        Text(
            rdAnalysisSectorTitle(item.sector.id, item.sector.titleTr),
            style = RdFontStyle.Footnote.toTextStyle(),
            color = if (selected) androidx.compose.ui.graphics.Color.White else colors.black,
            maxLines = 2,
        )
    }
}

@Composable
private fun sectorColor(sector: AnalysisSector) = when (sector) {
    AnalysisSector.Construction -> RdTheme.colors.high
    AnalysisSector.Manufacturing -> RdTheme.colors.info
    AnalysisSector.Mining -> RdTheme.colors.slate
    AnalysisSector.Energy -> RdTheme.colors.medium
    AnalysisSector.Healthcare -> RdTheme.colors.critical
    AnalysisSector.AgricultureLivestock -> RdTheme.colors.low
    AnalysisSector.General -> RdTheme.colors.charcoal
    else -> RdTheme.colors.greenDark
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
