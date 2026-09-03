package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Port of OBNotificationPermissionView.swift (2026-08-08 visual pass, Faz E). POST_NOTIFICATIONS
 * request logic (Android 13+ only, no-op + continue below that) now also persists the server-side
 * master preference when permission is granted, matching iOS's onboarding flow. iOS's animated bell
 * (custom `OBBellGlyph` Bezier shape + wiggle/ripple
 * `TimelineView` animation) is a static `NotificationsActive` icon (no custom Path drawing — the
 * Bezier bell shape itself isn't ported) but the wiggle+ripple motion itself now IS real
 * (2026-08-09 animation pass): the bell rotates in a periodic keyframe wiggle (rest, then a
 * quick 3-shake burst, matching a real notification-bell alert cadence rather than a continuous
 * back-and-forth that would feel spammy over an onboarding screen users sit on for seconds), and
 * the radial glow behind it breathes (scale) in its own slower loop — same intent as iOS's
 * ripple, simpler mechanism (scale, not an expanding stroked ring).
 * The footer uses the same single "Ücretsiz devam et" action as iOS: that action requests the
 * system permission once, records a granted choice, and advances regardless of the user's
 * decision. There is no second permission-bypass action, so the onboarding order and prompt timing
 * stay identical.
 */
@Composable
fun OBNotificationPermissionScreen(
    onContinue: () -> Unit,
    viewModel: OnboardingNotificationPermissionViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val context = LocalContext.current

    fun finish(granted: Boolean) {
        viewModel.recordPermission(granted = granted, onComplete = onContinue)
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> finish(granted) }

    val infiniteTransition = rememberInfiniteTransition(label = "bell")
    // 3-shake wiggle burst every 2.6s, rest of the cycle at 0° — a periodic alert cadence, not a
    // continuous back-and-forth (see doc comment above for why).
    val wiggle by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 0f,
        animationSpec = infiniteRepeatable(
            animation = keyframes {
                durationMillis = 2600
                0f at 0
                0f at 1600 using LinearEasing
                -10f at 1700
                10f at 1800
                -8f at 1900
                8f at 2000
                0f at 2100
                0f at 2600
            },
            repeatMode = RepeatMode.Restart,
        ),
        label = "wiggle",
    )
    val glowScale by infiniteTransition.animateFloat(
        initialValue = 0.94f,
        targetValue = 1.04f,
        animationSpec = infiniteRepeatable(
            animation = tween(1400, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glow",
    )

    Column(
        modifier = Modifier.fillMaxSize().background(colors.white).padding(horizontal = RdSpacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(52.dp))
        Text(
            stringResource(RdR.string.rd_bildirim_plan_teklif_baslik),
            style = RdFontStyle.Title1.toTextStyle(),
            color = colors.onyx,
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.height(38.dp))
        Box(
            modifier = Modifier
                .size(238.dp)
                .scale(glowScale)
                .background(
                    Brush.radialGradient(listOf(colors.green.copy(alpha = 0.16f), colors.green.copy(alpha = 0f))),
                    CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.NotificationsActive,
                contentDescription = null,
                tint = colors.green,
                modifier = Modifier.size(118.dp).rotate(wiggle),
            )
        }

        Spacer(Modifier.height(36.dp))
        Text(
            stringResource(RdR.string.rd_bildirim_plan_teklif_aciklama),
            style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.Normal),
            color = colors.slate,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 320.dp),
        )

        Spacer(Modifier.weight(1f))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Box(
                modifier = Modifier.size(20.dp).clip(CircleShape).background(colors.greenSoft),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(11.dp))
            }
            Spacer(Modifier.width(8.dp))
            Text(stringResource(RdR.string.rd_bu_adimda_satin_alma_yapilmaz), style = RdFontStyle.Callout.toTextStyle(), color = colors.graphite)
        }

        Spacer(Modifier.height(16.dp))
        RdPrimaryButton(
            text = stringResource(RdR.string.rd_bildirimleri_ac),
            onClick = {
                val osPermissionGranted = NotificationManagerCompat.from(context).areNotificationsEnabled() &&
                    (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                        PackageManager.PERMISSION_GRANTED)
                if (osPermissionGranted) {
                    // The permission may already have been granted in system settings. Still run
                    // the persistence path so the server row is created during onboarding.
                    finish(granted = true)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    // Below Android 13 there is no runtime prompt. The system setting is disabled,
                    // so continue without creating an enabled preference row.
                    finish(granted = false)
                }
            },
            showArrow = false,
            style = RdButtonStyle.Onyx,
        )
        Spacer(Modifier.height(12.dp))
    }
}
