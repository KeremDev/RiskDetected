package com.riskdetectedan.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.profile.RiskMethodWire
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.data.progress.ProfessionalProgressRepository
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface ProfileUiState {
    data object Loading : ProfileUiState
    data class Loaded(val profile: UserProfile) : ProfileUiState
    data class Failed(val error: AppErrorMessage) : ProfileUiState
    data object SignedOut : ProfileUiState
}

private const val PROFILE_CONTEXT = "Profil işlemi tamamlanamadı"

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val profileRepository: ProfileRepository,
    private val professionalProgressRepository: ProfessionalProgressRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<ProfileUiState>(ProfileUiState.Loading)
    val state: StateFlow<ProfileUiState> = _state.asStateFlow()

    // Null while loading/unavailable — the card that reads this just doesn't render rather than
    // showing an error, matching this feature's non-blocking nature on iOS too (a progress fetch
    // failure there just logs and returns nil, never surfaces an error to the user).
    private val _progress = MutableStateFlow<ProfessionalProgressSummary?>(null)
    val progress: StateFlow<ProfessionalProgressSummary?> = _progress.asStateFlow()

    private val _isSaving = MutableStateFlow(false)
    val isSaving: StateFlow<Boolean> = _isSaving.asStateFlow()

    private val _saveError = MutableStateFlow<AppErrorMessage?>(null)
    val saveError: StateFlow<AppErrorMessage?> = _saveError.asStateFlow()

    /** Separate from [isSaving]/[saveError] — the avatar picker lives on [ProfileHero] (outside
     * the edit form), a distinct action with its own in-flight/error state so it doesn't fight
     * over the edit form's flags. */
    private val _isSavingAvatar = MutableStateFlow(false)
    val isSavingAvatar: StateFlow<Boolean> = _isSavingAvatar.asStateFlow()

    private val _avatarError = MutableStateFlow<AppErrorMessage?>(null)
    val avatarError: StateFlow<AppErrorMessage?> = _avatarError.asStateFlow()

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
                is RdResult.Failure -> ProfileUiState.Failed(
                    AppErrorMessages.make(result.message, context = PROFILE_CONTEXT),
                )
            }
        }
        viewModelScope.launch {
            when (val result = professionalProgressRepository.fetchSummary(userId)) {
                is RdResult.Success -> _progress.value = result.value
                is RdResult.Failure -> Unit // non-blocking, see _progress's doc comment
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
                        _saveError.value = AppErrorMessages.make(upload.message, context = PROFILE_CONTEXT)
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
                    _saveError.value = AppErrorMessages.make(result.message, context = PROFILE_CONTEXT)
                }
            }
        }
    }

    fun clearSaveError() {
        _saveError.value = null
    }

    /** Real port of `handleProfileAvatarSelection` — upload then reload the full profile
     * (matches iOS's `saveProfileAvatar` -> `refreshProfile()` pair rather than trusting a local
     * echo, same discipline as [saveProfile]). */
    fun updateAvatar(jpegBytes: ByteArray) {
        val current = (_state.value as? ProfileUiState.Loaded)?.profile ?: return
        if (_isSavingAvatar.value) return
        _isSavingAvatar.value = true
        _avatarError.value = null
        viewModelScope.launch {
            when (val result = profileRepository.uploadAvatar(current.id, jpegBytes)) {
                is RdResult.Success -> {
                    _isSavingAvatar.value = false
                    load()
                }
                is RdResult.Failure -> {
                    _isSavingAvatar.value = false
                    _avatarError.value = AppErrorMessages.make(result.message, context = PROFILE_CONTEXT)
                }
            }
        }
    }

    fun clearAvatarError() {
        _avatarError.value = null
    }
}
