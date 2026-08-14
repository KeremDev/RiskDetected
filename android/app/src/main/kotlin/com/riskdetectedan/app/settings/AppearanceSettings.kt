package com.riskdetectedan.app.settings

import com.riskdetectedan.core.designsystem.R as RdR

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
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
    viewModel: AppearanceViewModel = androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel(),
) {
    val selected by viewModel.mode.collectAsState()
    AppearanceSettingsContent(
        selected = selected,
        onSelect = viewModel::set,
        onBack = onBack,
    )
}

@Composable
internal fun AppearanceSettingsContent(
    selected: AppearanceMode,
    onSelect: (AppearanceMode) -> Unit,
    onBack: () -> Unit,
) {
    val colors = RdTheme.colors
    Column(Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = stringResource(RdR.string.rd_tercihler), onBack = onBack)
        LazyColumn(
            modifier = Modifier.fillMaxSize().selectableGroup(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Column(
                    modifier = Modifier.padding(start = RdSpacing.lg, end = RdSpacing.lg, top = RdSpacing.sm, bottom = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = stringResource(RdR.string.rd_tema).uppercase(),
                        style = RdFontStyle.SectionHeader.toTextStyle(),
                        color = colors.slate,
                    )
                    Text(
                        text = stringResource(RdR.string.rd_tema_aciklama),
                        style = RdFontStyle.Footnote.toTextStyle(),
                        color = colors.slate,
                    )
                }
            }
            items(AppearanceMode.entries.size) { index ->
                val mode = AppearanceMode.entries[index]
                val title = when (mode) {
                    AppearanceMode.System -> stringResource(RdR.string.rd_sistem)
                    AppearanceMode.Light -> stringResource(RdR.string.rd_aydinlik)
                    AppearanceMode.Dark -> stringResource(RdR.string.rd_karanlik)
                }
                val subtitle = when (mode) {
                    AppearanceMode.System -> stringResource(RdR.string.rd_tema_sistem_aciklama)
                    AppearanceMode.Light -> stringResource(RdR.string.rd_tema_aydinlik_aciklama)
                    AppearanceMode.Dark -> stringResource(RdR.string.rd_tema_karanlik_aciklama)
                }
                val icon = when (mode) {
                    AppearanceMode.System -> Icons.Filled.PhoneAndroid
                    AppearanceMode.Light -> Icons.Filled.LightMode
                    AppearanceMode.Dark -> Icons.Filled.DarkMode
                }
                AppearanceOptionRow(
                    icon = icon,
                    title = title,
                    subtitle = subtitle,
                    selected = selected == mode,
                    onClick = { onSelect(mode) },
                    modifier = Modifier.padding(horizontal = RdSpacing.lg),
                )
            }
            item { Spacer(Modifier.size(RdSpacing.lg)) }
        }
    }
}

@Composable
private fun AppearanceOptionRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = RdTheme.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(colors.white)
            .border(
                width = if (selected) 1.5.dp else 1.dp,
                color = if (selected) colors.green.copy(alpha = .55f) else colors.line,
                shape = RoundedCornerShape(16.dp),
            )
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(if (selected) colors.selected else colors.fog),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (selected) Color.White else colors.charcoal,
                modifier = Modifier.size(18.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
            Text(subtitle, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
        }
        Spacer(Modifier.width(10.dp))
        Icon(
            imageVector = if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
            contentDescription = null,
            tint = if (selected) colors.green else colors.slate.copy(alpha = .55f),
            modifier = Modifier.size(20.dp),
        )
    }
}
