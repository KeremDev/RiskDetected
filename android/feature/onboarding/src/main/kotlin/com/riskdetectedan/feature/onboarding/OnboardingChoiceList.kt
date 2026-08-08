package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdCard
import com.riskdetectedan.core.designsystem.RdChipTile
import com.riskdetectedan.core.designsystem.RdFooter
import com.riskdetectedan.core.designsystem.RdHeroTile
import com.riskdetectedan.core.designsystem.RdHeroTint
import com.riskdetectedan.core.designsystem.RdOnboardingSubtitle
import com.riskdetectedan.core.designsystem.RdOnboardingTitle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSelectionCounter
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.RdTopBar

enum class RdPickerLayout { List, Grid }

/**
 * Shared shape for every single/multi-select onboarding step, now matching OBTopBar/OBProgress/
 * OBCard/OBChipTile/OBSelectionCounter/OBFooter's real visual design (2026-08-08 visual pass) —
 * this file used to be a plain `LazyColumn`+`Text`+`Button` stand-in (see git history commit
 * before this one). [layout] picks the picker shape: `List` mirrors OBCard's full-width rows
 * (Certificate/HazardClass/Frequency), `Grid` mirrors OBSectorView's bespoke 2-column chip tiles
 * (Sector — the one screen iOS gives a genuinely different picker shape, not reused elsewhere).
 * Per-item leading icons/subtitles/tints (`itemIcon`/`itemSubtitle`/`itemIconTint`/
 * `itemIconBackground`) are real iOS values read directly from `OBSectorView.swift`'s `s.icon`/
 * `s.sub` (delegates to `AnalysisSector.icon`/`.subtitle`), `OBHazardClassView.swift`'s local
 * `items` tuple array (icon/sub) + `hazardIcon()` helper (permanently severity-tinted,
 * independent of selection — that's why `itemIconTint`/`itemIconBackground` exist as overrides
 * on [RdCard] rather than just always using the selection-dependent onyx/fog default), and
 * `OBCertificateView.swift`'s `helmetItems` tuple's `hatColor` (reused as the icon tint; iOS's
 * actual leading view there is a bespoke Canvas hard-hat-with-letter badge, not an SF Symbol —
 * substituted with a Material icon per this pass's documented simplification policy). SF Symbol
 * names are mapped to their closest Material Icons Extended equivalent, not a literal port
 * (Android has no SF Symbol asset catalog to draw from).
 */
@Composable
fun <T> OnboardingChoiceScreen(
    title: String,
    items: List<T>,
    isSelected: (T) -> Boolean,
    label: (T) -> String,
    onToggle: (T) -> Unit,
    canContinue: Boolean,
    onContinue: () -> Unit,
    subtitle: String? = null,
    continueLabel: String = "Devam",
    multi: Boolean = false,
    layout: RdPickerLayout = RdPickerLayout.List,
    step: Int? = null,
    totalSteps: Int = 4,
    onBack: (() -> Unit)? = null,
    heroTint: RdHeroTint = RdHeroTint.Neutral,
    heroIcon: ImageVector? = null,
    selectionCounterSuffix: String = "seçildi",
    itemIcon: (T) -> ImageVector? = { null },
    itemSubtitle: (T) -> String? = { null },
    itemIconTint: (T) -> Color? = { null },
    itemIconBackground: (T) -> Color? = { null },
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(RdTheme.colors.paper),
    ) {
        if (step != null) {
            RdTopBar(step = step, total = totalSteps, onBack = onBack)
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = RdSpacing.lg),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (heroIcon != null) {
                RdHeroTile(tint = heroTint) {
                    Icon(heroIcon, contentDescription = null, tint = RdTheme.colors.onyx, modifier = Modifier.padding(4.dp))
                }
                Spacer(modifier = Modifier.height(RdSpacing.md))
            }
            RdOnboardingTitle(title)
            if (subtitle != null) {
                Spacer(modifier = Modifier.height(RdSpacing.xxs))
                RdOnboardingSubtitle(subtitle)
            }
        }

        Spacer(modifier = Modifier.height(RdSpacing.md))
        HorizontalDivider(color = RdTheme.colors.line)

        when (layout) {
            RdPickerLayout.List -> LazyColumn(
                modifier = Modifier.weight(1f).padding(horizontal = RdSpacing.lg),
                verticalArrangement = Arrangement.spacedBy(RdSpacing.xs, alignment = Alignment.Top),
                contentPadding = PaddingValues(top = RdSpacing.md, bottom = RdSpacing.md),
            ) {
                items(items) { item ->
                    RdCard(
                        title = label(item),
                        onClick = { onToggle(item) },
                        subtitle = itemSubtitle(item),
                        icon = itemIcon(item),
                        iconTint = itemIconTint(item),
                        iconBackground = itemIconBackground(item),
                        selected = isSelected(item),
                        multi = multi,
                    )
                }
            }
            RdPickerLayout.Grid -> LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                modifier = Modifier.weight(1f).padding(horizontal = RdSpacing.lg),
                horizontalArrangement = Arrangement.spacedBy(RdSpacing.xs),
                verticalArrangement = Arrangement.spacedBy(RdSpacing.xs),
                contentPadding = PaddingValues(top = RdSpacing.md, bottom = RdSpacing.md),
            ) {
                items(items) { item ->
                    RdChipTile(
                        title = label(item),
                        onClick = { onToggle(item) },
                        subtitle = itemSubtitle(item),
                        icon = itemIcon(item),
                        selected = isSelected(item),
                    )
                }
            }
        }

        if (multi) {
            RdSelectionCounter(
                count = items.count(isSelected),
                suffix = selectionCounterSuffix,
                modifier = Modifier.fillMaxWidth().padding(horizontal = RdSpacing.lg),
            )
        }

        RdFooter {
            RdPrimaryButton(
                text = continueLabel,
                onClick = onContinue,
                enabled = canContinue,
                style = RdButtonStyle.Onyx,
            )
        }
    }
}
