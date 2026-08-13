package com.riskdetectedan.app.push

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.notifications.NotificationEngagementRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class NotificationEngagementRegistrarViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val engagementRepository: NotificationEngagementRepository,
) : ViewModel() {
    init {
        viewModelScope.launch {
            authRepository.currentUserIdFlow.collectLatest { userId ->
                if (userId != null) engagementRepository.sync(userId)
            }
        }
    }

    fun refresh() {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch { engagementRepository.sync(userId) }
    }
}

@Composable
fun NotificationEngagementRegistrar(
    viewModel: NotificationEngagementRegistrarViewModel = hiltViewModel(),
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
