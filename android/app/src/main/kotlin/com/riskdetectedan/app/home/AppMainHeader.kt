package com.riskdetectedan.app.home

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.riskdetectedan.app.R
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.designsystem.R as RdR
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/** Shared Android port of iOS `RDHeaderLogoButton + RDHeaderAccountCTA`. */
@Composable
fun AppMainHeader(
    profile: UserProfile?,
    onLogo: () -> Unit,
    onProfile: () -> Unit,
    onUpgradeTier: (SubscriptionTier) -> Unit,
    horizontalPadding: Dp = 20.dp,
    topPadding: Dp = 8.dp,
    bottomPadding: Dp = 8.dp,
) {
    val colors = RdTheme.colors
    val currentTier = profile?.tier ?: SubscriptionTier.Free
    val targetTier = if (currentTier == SubscriptionTier.Plus) SubscriptionTier.Pro else SubscriptionTier.Plus
    val accent = if (targetTier == SubscriptionTier.Pro) colors.green else colors.planPlus
    val accentDark = if (targetTier == SubscriptionTier.Pro) colors.greenDark else colors.planPlusDark

    Row(
        modifier = Modifier.fillMaxWidth().padding(
            start = horizontalPadding,
            end = horizontalPadding,
            top = topPadding,
            bottom = bottomPadding,
        ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painter = painterResource(R.drawable.rd_logo),
            contentDescription = stringResource(RdR.string.rd_riskdetected),
            contentScale = ContentScale.FillHeight,
            // iOS RDLogo switches the whole wordmark to a white template in dark mode. The
            // source PNG contains a black wordmark, so rendering it unchanged makes the brand
            // disappear on Android's dark paper surface.
            colorFilter = if (RdTheme.isDark) ColorFilter.tint(Color.White) else null,
            modifier = Modifier.height(34.dp).clickable(onClick = onLogo),
            alignment = Alignment.CenterStart,
        )
        Spacer(Modifier.weight(1f))
        if (currentTier != SubscriptionTier.Pro) {
            Row(
                modifier = Modifier
                    .shadow(
                        elevation = 8.dp,
                        shape = RoundedCornerShape(7.dp),
                        ambientColor = accent.copy(alpha = 0.24f),
                        spotColor = accent.copy(alpha = 0.24f),
                    )
                    .clip(RoundedCornerShape(7.dp))
                    .background(Brush.linearGradient(listOf(accent, accentDark)))
                    .clickable { onUpgradeTier(targetTier) }
                    .padding(horizontal = RdSpacing.sm)
                    .height(24.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.ArrowCircleUp, contentDescription = null, tint = colors.white, modifier = Modifier.size(12.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(RdR.string.rd_yukselt), style = RdFontStyle.Caption.toTextStyle(), color = colors.white)
            }
            Spacer(Modifier.width(RdSpacing.sm))
        }
        androidx.compose.foundation.layout.Box(modifier = Modifier.clickable(onClick = onProfile)) {
            HomeHeaderAvatar(
                initials = profile?.displayInitials ?: "—",
                tier = currentTier,
                avatarPath = profile?.avatarUrl,
            )
        }
    }
}
