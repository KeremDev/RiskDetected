package com.riskdetectedan.feature.onboarding.nova

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.designsystem.isg.novaPress
import com.riskdetectedan.feature.onboarding.OnboardingNotificationPermissionViewModel
import com.riskdetectedan.feature.onboarding.R

// MARK: - Trial offer

@Composable
internal fun NovaOBTrialScreen(controller: NovaOnboardingController) {
    Column(Modifier.fillMaxSize()
        .background(Brush.verticalGradient(0f to Color(0xFFF6B06A), 0.24f to Color(0xFFF8CFA4), 0.52f to Color(0xFFF3E7DC),
            0.74f to Color(0xFFF1F1EF), 1f to Color(0xFFEDEDEB)))
        .padding(horizontal = 22.dp).padding(top = obPadTop(54f), bottom = obPadBottom(34f))) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { ObCloseButton { controller.go(NovaOBScreen.Push) } }
        // The prototype reserves 400 pt for the absolutely-placed mock; native text runs a touch taller.
        NovaOBTrialMockup(Modifier.padding(top = 6.dp).height(424.dp).offset(x = (-4).dp))
        Column(Modifier.weight(1f).fillMaxWidth().padding(top = 10.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.Bottom)) {
            ObText("İSGADA’yı 7 gün ücretsiz denemenizi istiyoruz", 31f, weight = 800, lineHeight = 1.14f, tracking = -1.1f, align = TextAlign.Center)
            ObText("Tüm özellikler açık, şuan ödeme alınmaz. Deneme bitmeden hatırlatırız.", 14.5f, Modifier.widthIn(max = 296.dp),
                color = NovaOB.muted, lineHeight = 1.45f, align = TextAlign.Center)
            ObPillButton("İncele", showsArrow = true, background = Color(0xFF111111)) { controller.go(NovaOBScreen.TrialHow) }
        }
    }
}

@Composable
private fun ObCloseButton(onClick: () -> Unit) {
    Box(Modifier.shadow(4.dp, CircleShape, ambientColor = Color(0xFF784614).copy(alpha = 0.14f), spotColor = Color(0xFF784614).copy(alpha = 0.14f))
        .size(36.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.72f)).novaPress(onClick = onClick),
        contentAlignment = Alignment.Center) {
        ObIcon("M6 6l12 12|M18 6L6 18", 15f, Color(0xFF2C2320), lineWidth = 2.3f)
    }
}

private val mockTags = listOf("Risk analizi", "Eğitim", "Denetim", "Kontrol listesi", "EKİP takibi", "Ramak kala", "İSG kurulu")

