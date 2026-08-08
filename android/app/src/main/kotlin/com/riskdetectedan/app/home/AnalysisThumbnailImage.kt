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
import com.riskdetectedan.core.data.analysis.PhotoRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Real port of `AnalysisThumbnail.swift` — authenticated Storage download of a `photos.
 * storage_path`, decoded and shown once, cached for the ViewModel's lifetime by `loadedPath`
 * (matches the Swift `@State loadedPath` re-download guard exactly, just as a StateFlow instead
 * of `@State`). One instance per card ([AnalysisThumbnailImage] callers pass a `key` scoped to
 * the path so [hiltViewModel] mints a distinct instance per ring card, not one shared instance
 * racing between rows — the same tradeoff iOS makes implicitly via one `@State` per `View`
 * struct instance).
 */
@HiltViewModel
class AnalysisThumbnailViewModel @Inject constructor(
    private val photoRepository: PhotoRepository,
) : ViewModel() {
    private val _bitmap = MutableStateFlow<Bitmap?>(null)
    val bitmap: StateFlow<Bitmap?> = _bitmap.asStateFlow()
    private var loadedPath: String? = null

    fun load(path: String?) {
        if (path == null || path == loadedPath) return
        loadedPath = path
        _bitmap.value = null
        viewModelScope.launch {
            val bytes = (photoRepository.downloadPhoto(path) as? RdResult.Success)?.value
            _bitmap.value = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        }
    }
}

/** No-op (transparent) when [path] is null or the download/decode hasn't resolved yet — the
 * caller is expected to layer this over its own placeholder fallback (same as `AnalysisThumbnail`
 * showing `RDPlaceholderPhoto` underneath until `image` loads), not a self-contained placeholder
 * of its own. */
@Composable
fun AnalysisThumbnailImage(path: String?, modifier: Modifier = Modifier) {
    val viewModel: AnalysisThumbnailViewModel = hiltViewModel(key = path ?: "rd-analysis-thumbnail-empty")
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
