package com.riskdetectedan.feature.onboarding.nova

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.isg.rememberNovaReduceMotion
import com.riskdetectedan.feature.onboarding.R
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.sin
import kotlin.random.Random

// MARK: - Profile preparation

private val prepBounds = listOf(25, 50, 75, 100)

@Composable
internal fun NovaOBPrepScreen(controller: NovaOnboardingController) {
    val answers = controller.answers
    val labels = listOf(
        "Çalışma tercihlerin düzenlendi.",
        if ("exp" in controller.skipped || (answers.exp == null && !answers.expLess)) "Deneyim bilgisi daha sonra eklenecek."
        else "Deneyim bilgilerin işlendi.",
        if ("assist" in controller.skipped || answers.assist.isEmpty()) "Destek tercihleri daha sonra seçilecek."
        else "Destek tercihlerin düzenlendi.",
        "Profil kartın hazırlandı.",
    )
    Column(Modifier.fillMaxSize().background(NovaOB.surface).padding(horizontal = 24.dp)
        .padding(top = obPadTop(96f), bottom = obPadBottom(40f)),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(36.dp)) {
        ObText("Sana özel profil hazırlanıyor", 27f, Modifier.fillMaxWidth(), weight = 700, lineHeight = 1.2f, tracking = -0.3f,
            align = TextAlign.Center)
        Box(Modifier.size(196.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val width = 10.dp.toPx()
                val inset = width / 2
                val arcSize = Size(size.width - width, size.height - width)
                drawArc(NovaOB.line, 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(width))
                drawArc(NovaOB.ink, -90f, 360f * controller.prepPercent / 100f, false, Offset(inset, inset), arcSize,
                    style = Stroke(width, cap = StrokeCap.Round))
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                ObText("${controller.prepPercent}%", 46f, weight = 700, tracking = -1.5f)
                ObIcon("M7 24c0-8.3 7.6-15 17-15s17 6.7 17 15|M4 24h40", 30f, 20f, NovaOB.line2, 1.8f, viewBoxWidth = 48f, viewBoxHeight = 32f)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            labels.forEachIndexed { index, label -> NovaOBPrepStep(label, controller.prepPercent >= prepBounds[index]) }
        }
        if (controller.prepDone) ObPrimaryButton("Profilimi gör") { controller.toCard() }
        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun NovaOBPrepStep(label: String, done: Boolean) {
    val shape = RoundedCornerShape(16.dp)
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).clip(shape).background(if (done) NovaOB.surface else Color(0xFFF5F5F5))
        .border(1.dp, if (done) NovaOB.line else Color(0xFFE8E8E8), shape).padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(22.dp).clip(CircleShape).background(if (done) NovaOB.ink else NovaOB.surface)
            .border(1.5.dp, if (done) NovaOB.ink else NovaOB.line2, CircleShape), contentAlignment = Alignment.Center) {
            if (done) ObIcon(NovaOB.CHECK, 12f, Color.White, lineWidth = 2.4f, viewBox = 14f)
        }
        ObText(label, 15f, Modifier.weight(1f), color = if (done) NovaOB.ink else NovaOB.muted, lineHeight = 1.3f)
        if (done) ObText("Tamamlandı", 12.5f)
    }
}

// MARK: - Profile card

@Composable
internal fun NovaOBProfileCardScreen(controller: NovaOnboardingController) {
    val reduceMotion = rememberNovaReduceMotion()
    val name = controller.answers.name.trim()
    Box(Modifier.fillMaxSize().background(NovaOB.surface)) {
        // Purely decorative full-height motion: off entirely under Reduce Motion, as on iOS.
        if (!reduceMotion) NovaOBConfettiLayer()
        Column(Modifier.fillMaxSize().padding(horizontal = 24.dp).padding(top = obPadTop(72f), bottom = obPadBottom(34f)),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Spacer(Modifier.weight(1f))
            Image(painterResource(R.drawable.nova_ob_profile_ready), null, Modifier.size(214.dp))
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ObText("Hepsi Tamam,\nSana özel profilini kaydettik.", 31f, weight = 800, lineHeight = 1.14f, tracking = -1f, align = TextAlign.Center)
                ObText(if (name.isEmpty()) "Cevapların için teşekkürler" else "Cevapların için teşekkürler $name", 17.5f,
                    color = NovaOB.muted, lineHeight = 1.45f, align = TextAlign.Center)
            }
            Spacer(Modifier.weight(1f))
            ObPillButton("Devam et", showsArrow = true) {
                controller.saveDraft()
                controller.go(NovaOBScreen.Signup)
            }
        }
    }
}

private class NovaOBConfettiPiece(
    val leftRatio: Float, val width: Float, val height: Float, val round: Boolean, val color: Color,
    val balloon: Boolean, val duration: Float, val delay: Float, val sway: Float,
)

private val confettiColors = listOf(0xFF000000, 0xFF555555, 0xFFE8B733, 0xFFD4453C, 0xFF999999, 0xFFF2E7C9, 0xFF000000)

/** Falling confetti and floating balloons (`isgFall` / `isgFloat` / `isgSway`). */
@Composable
private fun NovaOBConfettiLayer() {
    val pieces = remember {
        List(26) { index ->
            val balloon = index % 6 == 0
            val size = if (balloon) Random.nextDouble(14.0, 22.0).toFloat() else Random.nextDouble(6.0, 11.0).toFloat()
            NovaOBConfettiPiece(
                leftRatio = Random.nextDouble(0.02, 0.94).toFloat(), width = size,
                height = if (balloon) size * 1.25f else Random.nextDouble(9.0, 16.0).toFloat(),
                round = balloon || index % 3 != 0, color = Color(confettiColors[index % confettiColors.size]), balloon = balloon,
                duration = Random.nextDouble(3.4, 6.2).toFloat(), delay = Random.nextDouble(0.0, 4.0).toFloat(),
                sway = Random.nextDouble(1.8, 3.4).toFloat(),
            )
        }
    }
    var now by remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) { while (true) withFrameMillis { now = it } }
    Canvas(Modifier.fillMaxSize()) {
        val seconds = now / 1000f
        pieces.forEach { piece ->
            val cycle = ((seconds - piece.delay) / piece.duration) % 1f
            val progress = if (cycle < 0) cycle + 1 else cycle
            val travel = size.height + 160.dp.toPx()
            val swayPhase = sin(seconds / piece.sway * PI.toFloat())
            val alpha = when {
                progress < 0.08f -> progress / 0.08f
                progress >= 0.92f -> max(0f, (1 - progress) / 0.08f)
                else -> 0.9f
            }
            val w = piece.width.dp.toPx()
            val h = piece.height.dp.toPx()
            translate(size.width * piece.leftRatio + swayPhase * 16.dp.toPx(), -80.dp.toPx() + progress * travel) {
                rotate(if (piece.balloon) 0f else progress * 680f, Offset(w / 2, h / 2)) {
                    drawRoundRect(piece.color, size = Size(w, h), alpha = alpha,
                        cornerRadius = CornerRadius(if (piece.round) w / 2 else 2.dp.toPx()))
                }
            }
        }
    }
}
