package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Port of OBTrialInviteView.swift (2026-08-08 visual pass, Faz E). Real RevenueCat pricing not
 * shown here either way (matches this screen's pre-existing scope note — same gap as the paywall
 * step). The 3-phone auto-swapping deck (continuous scale/rotate/offset loop every 2.4s) is
 * simplified to one static phone bezel showing the same fallback preview content (mini risk rows
 * + "Rapor hazır") — the deck's motion is decorative, the screen content inside it is real and
 * kept. Footer links (Gizlilik Politikası/Geri Yükle/Şartlar) are static, non-interactive text —
 * same policy as the Auth screen's legal notice; a real restore-purchases call already exists on
 * the post-onboarding Paywall screen (feature #20), wiring it here too is a separate, deliberate
 * follow-up, not an oversight of this pass.
 */
@Composable
fun OBTrialInviteScreen(onContinue: () -> Unit) {
    val colors = RdTheme.colors
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.radialGradient(
                    colors = listOf(colors.green.copy(alpha = 0.10f), colors.paper),
                    center = Offset(0.5f, 0f),
                    radius = 900f,
                ),
            ),
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(32.dp))

            Text(
                buildAnnotatedTitle(colors.onyx, colors.green),
                style = RdFontStyle.Title1.toTextStyle(),
                textAlign = TextAlign.Center,
            )
            Text("birlikte seçelim", style = RdFontStyle.Title1.toTextStyle(), color = colors.onyx, textAlign = TextAlign.Center)

            Spacer(Modifier.height(24.dp))
            PhonePreview()

            Spacer(Modifier.height(28.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = colors.onyx, modifier = Modifier.size(15.dp))
                Spacer(Modifier.width(8.dp))
                Text(
                    "Fiyat ve uygun teklifler Google Play'de gösterilir",
                    style = RdFontStyle.Callout.toTextStyle(),
                    color = colors.onyx,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Spacer(Modifier.height(14.dp))
            RdPrimaryButton(text = "Plan seçeneklerini gör", onClick = onContinue, style = RdButtonStyle.Onyx)

            Spacer(Modifier.height(10.dp))
            Text("Taahhüt yok, istediğin zaman iptal.", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)

            Spacer(Modifier.height(14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                listOf("Gizlilik Politikası", "Geri Yükle", "Şartlar").forEach { label ->
                    Text(label, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

private fun buildAnnotatedTitle(onyx: Color, green: Color) = buildAnnotatedString {
    withStyle(SpanStyle(color = onyx)) { append("Sana uygun ") }
    withStyle(SpanStyle(color = green)) { append("planı") }
}

@Composable
private fun PhonePreview() {
    Box(
        modifier = Modifier
            .width(210.dp)
            .height(420.dp)
            .clip(RoundedCornerShape(38.dp))
            .background(Color(0xFF16191A)),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .width(190.dp)
                .height(400.dp)
                .clip(RoundedCornerShape(30.dp))
                .background(Color(0xFF0B0D0E)),
        ) {
            Column(
                modifier = Modifier.fillMaxSize().padding(vertical = 24.dp, horizontal = 14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(Icons.Filled.Shield, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
                Spacer(Modifier.weight(1f))
                MiniRiskRow(Color(0xFFB42318), "Yüksekte çalışma", "KRİTİK")
                Spacer(Modifier.height(8.dp))
                MiniRiskRow(Color(0xFFC76A00), "KKD eksikliği", "YÜKSEK")
                Spacer(Modifier.height(8.dp))
                MiniRiskRow(Color(0xFFD4A106), "Aydınlatma", "ORTA")
                Spacer(Modifier.weight(1f))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Verified, contentDescription = null, tint = Color(0xFF00B82E), modifier = Modifier.size(15.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Rapor hazır", style = RdFontStyle.Footnote.toTextStyle().copy(fontSize = 12.sp), color = Color(0xFF00B82E))
                }
            }
        }
        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 10.dp)
                .size(width = 76.dp, height = 20.dp)
                .clip(RoundedCornerShape(50))
                .background(Color.Black),
        )
    }
}

@Composable
private fun MiniRiskRow(dotColor: Color, label: String, badge: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color.White.copy(alpha = 0.04f))
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(dotColor))
        Spacer(Modifier.width(10.dp))
        Text(label, style = RdFontStyle.Caption.toTextStyle(), color = Color.White, modifier = Modifier.weight(1f))
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .background(dotColor.copy(alpha = 0.18f))
                .padding(horizontal = 6.dp, vertical = 2.dp),
        ) {
            Text(badge, style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 9.sp), color = dotColor, fontWeight = FontWeight.Bold)
        }
    }
}
