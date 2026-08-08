package com.riskdetectedan.feature.onboarding

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.HealthAndSafety
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/** Port of OBSplashView.swift (2026-08-08 visual pass, Faz C). iOS's real hero is a custom
 * phone-mockup (`OBSplashPhoneFrame`) with two rotated floating "12 Tehlike tespit edildi" /
 * "Kök Neden ve Mevzuat hazırlanıyor" chips over a tiled SVG safety pattern — simplified per this
 * pass's documented policy to a single icon over a soft gradient panel, no device mockup, no
 * floating chips. The bottom sheet structure (rounded-top-corner white panel, progress dots,
 * title/subtitle, primary CTA, "Atla" skip link) IS a faithful port — that part carries the real
 * information, the phone mockup was purely decorative. */
@Composable
fun OBSplashScreen(onNext: () -> Unit, onSkip: () -> Unit) {
    val colors = RdTheme.colors
    Column(modifier = Modifier.fillMaxSize().background(colors.white)) {
        // ---- Hero (simplified from OBSplashHero's phone-mockup + floating chips) ----
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(Brush.linearGradient(listOf(colors.white, colors.cloud, colors.fog), start = Offset(0f, 0f))),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(120.dp)
                    .shadow(elevation = 24.dp, shape = CircleShape, ambientColor = colors.onyx, spotColor = colors.onyx)
                    .clip(CircleShape)
                    .background(colors.white),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.HealthAndSafety,
                    contentDescription = null,
                    tint = colors.onyx,
                    modifier = Modifier.size(60.dp),
                )
            }
        }

        // ---- Bottom sheet (OBSplashBottomSheet — real port) ----
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(elevation = 17.dp, shape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp))
                .clip(RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp))
                .background(colors.white)
                .padding(horizontal = RdSpacing.xl)
                .padding(top = 24.dp, bottom = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            OBSplashProgressDots()

            Spacer(Modifier.height(16.dp))
            Text(
                text = "Profesyonel İSG Asistanı",
                style = RdFontStyle.Title1.toTextStyle(),
                color = colors.onyx,
                textAlign = TextAlign.Center,
            )

            Spacer(Modifier.height(11.dp))
            Text(
                text = "Fotoğraf çek; yapay zekâ tehlikeleri otomatik tespit etsin, raporun anında oluşsun ve tek tıklama ile paylaş.",
                style = RdFontStyle.Subheadline.toTextStyle(),
                color = colors.slate,
                textAlign = TextAlign.Center,
            )

            Spacer(Modifier.height(17.dp))
            RdPrimaryButton(
                text = "Devam Et",
                onClick = onNext,
                style = RdButtonStyle.Onyx,
            )

            TextButton(onClick = onSkip) {
                Text(
                    text = "Atla",
                    style = RdFontStyle.Subheadline.toTextStyle(),
                    color = colors.slate,
                )
            }
        }
    }
}

/** Mirrors OBSplashProgressDots: one filled pill (current step) + 5 dim dots (5 more onboarding
 * steps ahead) — static, matches this pass's "no per-segment animation" policy already used by
 * [com.riskdetectedan.core.designsystem.RdProgress]. */
@Composable
private fun OBSplashProgressDots() {
    val colors = RdTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(width = 20.dp, height = 6.dp)
                .clip(RoundedCornerShape(50))
                .background(colors.onyx),
        )
        repeat(5) {
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(colors.slate.copy(alpha = 0.4f)),
            )
        }
    }
}
