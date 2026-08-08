package com.riskdetectedan.feature.profile

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
import androidx.hilt.navigation.compose.hiltViewModel
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

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = "Bildirim Ayarları", onBack = onBack)

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.lg)) {
            when (val current = state) {
                is NotificationSettingsUiState.Loading -> Box(modifier = Modifier.fillMaxWidth().padding(RdSpacing.xl), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.onyx)
                }
                is NotificationSettingsUiState.SignedOut -> RdEmptyState(
                    icon = Icons.Filled.Notifications,
                    title = "Oturum yok",
                    subtitle = "Bildirim ayarlarını görmek için giriş yapmalısın.",
                )
                is NotificationSettingsUiState.Failed -> RdEmptyState(
                    icon = Icons.Filled.Notifications,
                    title = "Ayarlar yüklenemedi",
                    subtitle = current.error.message,
                )
                is NotificationSettingsUiState.Loaded -> {
                    val prefs = current.preferences
                    RdSectionCard {
                        Column {
                            PreferenceRow("Bildirimler açık", prefs.enabled, viewModel::setMaster)
                            PreferenceRow("Uygulama hatırlatmaları", prefs.appReminders, viewModel::setAppReminders)
                            PreferenceRow("Haftalık özet", prefs.progressWeeklySummary) {
                                viewModel.setProgressPreference(ProgressPreference.WeeklySummary, it)
                            }
                            PreferenceRow("Aylık özet", prefs.progressMonthlySummary) {
                                viewModel.setProgressPreference(ProgressPreference.MonthlySummary, it)
                            }
                            PreferenceRow("Kilometre taşları", prefs.progressMilestones) {
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
        Text(label, style = RdFontStyle.Callout.toTextStyle(), color = colors.onyx, modifier = Modifier.padding(end = RdSpacing.sm))
        Switch(
            checked = checked,
            onCheckedChange = onToggle,
            colors = SwitchDefaults.colors(checkedTrackColor = colors.green, checkedThumbColor = colors.white),
        )
    }
}
