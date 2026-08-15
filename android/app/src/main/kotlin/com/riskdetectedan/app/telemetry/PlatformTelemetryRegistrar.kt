package com.riskdetectedan.app.telemetry

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.telemetry.PlatformTelemetryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Process-scoped authenticated-session observer. Platform analytics is intentionally isolated
 * from sign-in and profile success; an unavailable RPC can never reject or delay authentication.
 */
@HiltViewModel
class PlatformTelemetryRegistrarViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val telemetryRepository: PlatformTelemetryRepository,
    @ApplicationContext context: Context,
) : ViewModel() {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    init {
        viewModelScope.launch {
            authRepository.currentUserIdFlow.collectLatest { userId ->
                if (userId != null) recordIfNeeded(userId)
            }
        }
    }

    fun refresh() {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch { recordIfNeeded(userId) }
    }

    private suspend fun recordIfNeeded(userId: String) {
        val today = istanbulDay()
        if (preferences.getString(storageKey(userId), null) == today) return

        repeat(MAX_ATTEMPTS) { attempt ->
            if (authRepository.currentUserId != userId) return
            if (attempt > 0) delay(RETRY_DELAYS_MS[attempt - 1])
            when (val result = telemetryRepository.recordCurrentPlatform()) {
                is RdResult.Success -> if (result.value.recorded) {
                    preferences.edit()
                        .putString(storageKey(userId), result.value.activityDay ?: today)
                        .apply()
                    return
                }
                is RdResult.Failure -> Unit
            }
        }
    }

    private fun storageKey(userId: String) = "platform_day_${userId.lowercase()}"

    private fun istanbulDay(): String = LocalDate.now(ISTANBUL_ZONE).toString()

    private companion object {
        const val PREFERENCES = "rd_platform_telemetry_v1"
        const val MAX_ATTEMPTS = 3
        val RETRY_DELAYS_MS = longArrayOf(500L, 1_500L)
        val ISTANBUL_ZONE: ZoneId = ZoneId.of("Europe/Istanbul")
    }
}

@Composable
fun PlatformTelemetryRegistrar(
    viewModel: PlatformTelemetryRegistrarViewModel = hiltViewModel(),
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) viewModel.refresh()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
}
