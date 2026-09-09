package com.riskdetectedan.feature.profile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.notifications.NotificationPreferences
import com.riskdetectedan.core.data.notifications.NotificationPreferencesRepository
import com.riskdetectedan.core.data.notifications.NotificationEngagementRepository
import com.riskdetectedan.core.data.notifications.ProgressPreference
import com.riskdetectedan.core.designsystem.R as RdR
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface NotificationSettingsUiState {
    data object Loading : NotificationSettingsUiState
    data object SignedOut : NotificationSettingsUiState
    data class Loaded(val preferences: NotificationPreferences) : NotificationSettingsUiState
    data class Failed(val error: AppErrorMessage) : NotificationSettingsUiState
}

@HiltViewModel
class NotificationSettingsViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val preferencesRepository: NotificationPreferencesRepository,
    private val engagementRepository: NotificationEngagementRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<NotificationSettingsUiState>(NotificationSettingsUiState.Loading)
    val state: StateFlow<NotificationSettingsUiState> = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = NotificationSettingsUiState.SignedOut
            return
        }
        _state.value = NotificationSettingsUiState.Loading
        viewModelScope.launch {
            _state.value = when (val result = preferencesRepository.fetchWithPresence(userId)) {
                is RdResult.Success -> {
                    val snapshot = result.value
                    val preferences = snapshot.preferences
                    // Repair accounts created by older Android builds: the OS permission may be
                    // granted while the preference row was never written. iOS already creates
                    // this row during onboarding; doing the same when the user opens Android's
                    // settings keeps the admin panel and profile state consistent after upgrade.
                    val hydratedPreferences = if (!snapshot.isPersisted && systemNotificationsGranted()) {
                        when (preferencesRepository.setMasterPreference(enabled = true)) {
                            is RdResult.Success -> {
                                engagementRepository.sync(userId, force = true)
                                (preferencesRepository.fetch(userId) as? RdResult.Success)?.value
                                    ?: preferences.copy(enabled = true)
                            }
                            is RdResult.Failure -> preferences
                        }
                    } else {
                        preferences
                    }
                    NotificationSettingsUiState.Loaded(hydratedPreferences)
                }
                is RdResult.Failure -> NotificationSettingsUiState.Failed(
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_bildirim_ayarlari_yuklenemedi),
                    ),
                )
            }
        }
    }

    /** Mirrors setProgressPreference/setAppRemindersPreference's "turn master on first if it
     * was never set" behavior — a progress/reminder toggle implies notifications are wanted. */
    fun setMaster(enabled: Boolean) {
        viewModelScope.launch {
            // Never mark the server preference enabled while Android has notifications blocked.
            // The screen normally requests POST_NOTIFICATIONS first; this guard keeps the same
            // invariant for any other caller and for resumed/stale UI state.
            if (enabled && !systemNotificationsGranted()) {
                load()
                return@launch
            }
            when (preferencesRepository.setMasterPreference(enabled)) {
                is RdResult.Success -> authRepository.currentUserId?.let { engagementRepository.sync(it, force = true) }
                is RdResult.Failure -> Unit
            }
            load()
        }
    }

    fun setProgressPreference(preference: ProgressPreference, enabled: Boolean) {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch {
            val current = state.value as? NotificationSettingsUiState.Loaded
            if (current == null || !current.preferences.enabled) {
                if (!ensurePreferenceRow(current)) {
                    load()
                    return@launch
                }
            }
            preferencesRepository.setProgressPreference(userId, preference, enabled)
            load()
        }
    }

    fun setAppReminders(enabled: Boolean) {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch {
            val current = state.value as? NotificationSettingsUiState.Loaded
            if (current == null || !current.preferences.enabled) {
                if (!ensurePreferenceRow(current)) {
                    load()
                    return@launch
                }
            }
            preferencesRepository.setAppRemindersPreference(userId, enabled)
            load()
        }
    }

    /**
     * A category toggle is also an implicit opt-in. Create the master row first, using the real
     * device authorization state instead of blindly enabling server notifications when Android
     * has them blocked. This mirrors iOS's `systemAuthorizationGranted` fallback and prevents a
     * direct category update from silently affecting zero rows when the preference record is new.
     */
    private suspend fun ensurePreferenceRow(current: NotificationSettingsUiState.Loaded?): Boolean {
        if (current?.preferences?.enabled == true) return true
        return preferencesRepository.setMasterPreference(systemNotificationsGranted()) is RdResult.Success
    }

    private fun systemNotificationsGranted(): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }
}
