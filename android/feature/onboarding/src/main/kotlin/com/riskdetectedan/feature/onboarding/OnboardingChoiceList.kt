package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.RdSpacing

/** Shared shape for every single/multi-select onboarding step — no iOS-parity card/animation
 * styling, just a functional list + continue button, matching this port's established
 * low-fidelity-but-real pattern (see AnalysisScreen's sector picker). */
@Composable
fun <T> OnboardingChoiceScreen(
    title: String,
    subtitle: String? = null,
    items: List<T>,
    isSelected: (T) -> Boolean,
    label: (T) -> String,
    onToggle: (T) -> Unit,
    canContinue: Boolean,
    onContinue: () -> Unit,
    continueLabel: String = "Devam",
) {
    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text(title)
        if (subtitle != null) Text(subtitle)
        LazyColumn(modifier = Modifier.padding(top = RdSpacing.sm).weight(1f)) {
            items(items) { item ->
                val selected = isSelected(item)
                ListItem(
                    headlineContent = { Text(if (selected) "✓ ${label(item)}" else label(item)) },
                    modifier = Modifier.clickable { onToggle(item) },
                )
            }
        }
        Button(
            onClick = onContinue,
            enabled = canContinue,
            modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.sm),
        ) {
            Text(continueLabel)
        }
    }
}
