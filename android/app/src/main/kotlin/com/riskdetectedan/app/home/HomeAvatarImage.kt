package com.riskdetectedan.app.home

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
import androidx.hilt.navigation.compose.hiltViewModel
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

/** Same self-contained-loader shape as [AnalysisThumbnailImage], targeting the "avatars" bucket
 * instead of "photos" — feeds [HomeHeaderAvatar]'s real-photo layer. A small twin of
 * `feature/profile/ProfileAvatarImage.kt` rather than a shared component: `app` and
 * `feature:profile` don't share a common UI module either could live in without a bigger
 * restructure, same tradeoff already accepted for the thumbnail loaders. */
@HiltViewModel
class HomeAvatarViewModel @Inject constructor(
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

@Composable
fun HomeAvatarImage(path: String?, modifier: Modifier = Modifier) {
    val viewModel: HomeAvatarViewModel = hiltViewModel(key = path ?: "rd-home-avatar-empty")
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
