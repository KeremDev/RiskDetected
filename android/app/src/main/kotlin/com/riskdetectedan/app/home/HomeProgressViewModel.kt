package com.riskdetectedan.app.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.progress.ProfessionalProgressRepository
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Faz S — Home's own professional-progress fetch, same non-blocking shape as
 * `ProfileViewModel`'s `_progress` (see that file's doc comment: a failed/absent fetch just
 * means the card doesn't show, never an error state). A second small ViewModel rather than
 * reusing `ProfileViewModel` directly — `feature:profile`'s ViewModel also owns unrelated
 * profile-edit-form state that Home has no business depending on.
 */
@HiltViewModel
class HomeProgressViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val progressRepository: ProfessionalProgressRepository,
) : ViewModel() {

    private val _progress = MutableStateFlow<ProfessionalProgressSummary?>(null)
    val progress: StateFlow<ProfessionalProgressSummary?> = _progress.asStateFlow()

    fun refresh() {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch {
            when (val result = progressRepository.fetchSummary(userId)) {
                is RdResult.Success -> _progress.value = result.value
                is RdResult.Failure -> Unit
            }
        }
    }
}