/** The layered "Saha Rutini" app mock behind the trial offer. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun NovaOBTrialMockup(modifier: Modifier) {
    Box(modifier.fillMaxWidth()) {
        val cardShape = RoundedCornerShape(26.dp)
        Column(Modifier.padding(horizontal = 8.dp).fillMaxWidth()
            .shadow(17.dp, cardShape, ambientColor = Color(0xFF965F23).copy(alpha = 0.16f), spotColor = Color(0xFF965F23).copy(alpha = 0.16f))
            .clip(cardShape).background(NovaOB.surface).padding(start = 17.dp, end = 17.dp, top = 18.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ObText("Saha Rutini", 18f, Modifier.weight(1f), weight = 700, tracking = -0.3f)
                Row(Modifier.height(28.dp).clip(CircleShape).background(NovaOB.fill2).padding(horizontal = 11.dp),
                    horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                    ObIcon("M4 20h4l10-10-4-4L4 16z", 12f, NovaOB.muted, lineWidth = 2f)
                    ObText("Düzenle", 12.5f, weight = 600, color = NovaOB.muted)
                }
            }
            Row(Modifier.fillMaxWidth().clip(CircleShape).background(NovaOB.fill2).padding(3.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Box(Modifier.weight(1f).height(31.dp).clip(CircleShape).background(Color(0xFF111111)), contentAlignment = Alignment.Center) {
                    ObText("Bugün", 13f, weight = 700, color = Color.White)
                }
                Box(Modifier.weight(1f).height(31.dp), contentAlignment = Alignment.Center) { ObText("Yaklaşan", 13f, weight = 600, color = NovaOB.muted2) }
            }
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
                .background(Brush.linearGradient(listOf(Color(0xFFF0A44F), Color(0xFFE8853C)))).padding(13.dp),
                horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                Box(Modifier.size(31.dp).clip(RoundedCornerShape(10.dp)).background(Color.White), contentAlignment = Alignment.Center) {
                    ObIcon("M12 2.6l8.4 3.6v5.5c0 4.9-3.4 9.1-8.4 10.7-5-1.6-8.4-5.8-8.4-10.7V6.2z", 17f, Color(0xFFE8853C), lineWidth = 0f, filled = true)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    ObText("Hedefin: saha denetimi", 13.5f, weight = 700, color = Color.White)
                    ObText("Vardiya başında kontrol listesi, risk kaydı ve eksik EKİP takibi tek akışta.", 11f,
                        color = Color.White.copy(alpha = 0.9f), lineHeight = 1.4f)
                }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                mockTags.forEach { tag ->
                    Box(Modifier.height(22.dp).clip(CircleShape).background(Color(0xFFF5EDE6)).padding(horizontal = 10.dp),
                        contentAlignment = Alignment.Center) {
                        ObText(tag, 10.5f, weight = 600, color = Color(0xFF8A6B50))
                    }
                }
            }
        }
        val shiftShape = RoundedCornerShape(18.dp)
        Column(Modifier.offset(y = 270.dp).width(236.dp).rotate(-2.4f)
            .shadow(16.dp, shiftShape, ambientColor = Color(0xFF965F23).copy(alpha = 0.18f), spotColor = Color(0xFF965F23).copy(alpha = 0.18f))
            .clip(shiftShape).background(NovaOB.surface).padding(horizontal = 13.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                ObIcon("circle:12,12,4.6|M12 1.5v3.2M12 19.3v3.2M1.5 12h3.2M19.3 12h3.2M4.6 4.6l2.3 2.3M17.1 17.1l2.3 2.3M19.4 4.6l-2.3 2.3M6.9 17.1l-2.3 2.3",
                    13f, Color(0xFFE8853C), lineWidth = 2f)
                ObText("Sabah vardiyası", 11.5f, weight = 700, color = NovaOB.muted)
            }
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color(0xFFFDF4EC)).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)) {
                ObText("Vardiya başı saha turu", 12f, weight = 700)
                ObText("07:15 · 12 dk", 10f, weight = 600, color = NovaOB.gold)
                ObText("Günün ilk kontrol listesini tamamla.", 10f, color = NovaOB.muted2, lineHeight = 1.4f)
            }
        }
        NovaOBStatusChip("M12 2.5A9.5 9.5 0 1021.5 12A9.5 9.5 0 0012 2.5m-.7 13.4l-3.6-3.6 1.5-1.5 2.1 2.1 4.8-5 1.5 1.5z", NovaOB.ink,
            "Tamamlanan:", "%68", NovaOB.ink, Modifier.align(Alignment.TopEnd).padding(end = 2.dp).offset(y = 298.dp).rotate(3f))
        NovaOBStatusChip("M12 2.5A9.5 9.5 0 1021.5 12A9.5 9.5 0 0012 2.5m1 14.6h-2v-2h2zm0-3.6h-2V7h2z", Color(0xFFC0564B),
            "Kritik:", "3 kayıt", Color(0xFFC0564B), Modifier.align(Alignment.TopEnd).padding(end = 16.dp).offset(y = 346.dp).rotate(-1.6f))
    }
}

@Composable
private fun NovaOBStatusChip(icon: String, iconColor: Color, label: String, value: String, valueColor: Color, modifier: Modifier) {
    val shape = RoundedCornerShape(14.dp)
    Row(modifier.shadow(13.dp, shape, ambientColor = Color(0xFF965F23).copy(alpha = 0.2f), spotColor = Color(0xFF965F23).copy(alpha = 0.2f))
        .clip(shape).background(NovaOB.surface).padding(horizontal = 13.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        ObIcon(icon, 15f, iconColor, lineWidth = 0f, filled = true)
        ObText(label, 12.5f, weight = 700)
        ObText(value, 12.5f, weight = 800, color = valueColor)
    }
}

// MARK: - How the trial works

private class NovaOBTrialStep(val title: String, val desc: String, val done: Boolean, val icon: String)

private const val TRIAL_CHECK = "M12 2.4A9.6 9.6 0 1021.6 12A9.6 9.6 0 0012 2.4m-1.1 14.2l-4.1-4.1 1.7-1.7 2.4 2.4 5.6-5.6 1.7 1.7z"

private val trialSteps = listOf(
    NovaOBTrialStep("Uygulamayı indir", "İSGADA’yı indirip açtın.", true, TRIAL_CHECK),
    NovaOBTrialStep("Deneyimini kişiselleştir", "Kişiselleştirme sorularının tamamını yanıtladın.", true, TRIAL_CHECK),
    NovaOBTrialStep("Bugün: anında erişim", "7 günlük ücretsiz PLUS denemen tüm özelliklerle başlıyor.", false,
        "M12 1.8l8.4 3.6v5.9c0 5-3.5 9.3-8.4 10.9-4.9-1.6-8.4-5.9-8.4-10.9V5.4zm-1 13.9l5.4-5.4-1.6-1.6-3.8 3.8-1.9-1.9-1.6 1.6z"),
    NovaOBTrialStep("5. gün: hatırlatma", "Deneme bitmeden haber veririz; istediğin an iptal edebilirsin.", false,
        "M12 2.4a5.4 5.4 0 00-5.4 5.4c0 4-1 5.4-2.2 6.9-.5.6 0 1.5.8 1.5h13.6c.8 0 1.3-.9.8-1.5-1.2-1.5-2.2-2.9-2.2-6.9A5.4 5.4 0 0012 2.4m-2.6 15.4a2.7 2.7 0 005.2 0z"),
    NovaOBTrialStep("7. gün: deneme sona erer", "İptal etmezsen 2499 TL/yıl üzerinden otomatik yenilenir.İptal edebilirsin.", false,
        "M12 2.3l2.9 6 6.6.9-4.8 4.7 1.1 6.6L12 17.3l-5.8 3.2 1.1-6.6L2.5 9.2l6.6-.9z"),
)

@Composable
internal fun NovaOBTrialHowScreen(controller: NovaOnboardingController) {
    Column(Modifier.fillMaxSize()
        .background(Brush.verticalGradient(0f to Color(0xFFF6C79A), 0.22f to Color(0xFFF8DDC2), 0.46f to Color(0xFFF5EDE4),
            0.7f to Color.White, 1f to Color.White))
        .padding(horizontal = 22.dp).padding(top = obPadTop(54f), bottom = obPadBottom(30f)),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(NovaOB.gold))
                Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(NovaOB.ink.copy(alpha = 0.12f)))
            }
            ObCloseButton { controller.go(NovaOBScreen.Push) }
        }
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.height(30.dp).clip(CircleShape).background(Color(0xFF111111)).padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                ObIcon("M12 2.2l2.9 6 6.6.9-4.8 4.6 1.1 6.6L12 17.2 6.2 20.3l1.1-6.6L2.5 9.1l6.6-.9z", 13f, Color(0xFFF0A44F), lineWidth = 0f, filled = true)
                ObText("7 GÜN ÜCRETSİZ · ŞUAN ÖDEME YOK", 11.5f, weight = 700, color = Color.White, tracking = 0.345f)
            }
            ObText("Ücretsiz deneme nasıl çalışır?", 26f, weight = 800, lineHeight = 1.1f, tracking = -1.2f, align = TextAlign.Center)
            ObText("Bugün tam erişimle başlıyorsun. 7 gün boyunca hiçbir ücret alınmaz.", 15f, Modifier.widthIn(max = 300.dp),
                color = NovaOB.muted, lineHeight = 1.45f, align = TextAlign.Center)
        }
        Column {
            trialSteps.forEachIndexed { index, step -> NovaOBTrialStepRow(index, step, last = index == trialSteps.lastIndex) }
        }
        Spacer(Modifier.weight(1f))
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            ObPillButton("7 günlük ücretsiz denemeyi başlat", fontSize = 17.5f, background = Color(0xFF111111)) { controller.go(NovaOBScreen.Push) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.height(44.dp).novaPress { controller.go(NovaOBScreen.Trial) }.padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    ObIcon("M20 12H5|M11 6l-6 6 6 6", 17f, NovaOB.muted, lineWidth = 2f)
                    ObText("Geri", 15f, color = NovaOB.muted)
                }
                Box(Modifier.size(1.dp, 18.dp).background(NovaOB.ink.copy(alpha = 0.14f)))
                Row(Modifier.height(44.dp).novaPress { controller.go(NovaOBScreen.Push) }.padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    ObText("Şimdilik Ücretsiz Devam Et", 15f, color = Color(0xFF999998), italic = true)
                    ObIcon("M4 12h15|M13 6l6 6-6 6", 17f, NovaOB.gold, lineWidth = 2f)
                }
            }
        }
    }
}

@Composable
private fun NovaOBTrialStepRow(index: Int, step: NovaOBTrialStep, last: Boolean) {
    val current = index == 2
    val dot = when {
        step.done -> Color(0xFFF7DCC0)
        current -> Color(0xFFE8853C)
        else -> NovaOB.surface
    }
    val iconColor = when {
        step.done -> Color(0xFFD08A44)
        current -> Color.White
        else -> Color(0xFFE8853C)
    }
    val shadow = when {
        current -> Color(0xFFC86E28).copy(alpha = 0.32f)
        step.done -> Color.Transparent
        else -> Color(0xFF785028).copy(alpha = 0.12f)
    }
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            val shape = RoundedCornerShape(15.dp)
            Box(Modifier.shadow(if (current) 10.dp else if (step.done) 0.dp else 8.dp, shape, ambientColor = shadow, spotColor = shadow)
                .size(46.dp).clip(shape).background(dot), contentAlignment = Alignment.Center) {
                ObIcon(step.icon, 23f, iconColor, lineWidth = 0f, filled = true)
            }
            if (!last) Box(Modifier.width(3.dp).weight(1f).heightIn(min = 10.dp).clip(CircleShape)
                .background(if (step.done) Color(0xFFF0D9C2) else Color(0xFFF0D6BF)))
        }
        Column(Modifier.weight(1f).padding(bottom = 18.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            ObText(step.title, 18.5f, weight = 800, tracking = -0.4f, color = if (step.done) Color(0xFF9A948E) else NovaOB.ink, strike = step.done)
            ObText(step.desc, 14f, color = if (step.done) Color(0xFFA8A29C) else NovaOB.muted, lineHeight = 1.45f)
        }
    }
}

// MARK: - Push permission

@Composable
internal fun NovaOBPushScreen(controller: NovaOnboardingController, onFinish: () -> Unit) {
    val context = LocalContext.current
    val permissions: OnboardingNotificationPermissionViewModel = hiltViewModel()
    var working by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        permissions.recordPermission(granted, onFinish)
    }
    Column(Modifier.fillMaxSize().background(NovaOB.surface).padding(horizontal = 24.dp)
        .padding(top = obPadTop(78f), bottom = obPadBottom(34f)), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Column(Modifier.weight(1f).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically)) {
            Image(painterResource(R.drawable.nova_ob_notification), null, Modifier.size(214.dp))
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ObText("Bildirimleri anında alın.", 30f, weight = 800, lineHeight = 1.14f, tracking = -1f, align = TextAlign.Center)
                ObText("Raporların, analizlerin, periyodik kontroller ve firma takipleri için bildirim izninizi istiyoruz.", 16f,
                    color = NovaOB.muted, lineHeight = 1.5f, align = TextAlign.Center)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            ObPillButton("Bildirimleri Aç", showsArrow = true) {
                if (working) return@ObPillButton
                working = true
                val granted = Build.VERSION.SDK_INT < 33 ||
                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                if (granted) permissions.recordPermission(true, onFinish) else launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
            Box(Modifier.fillMaxWidth().height(48.dp).novaPress(onClick = onFinish), contentAlignment = Alignment.Center) {
                ObText("Şimdi değil", 15.5f, color = NovaOB.muted)
            }
        }
    }
}
