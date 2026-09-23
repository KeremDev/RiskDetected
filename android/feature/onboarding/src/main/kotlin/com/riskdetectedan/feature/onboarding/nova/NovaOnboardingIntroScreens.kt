package com.riskdetectedan.feature.onboarding.nova

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Text
import com.riskdetectedan.core.designsystem.isg.novaPress
import com.riskdetectedan.core.designsystem.isg.rememberNovaReduceMotion
import com.riskdetectedan.feature.onboarding.R
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// MARK: - Splash

/**
 * The mascot zooms out of the screen centre into its resting spot while the wordmark fades in
 * underneath — the prototype's `isgMascotZoom` + `isgLogoReveal` pair.
 */
@Composable
internal fun NovaOBSplashScreen(controller: NovaOnboardingController) {
    val reduceMotion = rememberNovaReduceMotion()
    val zoom = remember { Animatable(1f) }
    val mascotAlpha = remember { Animatable(0f) }
    val logoAlpha = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        mascotAlpha.animateTo(1f, tween(240, easing = LinearEasing))
        delay(1_260)
        // The mascot fills most of the screen at this point; Reduce Motion snaps it into place.
        launch {
            if (reduceMotion) zoom.snapTo(0f) else zoom.animateTo(0f, tween(1_260, easing = CubicBezierEasing(0.24f, 0.9f, 0.2f, 1f)))
        }
        delay(1_080)
        launch { logoAlpha.animateTo(1f, tween(300, easing = LinearEasing)) }
        delay(180)
        mascotAlpha.animateTo(0f, tween(240, easing = LinearEasing))
        // Hold on the wordmark before handing over to the intro.
        delay(2_000)
        controller.go(NovaOBScreen.Intro1)
    }
    Box(Modifier.fillMaxSize().background(NovaOB.surface), contentAlignment = Alignment.Center) {
        Image(painterResource(R.drawable.nova_ob_logo), null, Modifier.width(220.dp).alpha(logoAlpha.value))
        Image(painterResource(R.drawable.nova_ob_mascot), null, Modifier
            .offset(x = (44.55f * (1 - zoom.value)).dp, y = (8.05f * (1 - zoom.value)).dp)
            .size(27.9.dp, 26.7.dp)
            .graphicsLayer {
                val factor = 1f + 11.5f * zoom.value
                scaleX = factor; scaleY = factor
                alpha = mascotAlpha.value
            })
    }
}

// MARK: - Intro 1–3

private data class NovaOBIntroSpec(val background: Color, val title: String, val image: Int, val body: String)

private val introSpecs = listOf(
    NovaOBIntroSpec(NovaOB.intro1Bg, "Sana Özel \nİSG", R.drawable.nova_ob_intro1,
        "Firmalarını, risk analizlerini, eğitimlerini ve günlük işlerini İSGADA ile tek bir çalışma alanında topla; her şeyi ihtiyaçlarına göre sen şekillendir."),
    NovaOBIntroSpec(NovaOB.intro2Bg, "Net ve Kolay\nTakip", R.drawable.nova_ob_intro2,
        "Risk analizlerini, eğitimlerini ve kontrol listelerini dağınık tablolar yerine tek bir düzende takip et; neyin ne zaman yapılacağını her an net şekilde gör."),
    NovaOBIntroSpec(NovaOB.intro3Bg, "Senin\nÖnceliğin", R.drawable.nova_ob_intro3,
        "Birkaç kısa soruyla çalışma alanını, kontrol listelerini ve asistan desteğini kendi deneyimine ve önceliklerine göre baştan kurgulayalım."),
)

