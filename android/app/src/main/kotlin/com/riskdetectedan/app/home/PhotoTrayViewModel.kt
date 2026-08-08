package com.riskdetectedan.app.home

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

/**
 * Backs Home's real multi-photo tray (Faz O — App/Views/Home/HomeView.swift's
 * `selectedPhotos`/`PhotoMediaTraySheet`). Deliberately scoped via `hiltViewModel()` to
 * [com.riskdetectedan.app.navigation.MainShell]'s own back stack entry (not Home's — Home is tab
 * *content* inside MainShell, it has no entry of its own) so it survives
 * [com.riskdetectedan.app.navigation.CaptureForTray] being pushed on top and popped — same
 * `NavBackStackEntry`-scoped ViewModel lifetime lesson learned fixing Faz M's active-tab reset
 * bug, applied here by construction instead of needing a `rememberSaveable` workaround.
 *
 * Holds local file paths only (not yet-uploaded bytes) — upload happens once at
 * [com.riskdetectedan.feature.analysis.AnalysisViewModel.createAnalysis] time, same as the
 * existing single-photo flow.
 */
@HiltViewModel
class PhotoTrayViewModel @Inject constructor() : ViewModel() {

    private val _photoPaths = MutableStateFlow<List<String>>(emptyList())
    val photoPaths: StateFlow<List<String>> = _photoPaths.asStateFlow()

    fun addPhoto(path: String) {
        _photoPaths.value = _photoPaths.value + path
    }

    fun addPhotos(paths: List<String>) {
        _photoPaths.value = _photoPaths.value + paths
    }

    fun removePhoto(path: String) {
        _photoPaths.value = _photoPaths.value.filterNot { it == path }
    }

    /** Mirrors `onMove(_:_:)` — swap with the neighbor at `index + delta`, clamped to bounds. */
    fun movePhoto(path: String, delta: Int) {
        val current = _photoPaths.value
        val index = current.indexOf(path)
        val target = index + delta
        if (index < 0 || target < 0 || target >= current.size) return
        _photoPaths.value = current.toMutableList().apply {
            val item = removeAt(index)
            add(target, item)
        }
    }

    fun clear() {
        _photoPaths.value = emptyList()
    }
}
