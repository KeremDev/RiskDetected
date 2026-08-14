package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.designsystem.R as RdR

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.notifications.ProgressPreference
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSectionCard
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/** Port of NotificationService.swift's preference-toggle surface (2026-08-08 visual pass,
 * Faz K of the core-flow redesign) — the master enabled/disable + app_reminders + 3 progress
 * flags this service actually exposes toggle UI for. APNs/FCM device-token registration (the
 * rest of that 684-line file) not ported — separate, needs a real Firebase project (Faz 7).
 * ViewModel logic unchanged. */
@Composable
fun NotificationSettingsScreen(onBack: (() -> Unit)? = null, viewModel: NotificationSettingsViewModel = hiltViewModel()) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> viewModel.setMaster(granted) }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = stringResource(RdR.string.rd_bildirim_ayarlari), onBack = onBack)

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.lg)) {
            when (val current = state) {
                is NotificationSettingsUiState.Loading -> Box(modifier = Modifier.fillMaxWidth().padding(RdSpacing.xl), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.black)
                }
                is NotificationSettingsUiState.SignedOut -> RdEmptyState(
                    icon = Icons.Filled.Notifications,
                    title = stringResource(RdR.string.rd_oturum_yok),
                    subtitle = stringResource(RdR.string.rd_bildirimleri_gormek_icin_giris),
                )
                is NotificationSettingsUiState.Failed -> RdEmptyState(
                    icon = Icons.Filled.Notifications,
                    title = stringResource(RdR.string.rd_ayarlar_yuklenemedi),
                    subtitle = current.error.message,
                )
                is NotificationSettingsUiState.Loaded -> {
                    val prefs = current.preferences
                    RdSectionCard {
                        Column {
                            PreferenceRow(stringResource(RdR.string.rd_bildirimler_acik), prefs.enabled) { enabled ->
                                if (!enabled || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                                    viewModel.setMaster(enabled)
                                } else if (
                                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                                    PackageManager.PERMISSION_GRANTED
                                ) {
                                    viewModel.setMaster(true)
                                } else {
                                    permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                                }
                            }
                            PreferenceRow(stringResource(RdR.string.rd_uygulama_hatirlatmalari), prefs.appReminders, viewModel::setAppReminders)
                            PreferenceRow(stringResource(RdR.string.rd_haftalik_ozet), prefs.progressWeeklySummary) {
                                viewModel.setProgressPreference(ProgressPreference.WeeklySummary, it)
                            }
                            PreferenceRow(stringResource(RdR.string.rd_aylik_ozet), prefs.progressMonthlySummary) {
                                viewModel.setProgressPreference(ProgressPreference.MonthlySummary, it)
                            }
                            PreferenceRow(stringResource(RdR.string.rd_kilometre_taslari), prefs.progressMilestones) {
                                viewModel.setProgressPreference(ProgressPreference.Milestones, it)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PreferenceRow(label: String, checked: Boolean, onToggle: (Boolean) -> Unit) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = RdSpacing.sm),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = RdFontStyle.Callout.toTextStyle(), color = colors.black, modifier = Modifier.padding(end = RdSpacing.sm))
        Switch(
            checked = checked,
            onCheckedChange = onToggle,
            colors = SwitchDefaults.colors(
                checkedTrackColor = colors.green,
                checkedThumbColor = androidx.compose.ui.graphics.Color.White,
                checkedBorderColor = colors.green,
                uncheckedTrackColor = colors.fog,
                uncheckedThumbColor = colors.slate.copy(alpha = 0.62f),
                uncheckedBorderColor = colors.line,
                disabledCheckedTrackColor = colors.green.copy(alpha = 0.45f),
                disabledCheckedThumbColor = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.72f),
                disabledUncheckedTrackColor = colors.fog.copy(alpha = 0.55f),
                disabledUncheckedThumbColor = colors.slate.copy(alpha = 0.32f),
            ),
        )
    }
}
