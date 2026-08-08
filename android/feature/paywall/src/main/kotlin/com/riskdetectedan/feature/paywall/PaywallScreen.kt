package com.riskdetectedan.feature.paywall

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.billing.BillingPackage
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Real RevenueCat-backed paywall (2026-08-08 visual pass, Faz L of the core-flow redesign, last
 * screen — Faz 4's real purchase flow via [PaywallViewModel]/[BillingRepository], mirrors
 * SubscriptionManager.swift's configure -> identify -> loadOfferings -> purchase flow). All
 * ViewModel logic unchanged — pure UI-layer pass, proves the real purchase path end to end same
 * as before, just styled now. Real hero + package cards (tier/price/CTA) replacing the plain
 * ListItem+Button stack, [RdEmptyState] for the honest "paketler henüz yapılandırılmadı" case
 * (RevenueCat has no packages configured on this offering yet — separate task from this SDK
 * wiring, not a bug this pass introduces or hides).
 */
@Composable
fun PaywallScreen(onBack: (() -> Unit)? = null, viewModel: PaywallViewModel = hiltViewModel()) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val isPurchasing by viewModel.isPurchasing.collectAsState()
    val purchaseError by viewModel.purchaseError.collectAsState()
    val activity = LocalContext.current.findActivity()

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = "Planı Yükselt", onBack = onBack)

        when (val current = state) {
            is PaywallUiState.Loading -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
            }
            is PaywallUiState.SignedOut -> RdEmptyState(
                icon = Icons.Filled.WorkspacePremium,
                title = "Oturum yok",
                subtitle = "Planını yükseltmek için giriş yapmalısın.",
            )
            is PaywallUiState.Failed -> RdEmptyState(
                icon = Icons.Filled.WorkspacePremium,
                title = "Paketler yüklenemedi",
                subtitle = current.error.message,
            )
            is PaywallUiState.Loaded -> Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = RdSpacing.lg),
            ) {
                PaywallHero(currentTier = current.currentTier.name)

                Spacer(Modifier.height(RdSpacing.md))
                if (current.packages.isEmpty()) {
                    // RevenueCat has no packages configured for this offering yet (Play Console
                    // subscription products aren't created — separate task from this SDK wiring,
                    // needs pricing/base-plan decisions) — honest empty state, not a fake list.
                    RdEmptyState(
                        icon = Icons.Filled.WorkspacePremium,
                        title = "Abonelik paketleri henüz yapılandırılmadı",
                        subtitle = "Yakında burada gerçek fiyatlarla listelenecek.",
                    )
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                        current.packages.forEach { pkg ->
                            PackageCard(
                                pkg = pkg,
                                isPurchasing = isPurchasing,
                                enabled = !isPurchasing && activity != null,
                                onPurchase = { activity?.let { viewModel.purchase(it, pkg) } },
                            )
                        }
                    }
                }

                Spacer(Modifier.height(RdSpacing.sm))
                TextButton(
                    onClick = viewModel::restorePurchases,
                    enabled = !isPurchasing,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Satın alımları geri yükle", style = RdFontStyle.Footnote.toTextStyle())
                }
                Spacer(Modifier.height(RdSpacing.lg))
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
            confirmButton = {
                TextButton(onClick = viewModel::clearPurchaseError) { Text("Tamam") }
            },
        )
    }
}

@Composable
private fun PaywallHero(currentTier: String) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.md),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier.size(56.dp).clip(CircleShape).background(colors.planPlusSoft),
            contentAlignment = Alignment.Center,
        ) {
            androidx.compose.material3.Icon(
                Icons.Filled.WorkspacePremium,
                contentDescription = null,
                tint = colors.planPlusDark,
                modifier = Modifier.size(26.dp),
            )
        }
        Spacer(Modifier.height(RdSpacing.xs))
        Text("Mevcut plan: $currentTier", style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)
    }
}

@Composable
private fun PackageCard(pkg: BillingPackage, isPurchasing: Boolean, enabled: Boolean, onPurchase: () -> Unit) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.white)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(RdRadius.lg))
            .padding(RdSpacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(pkg.tier.name, style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx)
                Text(pkg.productId, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }
            Text(pkg.formattedPrice, style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx)
        }
        Spacer(Modifier.height(RdSpacing.sm))
        RdPrimaryButton(
            text = if (isPurchasing) "İşleniyor..." else "Satın al",
            onClick = onPurchase,
            enabled = enabled,
            style = RdButtonStyle.Onyx,
            showArrow = false,
        )
    }
}

/** RevenueCat's `PurchaseParams.Builder` needs an Activity (to launch Google Play's billing
 * sheet) — `LocalContext.current` in a Composable is often an Activity already but isn't
 * guaranteed to be one (can be wrapped), so unwrap defensively rather than force-casting. */
private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
