package com.riskdetectedan.feature.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Port of OBNotificationPermissionView.swift (2026-08-08 visual pass, Faz E). POST_NOTIFICATIONS
 * request logic (Android 13+ only, no-op + continue below that) is unchanged from before this
 * pass — pure UI layer. iOS's animated bell (custom `OBBellGlyph` Bezier shape + wiggle/ripple
 * `TimelineView` animation) is simplified to a static `NotificationsActive` icon over a soft green
 * radial glow — no custom Path drawing, no wiggle, per this pass's documented policy. Android's
 * pre-existing two-path footer (primary "Bildirimleri Aç" request button + secondary "Ücretsiz
 * devam et" skip-without-prompting text link) is kept as-is — a real, deliberate divergence from
 * iOS's single combined button that predates this visual pass, not something to silently remove
 * here.
 */
@Composable
fun OBNotificationPermissionScreen(onContinue: () -> Unit) {
    val colors = RdTheme.colors
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { _ -> onContinue() }

    Column(
        modifier = Modifier.fillMaxSize().background(colors.white).padding(horizontal = RdSpacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(52.dp))
        Text(
            "Plan ve teklif bilgilerini bildirimlerden takip edebilirsin",
            style = RdFontStyle.Title1.toTextStyle(),
            color = colors.onyx,
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.height(46.dp))
        Box(
            modifier = Modifier
                .size(200.dp)
                .background(
                    Brush.radialGradient(listOf(colors.green.copy(alpha = 0.16f), colors.green.copy(alpha = 0f))),
                    CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.NotificationsActive, contentDescription = null, tint = colors.green, modifier = Modifier.size(84.dp))
        }

        Spacer(Modifier.height(36.dp))
        Text(
            "Plan, teklif ve uygulama hatırlatmaları için bildirimleri aç.",
            style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.Normal),
            color = colors.slate,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 320.dp),
        )

        Spacer(Modifier.height(28.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Box(
                modifier = Modifier.size(20.dp).clip(CircleShape).background(colors.greenSoft),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(11.dp))
            }
            Spacer(Modifier.width(8.dp))
            Text("Bu adımda satın alma yapılmaz", style = RdFontStyle.Callout.toTextStyle(), color = colors.graphite)
        }

        Spacer(Modifier.height(16.dp))
        RdPrimaryButton(
            text = "Bildirimleri Aç",
            onClick = {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    onContinue()
                }
            },
            showArrow = false,
            style = RdButtonStyle.Onyx,
        )

        Spacer(Modifier.height(4.dp))
        TextButton(onClick = onContinue) {
            Text("Ücretsiz devam et", style = RdFontStyle.Callout.toTextStyle(), color = colors.slate)
        }
        Spacer(Modifier.height(16.dp))
    }
}
