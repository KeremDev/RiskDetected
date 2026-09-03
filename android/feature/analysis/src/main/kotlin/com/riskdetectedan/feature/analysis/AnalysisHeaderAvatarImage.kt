package com.riskdetectedan.feature.analysis

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

/** Authenticated avatar loader for the result header.
 *
 * Feature modules cannot depend on the app module's `HomeAvatarImage`, so this intentionally
 * mirrors its tiny loader while keeping the result header visually identical to Home.
 */
@HiltViewModel
class AnalysisHeaderAvatarViewModel @Inject constructor(
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
fun AnalysisHeaderAvatarImage(path: String?, modifier: Modifier = Modifier) {
    val viewModel: AnalysisHeaderAvatarViewModel = hiltViewModel(key = path ?: "rd-analysis-avatar-empty")
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
