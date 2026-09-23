package com.riskdetectedan.app.network

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.riskdetectedan.core.data.network.NetworkMonitor
import com.riskdetectedan.core.designsystem.RdSpacing
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.delay

@HiltViewModel
class NetworkStatusViewModel @Inject constructor(
    networkMonitor: NetworkMonitor,
) : ViewModel() {
    val isOnline = networkMonitor.isOnline
}

/**
 * Mirrors RootView.swift's `OfflineStatusBanner` — same copy, same trigger (only render when
 * offline for 4 seconds while the app is in the foreground). Plain Material surface, not the real blurred/bordered design (deferred visual-parity
 * pass, same as every other screen). Caller is responsible for placement (RootView.swift shows
 * it at the top, above everything except the splash/hard-update screen) — this composable is
 * just the banner content, no positioning of its own.
 */
@Composable
fun NetworkStatusBanner(modifier: Modifier = Modifier, viewModel: NetworkStatusViewModel = hiltViewModel()) {
    val isOnline by viewModel.isOnline.collectAsState()
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val activelyOffline = !isOnline && lifecycleState.isAtLeast(Lifecycle.State.RESUMED)
    var showBanner by remember { mutableStateOf(false) }
    LaunchedEffect(activelyOffline) {
        if (!activelyOffline) {
            showBanner = false
            return@LaunchedEffect
        }
        // A network can briefly drop during Wi-Fi/cellular handoffs. Sync status stays immediate;
        // the user-facing warning only appears if the interruption persists (RootView.swift).
        delay(4_000)
        showBanner = true
    }
    if (!showBanner) return

    Text(
        stringResource(RdR.string.rd_offline_banner),
        modifier = modifier
            .padding(RdSpacing.sm)
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.errorContainer)
            .padding(horizontal = RdSpacing.md, vertical = RdSpacing.sm),
        color = MaterialTheme.colorScheme.onErrorContainer,
    )
}
