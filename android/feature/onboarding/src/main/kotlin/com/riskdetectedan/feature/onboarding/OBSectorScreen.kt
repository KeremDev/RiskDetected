package com.riskdetectedan.feature.onboarding

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
        title = "Hangi sektörde çalışıyorsun?",
        subtitle = "Birden fazla seçebilirsin",
        items = OnboardingSector.entries,
        isSelected = { selected.contains(it) },
        label = { it.label },
        onToggle = onToggle,
        canContinue = selected.isNotEmpty(),
        onContinue = onNext,
        multi = true,
        layout = RdPickerLayout.Grid,
        step = 3,
        onBack = onBack,
        heroTint = RdHeroTint.Cool,
        heroIcon = Icons.Filled.LocationCity,
        selectionCounterSuffix = "sektör seçildi",
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
private fun sectorSubtitle(sector: OnboardingSector): String = when (sector) {
    OnboardingSector.Construction -> "Şantiye, yapı, hafriyat"
    OnboardingSector.Manufacturing -> "Fabrika, atölye, üretim hattı"
    OnboardingSector.Energy -> "Santral, rafineri, enerji tesisleri"
    OnboardingSector.Mining -> "Yeraltı, açık ocak, taşocağı"
    OnboardingSector.Office -> "Banka, AVM, idari bina"
    OnboardingSector.LogisticsWarehouse -> "Depo, lojistik, yükleme alanları"
    OnboardingSector.ChemicalLaboratory -> "Kimyasal işlem, laboratuvar"
    OnboardingSector.Healthcare -> "Hastane, klinik, sağlık tesisi"
    OnboardingSector.FoodProduction -> "Gıda üretimi, mutfak, hijyen alanları"
    OnboardingSector.AgricultureLivestock -> "Tarım, hayvancılık, açık alan"
    OnboardingSector.Retail -> "Mağaza, perakende, müşteri alanı"
    OnboardingSector.MunicipalFieldServices -> "Belediye, kamu saha işleri"
    OnboardingSector.Education -> "Okul, üniversite, atölye"
    OnboardingSector.Hospitality -> "Otel, konaklama, misafir alanları"
    OnboardingSector.Other -> "Tanımlanmamış veya farklı sektörler"
}
