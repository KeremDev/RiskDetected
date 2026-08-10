package com.riskdetectedan.feature.paywall

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.billing.BillingPackage
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

private val PaywallGoldBase = Color(0xFFD4A106)
private val PaywallGoldDeep = Color(0xFFA37C04)
private val PaywallGoldSoft = Color(0xFFFEF6CE)
private val PaywallGoldEdge = Color(0xFFF4E3A8)

/**
 * Android rendering of live iOS `InAppPaywallView`: Plus/Pro selection, independent monthly /
 * yearly billing, store-backed prices, restore, legal links and a fixed CTA tray. Google Play's
 * own purchase sheet remains platform-native; the product hierarchy and all in-app states match
 * the iOS contract.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(
    onBack: (() -> Unit)? = null,
    initialPlan: PaywallPlan? = null,
    viewModel: PaywallViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val selectedPlan by viewModel.selectedPlan.collectAsState()
    val selectedBilling by viewModel.selectedBilling.collectAsState()
    val isPurchasing by viewModel.isPurchasing.collectAsState()
    val purchaseError by viewModel.purchaseError.collectAsState()
    val context = LocalContext.current
    val activity = context.findActivity()
    val uriHandler = LocalUriHandler.current
    var legalDocumentKind by remember { mutableStateOf<String?>(null) }
    var didApplyInitialPlan by remember(initialPlan) { mutableStateOf(false) }

    LaunchedEffect(state, initialPlan) {
        if (!didApplyInitialPlan && initialPlan != null && state is PaywallUiState.Loaded) {
            viewModel.selectPlan(initialPlan)
            didApplyInitialPlan = true
        }
    }

    val loaded = state as? PaywallUiState.Loaded
    val selectedPackage = loaded?.let { viewModel.selectedPackage() }
    val currentPlanIncludesSelection = loaded?.currentTier?.includes(selectedPlan.tier) == true

    Box(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        when (val current = state) {
            PaywallUiState.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
            }
            PaywallUiState.SignedOut -> RdEmptyState(
                icon = Icons.Filled.WorkspacePremium,
                title = stringResource(RdR.string.rd_oturum_yok),
                subtitle = stringResource(RdR.string.rd_plan_yukseltmek_icin_giris),
            )
            is PaywallUiState.Failed -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                RdEmptyState(
                    icon = Icons.Filled.WorkspacePremium,
                    title = stringResource(RdR.string.rd_paketler_yuklenemedi),
                    subtitle = current.error.message,
                )
                TextButton(onClick = viewModel::load) { Text(stringResource(RdR.string.rd_tekrar_dene)) }
            }
            is PaywallUiState.Loaded -> Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = 154.dp),
            ) {
                PaywallHero()
                Column(modifier = Modifier.padding(horizontal = 20.dp)) {
                    Spacer(Modifier.height(26.dp))
                    PlanSelector(selectedPlan, viewModel::selectPlan)
                    Spacer(Modifier.height(12.dp))
                    ProductHeading(selectedPlan, selectedBilling, selectedPackage)
                    Spacer(Modifier.height(14.dp))
                    BillingSelector(selectedPlan, selectedBilling, viewModel::selectBilling)
                    Spacer(Modifier.height(14.dp))
                    FeatureCard(selectedPlan)
                    Spacer(Modifier.height(12.dp))
                    ComparisonCard(onSelect = viewModel::selectPlan)
                    Spacer(Modifier.height(RdSpacing.lg))
                }
            }
        }

        Row(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(
                onClick = {
                    viewModel.recordClose()
                    onBack?.invoke()
                },
                enabled = !isPurchasing,
                modifier = Modifier.size(36.dp).clip(CircleShape).background(colors.white.copy(alpha = 0.95f)),
            ) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_kapat), tint = colors.onyx, modifier = Modifier.size(18.dp))
            }
            TextButton(onClick = viewModel::restorePurchases, enabled = !isPurchasing) {
                Text(
                    stringResource(if (isPurchasing) RdR.string.rd_bekle else RdR.string.rd_geri_yukle),
                    color = colors.onyx,
                    fontWeight = FontWeight.Bold,
                )
            }
        }

        if (state is PaywallUiState.Loaded) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .background(colors.paper)
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                RdPrimaryButton(
                    text = when {
                        isPurchasing -> stringResource(RdR.string.rd_satin_alma_hazirlaniyor)
                        currentPlanIncludesSelection -> stringResource(RdR.string.rd_planin_aktif)
                        selectedPackage == null -> stringResource(RdR.string.rd_fiyat_alinamadi_tekrar_dene)
                        selectedPlan == PaywallPlan.Plus && selectedBilling == PaywallBilling.Yearly -> stringResource(RdR.string.rd_devam_et)
                        else -> stringResource(RdR.string.rd_aboneligi_baslat)
                    },
                    onClick = {
                        viewModel.recordCtaTap()
                        if (selectedPackage == null) viewModel.load()
                        else activity?.let { viewModel.purchase(it, selectedPackage) }
                    },
                    enabled = !isPurchasing && !currentPlanIncludesSelection && activity != null,
                    loading = isPurchasing,
                    loadingLabel = stringResource(RdR.string.rd_satin_alma_dogrulaniyor),
                    style = RdButtonStyle.Green,
                    showArrow = false,
                )
                Text(
                    selectedPackage?.let { packageLegalLine(selectedBilling, it) }
                        ?: stringResource(RdR.string.rd_google_play_fiyat_teklif_dogrulama),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 6.dp),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text(stringResource(RdR.string.rd_sartlar), style = RdFontStyle.Caption.toTextStyle(), modifier = Modifier.clickable { legalDocumentKind = "terms" })
                    Text(stringResource(RdR.string.rd_gizlilik), style = RdFontStyle.Caption.toTextStyle(), modifier = Modifier.clickable { legalDocumentKind = "privacy" })
                    Text(
                        stringResource(RdR.string.rd_abonelikleri_yonet),
                        style = RdFontStyle.Caption.toTextStyle(),
                        modifier = Modifier.clickable {
                            uriHandler.openUri("https://play.google.com/store/account/subscriptions")
                        },
                    )
                }
            }
        }
    }

    purchaseError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearPurchaseError,
            title = { Text(error.title) },
            text = {
                Column {
                    Text(error.message)
                    if (error.action.isNotEmpty()) Text(error.action)
                    Text(error.supportID)
                }
            },
            confirmButton = { TextButton(onClick = viewModel::clearPurchaseError) { Text(stringResource(RdR.string.rd_tamam)) } },
        )
    }

    if (legalDocumentKind != null) {
        var documents by remember { mutableStateOf<List<RdLegalDocument>>(emptyList()) }
        LaunchedEffect(Unit) {
            documents = LegalDocumentAssets.load(context)
                .map { RdLegalDocument(kind = it.kind, title = it.title, text = it.text) }
        }
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { legalDocumentKind = null }, sheetState = sheetState) {
            RdLegalDocumentSheet(
                documents = documents,
                initialKind = legalDocumentKind,
                onClose = { legalDocumentKind = null },
            )
        }
    }
}

@Composable
private fun PaywallHero() {
    val colors = RdTheme.colors
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(88.dp)
            .background(Brush.linearGradient(listOf(colors.greenDark, colors.green))),
    ) {
        Icon(
            Icons.Filled.WorkspacePremium,
            contentDescription = null,
            tint = colors.white.copy(alpha = 0.22f),
            modifier = Modifier.align(Alignment.BottomEnd).padding(end = 24.dp).size(68.dp),
        )
    }
}

@Composable
private fun PlanSelector(selected: PaywallPlan, onSelect: (PaywallPlan) -> Unit) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier.fillMaxWidth().clip(CircleShape).background(colors.fog).padding(4.dp),
    ) {
        PlanPill(PaywallPlan.Plus, selected == PaywallPlan.Plus, { onSelect(PaywallPlan.Plus) }, Modifier.weight(1f))
        PlanPill(PaywallPlan.Pro, selected == PaywallPlan.Pro, { onSelect(PaywallPlan.Pro) }, Modifier.weight(1f))
    }
}

@Composable
private fun BillingSelector(plan: PaywallPlan, selected: PaywallBilling, onSelect: (PaywallBilling) -> Unit) {
    val colors = RdTheme.colors
    val accent = if (plan == PaywallPlan.Plus) PaywallGoldDeep else colors.greenDark
    val accentSoft = if (plan == PaywallPlan.Plus) PaywallGoldSoft else colors.greenSoft
    Row(
        modifier = Modifier.fillMaxWidth().clip(CircleShape).background(colors.fog).padding(4.dp),
    ) {
        PaywallPill(stringResource(RdR.string.rd_aylik), selected == PaywallBilling.Monthly, { onSelect(PaywallBilling.Monthly) }, Modifier.weight(1f), accent, accentSoft)
        PaywallPill(stringResource(RdR.string.rd_yillik), selected == PaywallBilling.Yearly, { onSelect(PaywallBilling.Yearly) }, Modifier.weight(1f), accent, accentSoft)
    }
}

@Composable
private fun PlanPill(plan: PaywallPlan, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    val isPlus = plan == PaywallPlan.Plus
    val accent = if (isPlus) PaywallGoldDeep else colors.greenDark
    val soft = if (isPlus) PaywallGoldSoft else colors.greenSoft
    Row(
        modifier = modifier.height(38.dp).clip(CircleShape)
            .background(if (selected) soft else colors.fog)
            .border(1.dp, if (selected) accent.copy(alpha = .28f) else colors.fog, CircleShape)
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Icon(if (isPlus) Icons.Filled.WorkspacePremium else Icons.Filled.Star, null, tint = if (selected) accent else colors.slate, modifier = Modifier.size(13.dp))
        Spacer(Modifier.size(5.dp))
        Text(stringResource(if (isPlus) RdR.string.rd_plus else RdR.string.rd_pro), style = RdFontStyle.Callout.toTextStyle(), color = if (selected) accent else colors.slate, fontWeight = FontWeight.Black)
    }
}

@Composable
private fun PaywallPill(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    accent: Color = RdTheme.colors.onyx,
    accentSoft: Color = RdTheme.colors.white,
) {
    val colors = RdTheme.colors
    Box(
        modifier = modifier
            .height(38.dp)
            .clip(CircleShape)
            .background(if (selected) accentSoft else colors.fog)
            .border(1.dp, if (selected) accent.copy(alpha = .24f) else colors.fog, CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = RdFontStyle.Callout.toTextStyle(), color = if (selected) accent else colors.slate, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun ProductHeading(plan: PaywallPlan, billing: PaywallBilling, pkg: BillingPackage?) {
    val colors = RdTheme.colors
    Column {
        ProductBadge(plan)
        Spacer(Modifier.height(if (plan == PaywallPlan.Plus) 6.dp else 4.dp))
        Text(
            when {
                plan == PaywallPlan.Plus && billing == PaywallBilling.Yearly -> stringResource(RdR.string.rd_ilk_haftaniz_bizden)
                plan == PaywallPlan.Plus -> stringResource(RdR.string.rd_plus_abone_olun)
                else -> stringResource(RdR.string.rd_limitsiz_ozellikler)
            },
            style = RdFontStyle.Title1.toTextStyle(),
            color = colors.onyx,
            fontWeight = FontWeight.Black,
        )
        Text(
            when {
                pkg == null -> stringResource(RdR.string.rd_google_play_fiyati_yukleniyor)
                billing == PaywallBilling.Yearly -> stringResource(RdR.string.rd_yillik_plan_fiyat_ozellik_format, pkg.formattedPrice, plan.name)
                else -> stringResource(RdR.string.rd_aylik_plan_fiyat_ozellik_format, plan.name, pkg.formattedPrice)
            },
            style = RdFontStyle.Footnote.toTextStyle(),
            color = colors.slate,
        )
    }
}

@Composable
private fun ProductBadge(plan: PaywallPlan) {
    val colors = RdTheme.colors
    val isPlus = plan == PaywallPlan.Plus
    val background = if (isPlus) PaywallGoldSoft else colors.onyx
    val foreground = if (isPlus) PaywallGoldDeep else colors.white
    val iconTint = if (isPlus) PaywallGoldBase else colors.green
    Row(
        Modifier.clip(RoundedCornerShape(7.dp)).background(background)
            .border(1.dp, if (isPlus) PaywallGoldEdge else colors.onyx, RoundedCornerShape(7.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(if (isPlus) Icons.Filled.WorkspacePremium else Icons.Filled.Star, null, tint = iconTint, modifier = Modifier.size(12.dp))
        Text(if (isPlus) "PLUS" else "PRO", style = RdFontStyle.Caption.toTextStyle(), color = foreground, fontWeight = FontWeight.Black)
    }
}

@Composable
private fun FeatureCard(plan: PaywallPlan) {
    val colors = RdTheme.colors
    val accent = if (plan == PaywallPlan.Plus) PaywallGoldDeep else colors.greenDark
    val soft = if (plan == PaywallPlan.Plus) PaywallGoldSoft else colors.greenSoft
    val features = if (plan == PaywallPlan.Plus) {
        listOf(
            stringResource(RdR.string.rd_plus_analiz_limitleri),
            stringResource(RdR.string.rd_ucretli_fotograf_bulgu_limitleri),
            stringResource(RdR.string.rd_plus_rapor_limiti),
            stringResource(RdR.string.rd_plus_firma_saklama),
            stringResource(RdR.string.rd_ai_bulgularini_duzenleme),
        )
    } else {
        listOf(
            stringResource(RdR.string.rd_pro_analiz_limitleri),
            stringResource(RdR.string.rd_ucretli_fotograf_bulgu_limitleri),
            stringResource(RdR.string.rd_pro_rapor_limiti),
            stringResource(RdR.string.rd_pro_firma_saklama),
            stringResource(RdR.string.rd_tum_pro_analiz_kanvaslari),
        )
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(soft.copy(alpha = .32f))
            .border(1.dp, accent.copy(alpha = .18f), RoundedCornerShape(RdRadius.lg))
            .padding(RdSpacing.md),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        features.forEach { feature ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = accent, modifier = Modifier.size(18.dp))
                Text(feature, style = RdFontStyle.Callout.toTextStyle(), color = colors.onyx)
            }
        }
    }
}

@Composable
private fun ComparisonCard(onSelect: (PaywallPlan) -> Unit) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.greenSoft)
            .border(1.dp, colors.green.copy(alpha = .20f), RoundedCornerShape(RdRadius.lg))
            .clickable { onSelect(PaywallPlan.Pro) }
            .padding(RdSpacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Icon(Icons.Filled.Star, null, tint = colors.greenDark, modifier = Modifier.size(17.dp))
            Text(stringResource(RdR.string.rd_daha_fazlasina_mi_ihtiyaciniz_var), style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx)
        }
        Text(stringResource(RdR.string.rd_pro_ile_daha_yuksek_analiz_rapor_ve_firma_limitlerini_i), style = RdFontStyle.Footnote.toTextStyle(), color = colors.greenDark)
    }
}

private fun SubscriptionTier.includes(other: SubscriptionTier): Boolean = when (this) {
    SubscriptionTier.Pro -> other == SubscriptionTier.Plus || other == SubscriptionTier.Pro
    SubscriptionTier.Plus -> other == SubscriptionTier.Plus
    SubscriptionTier.Free -> false
}

@Composable
private fun packageLegalLine(billing: PaywallBilling, pkg: BillingPackage): String =
    stringResource(
        RdR.string.rd_abonelik_yenileme_format,
        stringResource(if (billing == PaywallBilling.Yearly) RdR.string.rd_yillik else RdR.string.rd_aylik),
        pkg.formattedPrice,
    )

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