@Composable
internal fun NovaOBIntroScreen(controller: NovaOnboardingController, page: Int, onLogin: () -> Unit) {
    val spec = introSpecs[page]
    Column(Modifier.fillMaxSize().background(spec.background).padding(horizontal = 24.dp)
        .padding(top = obPadTop(78f), bottom = obPadBottom(40f))) {
        Row(Modifier.fillMaxWidth().padding(bottom = 26.dp), verticalAlignment = Alignment.CenterVertically) {
            ObDots(page)
            Spacer(Modifier.weight(1f))
            if (page == 0) ObText("Tanıtımı geç", 14f, Modifier.novaPress(onClick = onLogin).padding(horizontal = 6.dp, vertical = 8.dp),
                color = NovaOB.slate)
        }
        Column(Modifier.weight(1f).fillMaxWidth()) {
            ObText(spec.title, 53f, Modifier.fillMaxWidth(), weight = 800, color = Color(0xFF030303), lineHeight = 1.06f, tracking = -1.8f)
            Spacer(Modifier.weight(1f))
            Image(painterResource(spec.image), null, Modifier.size(280.dp).align(Alignment.CenterHorizontally))
            Spacer(Modifier.weight(1f))
            ObText(spec.body, 16.5f, Modifier.fillMaxWidth(), color = NovaOB.inkSoft, lineHeight = 1.5f)
        }
        Row(Modifier.fillMaxWidth().padding(top = 34.dp), horizontalArrangement = Arrangement.spacedBy(20.dp),
            verticalAlignment = Alignment.CenterVertically) {
            if (page == 2) {
                ObPillButton("Devam Et", height = 57f, fontSize = 16.5f, fixedWidth = 203f) { controller.go(NovaOBScreen.Social) }
                Spacer(Modifier.weight(1f))
                ObText("Yanıtlarını\ndaha sonra değiştirebilirsin.", 13f, color = NovaOB.slate, lineHeight = 1.45f, align = TextAlign.End)
            } else {
                ObPillButton("Devam et", height = 60f, fontSize = 17f, horizontalPadding = 40f) {
                    controller.go(if (page == 0) NovaOBScreen.Intro2 else NovaOBScreen.Intro3)
                }
                Spacer(Modifier.weight(1f))
                if (page == 0) {
                    val regular = obStyle(13.5f, color = NovaOB.slate, lineHeight = 1.45f)
                    val bold = obStyle(13.5f, 700)
                    Text(buildAnnotatedString {
                        withStyle(SpanStyle(fontFamily = regular.fontFamily, fontSize = regular.fontSize, color = NovaOB.slate)) { append("Hesabın var mı?\n") }
                        withStyle(SpanStyle(fontFamily = bold.fontFamily, fontWeight = bold.fontWeight, fontSize = bold.fontSize, color = NovaOB.ink)) { append("Giriş yap") }
                    }, Modifier.novaPress(onClick = onLogin), style = regular, textAlign = TextAlign.End)
                }
            }
        }
    }
}

// MARK: - Social proof

private data class NovaOBReview(val title: String, val body: String, val name: String, val role: String, val initials: String)

private val reviews = listOf(
    NovaOBReview("Saha denetimi artık dakikalar sürüyor",
        "Eskiden Excel’de kaybolan kontrol listelerini telefondan doldurup anında rapora çeviriyorum.", "Mert Kaya", "A Sınıfı İSG Uzmanı", "MK"),
    NovaOBReview("Eğitim takibi kendiliğinden işliyor",
        "Süresi dolan eğitimleri İSGADA hatırlatıyor; 14 firmada tek bir gecikme yaşamadım.", "Elif Yıldırım", "OSGB Koordinatörü", "EY"),
    NovaOBReview("Risk analizi şablonları tam yerinde",
        "Sektöre göre gelen maddeler sayesinde yeni bir analiz hazırlamak yarım güne değil bir saate indi.", "Serkan Demir", "B Sınıfı İSG Uzmanı", "SD"),
    NovaOBReview("Denetime hazır olmak rahatlatıcı",
        "Bakanlık denetiminde istenen tüm kayıtlar tek ekrandaydı; hiçbir dosya aramadım.", "Ayşe Tunç", "İSG Müdürü", "AT"),
    NovaOBReview("Ekipteki herkes aynı sayfada",
        "Görev atadığımda sahadaki teknisyen bildirim alıyor, işin durumunu canlı görüyorum.", "Burak Şen", "İş Güvenliği Şefi", "BŞ"),
)

