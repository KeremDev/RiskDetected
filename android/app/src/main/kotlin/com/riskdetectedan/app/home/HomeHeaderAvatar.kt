package com.riskdetectedan.app.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Real port of `RDAvatar.swift` — gradient circle + initials, tier-colored badge overlay
 * (bottom-trailing) when paid. `RDAvatar.badgeIcon`'s `crown.fill`/`star.fill` mapped to Material
 * `MilitaryTech`/`Star` (no crown glyph in the extended icon set) — same "closest available
 * Material icon" substitution CanvasSheet already uses for its own SF Symbol mappings, not a
 * silent shortcut. Image-avatar path (`app.profile?.avatarURL`) not ported — no avatar-photo
 * upload/display exists anywhere on Android yet, initials-only.
 */
@Composable
fun HomeHeaderAvatar(initials: String, tier: SubscriptionTier, size: Int = 36) {
    val colors = RdTheme.colors
    val sizeDp = size.dp
    Box(modifier = Modifier.size(sizeDp)) {
        Box(
            modifier = Modifier
                .size(sizeDp)
                .clip(CircleShape)
                .background(Color(0xFFDDE5E0))
                .border(1.dp, colors.white.copy(alpha = 0.55f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(initials, style = RdFontStyle.Caption.toTextStyle(), color = colors.white)
        }
        if (tier.isPaid) {
            val badgeColor = if (tier == SubscriptionTier.Pro) colors.green else colors.planPlus
            val badgeIcon = if (tier == SubscriptionTier.Pro) Icons.Filled.Star else Icons.Filled.MilitaryTech
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .size((size * 0.5f).dp)
                    .clip(CircleShape)
                    .background(badgeColor)
                    .border(2.dp, colors.paper, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(badgeIcon, contentDescription = null, tint = colors.white, modifier = Modifier.size((size * 0.24f).dp))
            }
        }
    }
}
