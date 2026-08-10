package com.riskdetectedan.feature.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.profile.ProfileRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Real port of `profileAvatarImage(path:)` + `AuthService.swift`'s avatar-load pattern —
 * authenticated Storage download, decoded once, cached for the ViewModel's lifetime. Same
 * self-contained-loader shape as `app/home/AnalysisThumbnailImage.kt` (feature:profile can't
 * depend on the app module, so this is a small local twin rather than a shared one — same
 * "duplicate a tiny loader per module" tradeoff already accepted elsewhere in this codebase). */
@HiltViewModel
class ProfileAvatarViewModel @Inject constructor(
    private val profileRepository: ProfileRepository,
) : ViewModel() {
    private val _bitmap = MutableStateFlow<Bitmap?>(null)
    val bitmap: StateFlow<Bitmap?> = _bitmap.asStateFlow()
    private var loadedPath: String? = null

    fun load(path: String?) {
        if (path == null || path == loadedPath) return
        loadedPath = path
        _bitmap.value = null
        viewModelScope.launch {
            val bytes = (profileRepository.downloadAvatar(path) as? RdResult.Success)?.value
            _bitmap.value = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        }
    }
}

/** Transparent when [path] is null or not yet resolved — caller layers this over its own
 * initials/placeholder fallback, same convention as `AnalysisThumbnailImage`. */
@Composable
fun ProfileAvatarImage(path: String?, modifier: Modifier = Modifier) {
    val viewModel: ProfileAvatarViewModel = hiltViewModel(key = path ?: "rd-profile-avatar-empty")
    LaunchedEffect(path) { viewModel.load(path) }
    val bitmap by viewModel.bitmap.collectAsState()
    bitmap?.let {
        Image(
            bitmap = it.asImageBitmap(),
            contentDescription = null,
            modifier = modifier.fillMaxSize(),
            contentScale = ContentScale.Crop,
        )
    }
}
