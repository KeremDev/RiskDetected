package com.riskdetectedan.feature.profile

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.billing.BillingRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.profile.ProfileStats
import com.riskdetectedan.core.data.profile.RiskMethodWire
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.data.progress.ProfessionalProgressBadge
import com.riskdetectedan.core.data.progress.ProfessionalProgressRepository
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.data.release.AndroidRuntimeGateName
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import com.riskdetectedan.core.designsystem.R as RdR
import dagger.hilt.android.qualifiers.ApplicationContext
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

sealed interface ProfileRestoreState {
    data object Idle : ProfileRestoreState
    data object Restoring : ProfileRestoreState
    data class Completed(val message: String) : ProfileRestoreState
    data class Failed(val error: AppErrorMessage) : ProfileRestoreState
}

@HiltViewModel
class ProfileViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val profileRepository: ProfileRepository,
    private val professionalProgressRepository: ProfessionalProgressRepository,
    private val billingRepository: BillingRepository,
    private val releasePolicyRepository: ReleasePolicyRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<ProfileUiState>(ProfileUiState.Loading)
    val state: StateFlow<ProfileUiState> = _state.asStateFlow()

    // Null while loading/unavailable — the card that reads this just doesn't render rather than
    // showing an error, matching this feature's non-blocking nature on iOS too (a progress fetch
    // failure there just logs and returns nil, never surfaces an error to the user).
    private val _progress = MutableStateFlow<ProfessionalProgressSummary?>(null)
    val progress: StateFlow<ProfessionalProgressSummary?> = _progress.asStateFlow()

    private val _stats = MutableStateFlow<ProfileStats?>(null)
    val stats: StateFlow<ProfileStats?> = _stats.asStateFlow()

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

    private val _restoreState = MutableStateFlow<ProfileRestoreState>(ProfileRestoreState.Idle)
    val restoreState: StateFlow<ProfileRestoreState> = _restoreState.asStateFlow()

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
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_profil_islemi_tamamlanamadi),
                    ),
                )
            }
        }
        viewModelScope.launch { refreshProgress(userId) }
        viewModelScope.launch {
            when (val result = profileRepository.fetchStats(userId)) {
                is RdResult.Success -> _stats.value = result.value
                is RdResult.Failure -> Unit
            }
        }
    }

    private suspend fun refreshProgress(userId: String) {
        when (val result = professionalProgressRepository.fetchSummary(userId)) {
            is RdResult.Success -> _progress.value = result.value
            is RdResult.Failure -> Unit // non-blocking, see _progress's doc comment
        }
    }

    /** Real port of `onClose`'s `markBadgeSeen` + `onRefresh` pair
     * ([ProfessionalProgressProfileSection.swift]) — marks the celebrated badge's `seen_at` (so
     * [ProfessionalProgressSummary.pendingCelebration] stops returning it) then refetches the
     * summary, matching the Swift call order exactly (seen-write happens before the refresh that
     * would otherwise immediately re-show the same sheet). */
    fun markBadgeSeen(badge: ProfessionalProgressBadge) {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch {
            professionalProgressRepository.markBadgeSeen(badge.id)
            refreshProgress(userId)
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
                        _saveError.value = AppErrorMessages.make(
                            upload.message,
                            context = context.getString(RdR.string.rd_profil_islemi_tamamlanamadi),
                        )
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
                    _saveError.value = AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_profil_islemi_tamamlanamadi),
                    )
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
                    _avatarError.value = AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_profil_islemi_tamamlanamadi),
                    )
                }
            }
        }
    }

    fun clearAvatarError() {
        _avatarError.value = null
    }

    fun restorePurchases() {
        if (_restoreState.value is ProfileRestoreState.Restoring) return
        val userId = authRepository.currentUserId ?: return
        _restoreState.value = ProfileRestoreState.Restoring
        viewModelScope.launch {
            val gate = releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Payments)
            if (!gate.enabled) {
                _restoreState.value = ProfileRestoreState.Failed(
                    AppErrorMessages.make(
                        context.getString(RdR.string.rd_satin_alma_kapali_format, gate.reason),
                        context = context.getString(RdR.string.rd_geri_yukleme_tamamlanamadi),
                    ),
                )
                return@launch
            }
            val configured = billingRepository.configure(userId)
            if (configured is RdResult.Failure) {
                _restoreState.value = ProfileRestoreState.Failed(
                    AppErrorMessages.make(
                        configured.message,
                        context = context.getString(RdR.string.rd_geri_yukleme_tamamlanamadi),
                    ),
                )
                return@launch
            }
            when (val result = billingRepository.restorePurchases()) {
                is RdResult.Success -> {
                    _restoreState.value = ProfileRestoreState.Completed(
                        if (result.value.isPaid) {
                            context.getString(RdR.string.rd_abonelik_bulundu_format, result.value.name)
                        } else {
                            context.getString(RdR.string.rd_google_play_aktif_abonelik_yok)
                        },
                    )
                    load()
                }
                is RdResult.Failure -> _restoreState.value = ProfileRestoreState.Failed(
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_geri_yukleme_tamamlanamadi),
                    ),
                )
            }
        }
    }

    fun clearRestoreState() {
        _restoreState.value = ProfileRestoreState.Idle
    }

    fun signOut() {
        viewModelScope.launch {
            when (val result = authRepository.signOut()) {
                is RdResult.Success -> {
                    billingRepository.clearUserIdentity()
                    _state.value = ProfileUiState.SignedOut
                }
                is RdResult.Failure -> _saveError.value = AppErrorMessages.make(
                    result.message,
                    context = context.getString(RdR.string.rd_cikis_yapilamadi),
                )
            }
        }
    }
}
