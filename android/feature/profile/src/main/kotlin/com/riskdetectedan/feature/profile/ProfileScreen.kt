package com.riskdetectedan.feature.profile

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * First real (non-placeholder) render in feature:profile — reads the actual `profiles` row
 * for the signed-in user via [ProfileViewModel]/`ProfileRepository`. Layout/fields still far
 * short of App/Views/Profile/ProfileView.swift; this proves the read path end to end first.
 */
@Composable
fun ProfileScreen(
    onManageCompanies: () -> Unit = {},
    onSupport: () -> Unit = {},
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(RdSpacing.lg),
        contentAlignment = Alignment.Center,
    ) {
        when (val current = state) {
            is ProfileUiState.Loading -> CircularProgressIndicator()
            is ProfileUiState.SignedOut -> Text("Oturum yok")
            is ProfileUiState.Failed -> Text("Profil yüklenemedi: ${current.message}")
            is ProfileUiState.Loaded -> Column {
                Text(current.profile.displayName)
                Text(current.profile.tier.name)
                Button(onClick = onManageCompanies) { Text("Firmalarım") }
                Button(onClick = onSupport) { Text("Destek") }
            }
        }
    }
}
