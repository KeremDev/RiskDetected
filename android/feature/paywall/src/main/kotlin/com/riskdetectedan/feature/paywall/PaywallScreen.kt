package com.riskdetectedan.feature.paywall

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.billing.BillingPackage
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * Real RevenueCat-backed paywall (Faz 4) — mirrors SubscriptionManager.swift's configure ->
 * identify -> loadOfferings -> purchase flow via [PaywallViewModel]/[BillingRepository]. Still
 * a plain Compose list, not App/Views/Paywall's real design (deferred visual-parity pass, same
 * as every other screen this session) — this proves the real purchase path end to end first.
 */
@Composable
fun PaywallScreen(viewModel: PaywallViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    val isPurchasing by viewModel.isPurchasing.collectAsState()
    val purchaseError by viewModel.purchaseError.collectAsState()
    val activity = LocalContext.current.findActivity()

    Box(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg), contentAlignment = Alignment.Center) {
        when (val current = state) {
            is PaywallUiState.Loading -> CircularProgressIndicator()
            is PaywallUiState.SignedOut -> Text("Oturum yok")
            is PaywallUiState.Failed -> Text("Paketler yüklenemedi: ${current.message}")
            is PaywallUiState.Loaded -> Column(modifier = Modifier.fillMaxWidth()) {
                Text("Mevcut plan: ${current.currentTier.name}")
                if (current.packages.isEmpty()) {
                    // RevenueCat has no packages configured for this offering yet (Play Console
                    // subscription products aren't created — separate task from this SDK wiring,
                    // needs pricing/base-plan decisions) — honest empty state, not a fake list.
                    Text("Abonelik paketleri henüz yapılandırılmadı.")
                } else {
                    LazyColumn(modifier = Modifier.padding(top = RdSpacing.sm)) {
                        items(current.packages, key = { it.id }) { pkg ->
                            ListItem(
                                headlineContent = { Text("${pkg.tier.name} — ${pkg.formattedPrice}") },
                                supportingContent = { Text(pkg.productId) },
                            )
                            Button(
                                onClick = { activity?.let { viewModel.purchase(it, pkg) } },
                                enabled = !isPurchasing && activity != null,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(if (isPurchasing) "İşleniyor..." else "Satın al")
                            }
                        }
                    }
                }
                TextButton(onClick = viewModel::restorePurchases, enabled = !isPurchasing) {
                    Text("Satın alımları geri yükle")
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
            confirmButton = {
                TextButton(onClick = viewModel::clearPurchaseError) { Text("Tamam") }
            },
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
