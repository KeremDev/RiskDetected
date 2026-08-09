package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Agriculture
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Construction
import androidx.compose.material.icons.filled.Factory
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.LocationCity
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.Warehouse
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import com.riskdetectedan.core.data.onboarding.OnboardingSector
import com.riskdetectedan.core.designsystem.RdHeroTint

/** Port of OBSectorView.swift — multi-select, the one screen iOS gives a bespoke 2-column grid
 * picker instead of the shared list-row card (see OnboardingChoiceList.kt's doc comment).
 * Per-item icon+subtitle mirror `AnalysisSector.icon`/`.subtitle` exactly (real SF Symbol names
 * mapped to their closest Material equivalent — see [sectorIcon]'s doc comment for the mapping
 * table) — `OBSector.icon`/`.sub` on iOS just delegate to that same model. */
@Composable
fun OBSectorScreen(
    selected: List<OnboardingSector>,
    onToggle: (OnboardingSector) -> Unit,
    onNext: () -> Unit,
    onBack: (() -> Unit)? = null,
) {
    OnboardingChoiceScreen(
        title = stringResource(RdR.string.rd_sektor_soru),
        subtitle = stringResource(RdR.string.rd_birden_fazla_secebilirsin),
        items = OnboardingSector.entries,
        isSelected = { selected.contains(it) },
        label = { onboardingSectorLabel(it) },
        onToggle = onToggle,
        canContinue = selected.isNotEmpty(),
        onContinue = onNext,
        multi = true,
        layout = RdPickerLayout.Grid,
        step = 3,
        onBack = onBack,
        heroTint = RdHeroTint.Cool,
        heroIcon = Icons.Filled.LocationCity,
        selectionCounterSuffix = stringResource(RdR.string.rd_sektor_secildi),
        itemIcon = { sectorIcon(it) },
        itemSubtitle = { sectorSubtitle(it) },
    )
}

/** Mirrors AnalysisSector.icon's SF Symbol choices (App/Models/AnalysisSector.swift), mapped to
 * the closest Material Icons Extended equivalent per item — not a literal port, Android has no
 * SF Symbol asset catalog. `hammer.fill`->Construction, `gearshape.2.fill`->Factory,
 * `bolt.fill`->Bolt, `mountain.2.fill`->Terrain, `building.2.fill`->Business,
 * `shippingbox.fill`->Warehouse, `flask.fill`->Science, `cross.case.fill`->LocalHospital,
 * `fork.knife`->Restaurant, `leaf.fill`->Agriculture, `bag.fill`->Storefront,
 * `signpost.right.fill`->AccountBalance, `graduationcap.fill`->School, `bed.double.fill`->Hotel,
 * `ellipsis` (OBSector's fallback for `.other`, which has no AnalysisSector mapping)->MoreHoriz. */
private fun sectorIcon(sector: OnboardingSector): ImageVector = when (sector) {
    OnboardingSector.Construction -> Icons.Filled.Construction
    OnboardingSector.Manufacturing -> Icons.Filled.Factory
    OnboardingSector.Energy -> Icons.Filled.Bolt
    OnboardingSector.Mining -> Icons.Filled.Terrain
    OnboardingSector.Office -> Icons.Filled.Business
    OnboardingSector.LogisticsWarehouse -> Icons.Filled.Warehouse
    OnboardingSector.ChemicalLaboratory -> Icons.Filled.Science
    OnboardingSector.Healthcare -> Icons.Filled.LocalHospital
    OnboardingSector.FoodProduction -> Icons.Filled.Restaurant
    OnboardingSector.AgricultureLivestock -> Icons.Filled.Agriculture
    OnboardingSector.Retail -> Icons.Filled.Storefront
    OnboardingSector.MunicipalFieldServices -> Icons.Filled.AccountBalance
    OnboardingSector.Education -> Icons.Filled.School
    OnboardingSector.Hospitality -> Icons.Filled.Hotel
    OnboardingSector.Other -> Icons.Filled.MoreHoriz
}

/** Mirrors AnalysisSector.subtitle's Turkish values verbatim. */
@Composable
private fun sectorSubtitle(sector: OnboardingSector): String = stringResource(
    when (sector) {
        OnboardingSector.Construction -> RdR.string.rd_sector_construction_subtitle
        OnboardingSector.Manufacturing -> RdR.string.rd_sector_manufacturing_subtitle
        OnboardingSector.Energy -> RdR.string.rd_sector_energy_subtitle
        OnboardingSector.Mining -> RdR.string.rd_sector_mining_subtitle
        OnboardingSector.Office -> RdR.string.rd_sector_office_subtitle
        OnboardingSector.LogisticsWarehouse -> RdR.string.rd_sector_logistics_subtitle
        OnboardingSector.ChemicalLaboratory -> RdR.string.rd_sector_chemical_subtitle
        OnboardingSector.Healthcare -> RdR.string.rd_sector_healthcare_subtitle
        OnboardingSector.FoodProduction -> RdR.string.rd_sector_food_subtitle
        OnboardingSector.AgricultureLivestock -> RdR.string.rd_sector_agriculture_subtitle
        OnboardingSector.Retail -> RdR.string.rd_sector_retail_subtitle
        OnboardingSector.MunicipalFieldServices -> RdR.string.rd_sector_municipal_subtitle
        OnboardingSector.Education -> RdR.string.rd_sector_education_subtitle
        OnboardingSector.Hospitality -> RdR.string.rd_sector_hospitality_subtitle
        OnboardingSector.Other -> RdR.string.rd_sector_other_subtitle
    },
)

@Composable
internal fun onboardingSectorLabel(sector: OnboardingSector): String = stringResource(
    when (sector) {
        OnboardingSector.Construction -> RdR.string.rd_sector_construction
        OnboardingSector.Manufacturing -> RdR.string.rd_sector_manufacturing
        OnboardingSector.Energy -> RdR.string.rd_sector_energy
        OnboardingSector.Mining -> RdR.string.rd_sector_mining
        OnboardingSector.Office -> RdR.string.rd_sector_office
        OnboardingSector.LogisticsWarehouse -> RdR.string.rd_sector_logistics
        OnboardingSector.ChemicalLaboratory -> RdR.string.rd_sector_chemical
        OnboardingSector.Healthcare -> RdR.string.rd_sector_healthcare
        OnboardingSector.FoodProduction -> RdR.string.rd_sector_food
        OnboardingSector.AgricultureLivestock -> RdR.string.rd_sector_agriculture
        OnboardingSector.Retail -> RdR.string.rd_sector_retail
        OnboardingSector.MunicipalFieldServices -> RdR.string.rd_sector_municipal
        OnboardingSector.Education -> RdR.string.rd_sector_education
        OnboardingSector.Hospitality -> RdR.string.rd_sector_hospitality
        OnboardingSector.Other -> RdR.string.rd_sector_other
    },
)
