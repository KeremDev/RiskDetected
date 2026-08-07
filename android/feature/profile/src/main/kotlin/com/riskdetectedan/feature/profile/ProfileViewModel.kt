package com.riskdetectedan.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.profile.RiskMethodWire
import com.riskdetectedan.core.data.profile.UserProfile
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface ProfileUiState {
    data object Loading : ProfileUiState
    data class Loaded(val profile: UserProfile) : ProfileUiState
    data class Failed(val message: String) : ProfileUiState
    data object SignedOut : ProfileUiState
}

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val profileRepository: ProfileRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<ProfileUiState>(ProfileUiState.Loading)
    val state: StateFlow<ProfileUiState> = _state.asStateFlow()

    private val _isSaving = MutableStateFlow(false)
    val isSaving: StateFlow<Boolean> = _isSaving.asStateFlow()

    private val _saveError = MutableStateFlow<String?>(null)
    val saveError: StateFlow<String?> = _saveError.asStateFlow()

    init {
        load()
    }

    fun load() {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = ProfileUiState.SignedOut
            return
        }
        _state.value = ProfileUiState.Loading
        viewModelScope.launch {
            _state.value = when (val result = profileRepository.fetchProfile(userId)) {
                is RdResult.Success -> ProfileUiState.Loaded(result.value)
                is RdResult.Failure -> ProfileUiState.Failed(result.message)
            }
        }
    }

    /** Mirrors ProfileView.swift's `save()` basic-field subset (see ProfileRepository doc) —
     * reloads the full profile from the server on success rather than trusting the local echo,
     * matching AuthService.swift's own post-upsert `fetchProfile` call. [logoJpegBytes], when
     * present, is uploaded first (same "upload then reference the resulting path" order as
     * ProfileView.swift's `save()`: `resolvedLogoPath = try await auth.uploadProfileLogo(...)`
     * happens before `updateProfile` is called) — a failed logo upload aborts the whole save
     * (matches iOS: the upload is inside the same `do` block the profile update is in, so a
     * throw there skips the update too), unlike company logos where the company row itself is
     * still valid without one. */
    fun saveProfile(
        fullName: String,
        title: String,
        certificateNumber: String,
        companyName: String,
        phone: String,
        preferredMethod: RiskMethodWire?,
        logoJpegBytes: ByteArray? = null,
    ) {
        val current = (_state.value as? ProfileUiState.Loaded)?.profile ?: return
        if (_isSaving.value) return
        _isSaving.value = true
        _saveError.value = null
        viewModelScope.launch {
            val logoUrl = if (logoJpegBytes != null) {
                when (val upload = profileRepository.uploadProfileLogo(current.id, logoJpegBytes)) {
                    is RdResult.Success -> upload.value
                    is RdResult.Failure -> {
                        _isSaving.value = false
                        _saveError.value = upload.message
                        return@launch
                    }
                }
            } else {
                current.companyLogoUrl
            }

            when (
                val result = profileRepository.updateProfile(
                    current = current,
                    fullName = fullName,
                    title = title,
                    certificateNumber = certificateNumber,
                    companyName = companyName,
                    phone = phone,
                    preferredMethod = preferredMethod,
                    companyLogoUrl = logoUrl,
                )
            ) {
                is RdResult.Success -> {
                    _isSaving.value = false
                    load()
                }
                is RdResult.Failure -> {
                    _isSaving.value = false
                    _saveError.value = result.message
                }
            }
        }
    }

    fun clearSaveError() {
        _saveError.value = null
    }
}
