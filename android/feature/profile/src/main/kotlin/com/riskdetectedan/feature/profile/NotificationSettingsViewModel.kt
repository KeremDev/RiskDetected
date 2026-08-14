package com.riskdetectedan.feature.profile

import android.content.Context
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
            _state.value = when (val result = preferencesRepository.fetch(userId)) {
                is RdResult.Success -> NotificationSettingsUiState.Loaded(result.value)
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
            preferencesRepository.setMasterPreference(enabled)
            authRepository.currentUserId?.let { engagementRepository.sync(it, force = true) }
            load()
        }
    }

    fun setProgressPreference(preference: ProgressPreference, enabled: Boolean) {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch {
            val current = state.value as? NotificationSettingsUiState.Loaded
            if (current == null || !current.preferences.enabled) {
                preferencesRepository.setMasterPreference(true)
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
                preferencesRepository.setMasterPreference(true)
            }
            preferencesRepository.setAppRemindersPreference(userId, enabled)
            load()
        }
    }
}
