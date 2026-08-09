package com.riskdetectedan.app.settings

import com.riskdetectedan.core.designsystem.R as RdR

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.ViewModel
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

enum class AppearanceMode { System, Light, Dark }

@Singleton
class AppearancePreferences @Inject constructor(@ApplicationContext context: Context) {
    private val preferences = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
    private val _mode = MutableStateFlow(
        runCatching { AppearanceMode.valueOf(preferences.getString("mode", null).orEmpty()) }
            .getOrDefault(AppearanceMode.System),
    )
    val mode: StateFlow<AppearanceMode> = _mode.asStateFlow()

    fun set(mode: AppearanceMode) {
        preferences.edit().putString("mode", mode.name).apply()
        _mode.value = mode
    }
}

@HiltViewModel
class AppearanceViewModel @Inject constructor(private val preferences: AppearancePreferences) : ViewModel() {
    val mode: StateFlow<AppearanceMode> = preferences.mode
    fun set(mode: AppearanceMode) = preferences.set(mode)
}

@Composable
fun AppearanceSettingsScreen(
    onBack: () -> Unit,
    viewModel: AppearanceViewModel = androidx.hilt.navigation.compose.hiltViewModel(),
) {
    val colors = RdTheme.colors
    val selected by viewModel.mode.collectAsState()
    Column(Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = stringResource(RdR.string.rd_gorunum), onBack = onBack)
        AppearanceMode.entries.forEach { mode ->
            val title = when (mode) {
                AppearanceMode.System -> stringResource(RdR.string.rd_sistem_ayari)
                AppearanceMode.Light -> stringResource(RdR.string.rd_acik)
                AppearanceMode.Dark -> stringResource(RdR.string.rd_koyu)
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { viewModel.set(mode) }
                    .padding(horizontal = RdSpacing.lg, vertical = RdSpacing.md),
            ) {
                Text(title, style = RdFontStyle.Callout.toTextStyle(), color = colors.onyx, modifier = Modifier.weight(1f))
                if (selected == mode) Icon(Icons.Filled.Check, contentDescription = null, tint = colors.green)
            }
        }
    }
}