@Composable
internal fun NovaOBSocialProofScreen(controller: NovaOnboardingController, onLogin: () -> Unit) {
    Box(Modifier.fillMaxSize().background(NovaOB.socialBg)) {
        Column(Modifier.fillMaxSize().padding(top = obPadTop(78f), bottom = obPadBottom(40f))) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 26.dp), verticalAlignment = Alignment.CenterVertically) {
                ObDots(3)
                Spacer(Modifier.weight(1f))
                ObText("Atla", 14f, Modifier.novaPress { controller.skipModal = true }.padding(horizontal = 6.dp, vertical = 8.dp),
                    weight = 600, color = NovaOB.slate)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                Column(Modifier.padding(horizontal = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Row(Modifier.height(34.dp).clip(CircleShape).background(NovaOB.ink).padding(start = 5.dp, end = 14.dp),
                        horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(24.dp).clip(CircleShape).background(NovaOB.intro3Bg), contentAlignment = Alignment.Center) {
                            ObText("★", 11f, weight = 800)
                        }
                        ObText("4000+ İş Güvenliği Uzmanının Tercihi", 12f, weight = 700, color = Color.White, tracking = 0.24f)
                    }
                    ObText("Sahada\nKanıtlanmış", 44f, weight = 800, lineHeight = 1.06f, tracking = -1.6f)
                }
                NovaOBAvatars()
                NovaOBMarquee(Modifier.weight(1f).heightIn(min = 200.dp).fillMaxWidth())
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 26.dp), horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalAlignment = Alignment.CenterVertically) {
                ObPillButton("Başlayalım", height = 57f, fontSize = 16.5f, fixedWidth = 203f) { controller.startQuestions() }
                Spacer(Modifier.weight(1f))
                ObText("Kurulum\n2 dakika sürer.", 13f, color = NovaOB.slate, lineHeight = 1.45f, align = TextAlign.End)
            }
        }
        if (controller.skipModal) {
            NovaOBSkipModal(onContinue = { controller.skipModal = false }, onSkip = { controller.skipModal = false; onLogin() })
        }
    }
}

@Composable
private fun NovaOBAvatars() {
    Row(Modifier.padding(horizontal = 24.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.height(74.dp), contentAlignment = Alignment.CenterStart) {
            Row(Modifier.offset(x = 34.dp, y = (-2).dp).blur(2.4.dp).alpha(0.55f), horizontalArrangement = Arrangement.spacedBy((-12).dp)) {
                listOf(0xFF5C7F88, 0xFF9DB0A4, 0xFFC89B7B, 0xFF7E8AA0).forEach { color ->
                    Box(Modifier.size(44.dp).clip(CircleShape).background(Color(color)).border(3.dp, NovaOB.socialBg, CircleShape))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy((-14).dp)) {
                listOf("MK" to 0xFF3E6670, "EY" to 0xFF8C5A3C, "SD" to 0xFF4F6B4A, "AT" to 0xFF6B5E8C, "4K+" to 0xFF000000).forEach { (text, color) ->
                    Box(Modifier.shadow(6.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.14f), spotColor = Color.Black.copy(alpha = 0.14f))
                        .size(46.dp).clip(CircleShape).background(Color(color)).border(3.dp, Color.White, CircleShape),
                        contentAlignment = Alignment.Center) {
                        ObText(text, if (text == "4K+") 13f else 14f, weight = if (text == "4K+") 800 else 700, color = Color.White)
                    }
                }
            }
        }
        ObText("Uzmanlar\nİSGADA kullanıyor", 13f, weight = 500, color = NovaOB.inkSoft, lineHeight = 1.4f)
    }
}

/** Continuously scrolling review rail (`isgMarquee`, 34 s linear). Reduce Motion holds it still. */
@Composable
private fun NovaOBMarquee(modifier: Modifier) {
    val reduceMotion = rememberNovaReduceMotion()
    val singleWidth = reviews.size * 264f
    val shift = remember { Animatable(0f) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) return@LaunchedEffect
        while (true) {
            shift.snapTo(0f)
            shift.animateTo(-singleWidth, tween(34_000, easing = LinearEasing))
        }
    }
    Box(modifier.clipToBounds(), contentAlignment = Alignment.BottomStart) {
        Row(Modifier.wrapContentWidth(Alignment.Start, unbounded = true).padding(start = 24.dp).offset(x = shift.value.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            (reviews + reviews).forEach { NovaOBReviewCard(it) }
        }
    }
}

