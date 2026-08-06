package com.riskdetectedan.feature.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.notifications.ProgressPreference
import com.riskdetectedan.core.designsystem.RdSpacing

/** Port of NotificationService.swift's preference-toggle surface — the master enabled/disable
 * + app_reminders + 3 progress flags this service actually exposes toggle UI for. APNs/FCM
 * device-token registration (the rest of that 684-line file) not ported — separate, needs a
 * real Firebase project (Faz 7). */
@Composable
fun NotificationSettingsScreen(viewModel: NotificationSettingsViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()

    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Bildirim ayarları")
        when (val current = state) {
            is NotificationSettingsUiState.Loading -> CircularProgressIndicator()
            is NotificationSettingsUiState.SignedOut -> Text("Oturum yok")
            is NotificationSettingsUiState.Failed -> Text(current.message)
            is NotificationSettingsUiState.Loaded -> {
                val prefs = current.preferences
                PreferenceRow("Bildirimler açık", prefs.enabled, viewModel::setMaster)
                PreferenceRow(
                    "Uygulama hatırlatmaları",
                    prefs.appReminders,
                    viewModel::setAppReminders,
                )
                PreferenceRow(
                    "Haftalık özet",
                    prefs.progressWeeklySummary,
                ) { viewModel.setProgressPreference(ProgressPreference.WeeklySummary, it) }
                PreferenceRow(
                    "Aylık özet",
                    prefs.progressMonthlySummary,
                ) { viewModel.setProgressPreference(ProgressPreference.MonthlySummary, it) }
                PreferenceRow(
                    "Kilometre taşları",
                    prefs.progressMilestones,
                ) { viewModel.setProgressPreference(ProgressPreference.Milestones, it) }
            }
        }
    }
}

@Composable
private fun PreferenceRow(label: String, checked: Boolean, onToggle: (Boolean) -> Unit) {
    Row(modifier = Modifier.fillMaxWidth().padding(vertical = RdSpacing.xs)) {
        Text(label, modifier = Modifier.padding(end = RdSpacing.sm))
        Switch(checked = checked, onCheckedChange = onToggle)
    }
}