@Composable
private fun NovaOBReviewCard(review: NovaOBReview) {
    val shape = RoundedCornerShape(22.dp)
    Column(Modifier.padding(bottom = 12.dp)
        .shadow(11.dp, shape, ambientColor = Color(0xFF142832).copy(alpha = 0.08f), spotColor = Color(0xFF142832).copy(alpha = 0.08f))
        .size(252.dp, 220.dp).clip(shape).background(NovaOB.surface).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp)) {
        ObText("★★★★★", 12f, color = NovaOB.gold, tracking = 1.68f)
        ObText(review.title, 15.5f, weight = 700, lineHeight = 1.25f, tracking = -0.2f)
        ObText(review.body, 13f, color = NovaOB.slate, lineHeight = 1.45f)
        Row(Modifier.padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(30.dp).clip(CircleShape).background(Color(0xFFEDF3F2)), contentAlignment = Alignment.Center) {
                ObText(review.initials, 11.5f, weight = 700, color = Color(0xFF3E6670))
            }
            Column {
                ObText(review.name, 12.5f, weight = 700)
                ObText(review.role, 11f, color = NovaOB.slate)
            }
        }
    }
}

/** "Bu adımı atlamak istiyor musun?" — dimmed scrim plus a centred card. */
@Composable
internal fun NovaOBSkipModal(onContinue: () -> Unit, onSkip: () -> Unit) {
    val reduceMotion = rememberNovaReduceMotion()
    val shown = remember { Animatable(0f) }
    LaunchedEffect(Unit) { shown.animateTo(1f, tween(300, easing = CubicBezierEasing(0.2f, 0.85f, 0.25f, 1f))) }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.35f)).background(Color(0xFF0E161C).copy(alpha = 0.42f))
            .clickable(remember { MutableInteractionSource() }, null, onClick = onContinue))
        val shape = RoundedCornerShape(26.dp)
        Column(Modifier.padding(horizontal = 24.dp).widthIn(max = 320.dp)
            .scale(if (reduceMotion) 1f else 0.94f + 0.06f * shown.value).alpha(shown.value)
            .shadow(30.dp, shape, ambientColor = Color(0xFF0E161C).copy(alpha = 0.28f), spotColor = Color(0xFF0E161C).copy(alpha = 0.28f))
            .clip(shape).background(NovaOB.surface).padding(22.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Image(painterResource(R.drawable.nova_ob_skip_warning), null, Modifier.size(168.dp).padding(top = 0.dp).offset(y = (-6).dp))
            ObText("Bu adımı atlamak istiyor musun?", 21f, weight = 800, lineHeight = 1.2f, tracking = -0.4f, align = TextAlign.Center)
            ObText("Soruları yanıtlamazsan sana özel risk analizi önerileri, eğitim takvimi ve hatırlatmaları hazırlayamayız. Uygulama içinde her şeyi tek tek kendin kurman gerekir.",
                14.5f, color = NovaOB.slate, lineHeight = 1.5f, align = TextAlign.Center)
            Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                Row(Modifier.fillMaxWidth().height(54.dp).clip(CircleShape).background(NovaOB.ink).novaPress(onClick = onContinue),
                    horizontalArrangement = Arrangement.spacedBy(9.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                    ObIcon("circle:12,12,9.2|M8.4 14.2c.8 1.3 2.1 2 3.6 2s2.8-.7 3.6-2|M9 9.6h.01|M15 9.6h.01", 19f, Color.White, lineWidth = 1.9f)
                    ObText("Devam et", 16.5f, weight = 700, color = Color.White)
                }
                Row(Modifier.fillMaxWidth().height(48.dp).novaPress(onClick = onSkip),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                    ObIcon("circle:12,12,9.2|M8.4 16c.8-1.3 2.1-2 3.6-2s2.8.7 3.6 2|M9 9.6h.01|M15 9.6h.01", 17f, Color(0xFF5A6A6E), lineWidth = 1.9f)
                    ObText("Yine de atla", 15f, weight = 600, color = NovaOB.slate)
                }
            }
        }
    }
}
