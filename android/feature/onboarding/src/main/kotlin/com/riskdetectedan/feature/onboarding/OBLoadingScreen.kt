package com.riskdetectedan.feature.onboarding

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.R as RdR
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import kotlinx.coroutines.delay

/**
 * Android counterpart of iOS `OBLoadingView`: a real 15-second, continuously progressing
 * personalisation stage with the same three thirds, completion hand-off and field-professional
 * testimonial carousel. The callback fires only after 100% has been visible long enough to be
 * perceived, so navigation never cuts the ring off at 99%.
 */
@Composable
fun OBLoadingScreen(
    onFinished: () -> Unit,
    primarySectorLabel: String? = null,
    hazardsLabel: String? = null,
    certificateLabel: String? = null,
) {
    val colors = RdTheme.colors
    val compact = LocalConfiguration.current.screenHeightDp < 740
    val resolvedSectorLabel = primarySectorLabel ?: stringResource(RdR.string.rd_sector_construction)
    val resolvedHazardsLabel = hazardsLabel ?: stringResource(RdR.string.rd_hazard_critical)
    val resolvedCertificateLabel = certificateLabel ?: stringResource(RdR.string.rd_cert_a)
    val preparingTitle = stringResource(RdR.string.rd_kurulum_hazirlaniyor)
    val readyTitle = stringResource(RdR.string.rd_plan_hazir_nokta)
    var title by remember { mutableStateOf(preparingTitle) }
    val progress = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        progress.animateTo(1f, animationSpec = tween(durationMillis = 15_000, easing = LinearEasing))
        title = readyTitle
        delay(650)
        onFinished()
    }

    Box(Modifier.fillMaxSize().background(colors.paper), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            LoadingProgress(progress.value, compact)

            Spacer(Modifier.height(if (compact) 18.dp else 26.dp))
            Text(
                title,
                style = RdFontStyle.Title3.toTextStyle(),
                color = colors.onyx,
                textAlign = TextAlign.Center,
            )

            Spacer(Modifier.height(if (compact) 14.dp else 20.dp))
            Column(
                verticalArrangement = Arrangement.spacedBy(if (compact) 8.dp else 10.dp),
                modifier = Modifier.widthIn(max = 352.dp),
            ) {
                LoadingStepRow(
                    status = stepStatus(0, progress.value),
                    highlight = resolvedSectorLabel,
                    sentence = stringResource(RdR.string.rd_loading_sector_format, resolvedSectorLabel),
                    compact = compact,
                )
                LoadingStepRow(
                    status = stepStatus(1, progress.value),
                    highlight = resolvedHazardsLabel,
                    sentence = stringResource(RdR.string.rd_loading_hazard_format, resolvedHazardsLabel),
                    compact = compact,
                )
                LoadingStepRow(
                    status = stepStatus(2, progress.value),
                    highlight = resolvedCertificateLabel,
                    sentence = stringResource(RdR.string.rd_loading_certificate_format, resolvedCertificateLabel),
                    compact = compact,
                )
            }

            Spacer(Modifier.height(if (compact) 10.dp else 16.dp))
            LoadingTestimonialCarousel(compact = compact, modifier = Modifier.widthIn(max = 352.dp))
        }
    }
}

@Composable
private fun LoadingProgress(progress: Float, compact: Boolean) {
    val colors = RdTheme.colors
    val diameter = if (compact) 112.dp else 132.dp
    val lineWidth = if (compact) 9.dp else 10.dp
    val percentage = (progress.coerceIn(0f, 1f) * 100).toInt().coerceAtMost(100)

    Box(Modifier.size(diameter + 22.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(diameter + 22.dp)) {
            drawCircle(
                color = colors.onyx.copy(alpha = 0.06f),
                style = Stroke(width = 1.dp.toPx()),
            )
        }
        Box(
            Modifier.size(diameter).shadow(10.dp, CircleShape, ambientColor = colors.onyx.copy(.06f))
                .clip(CircleShape).background(colors.white),
        )
        Canvas(Modifier.size(diameter)) {
            val stroke = lineWidth.toPx()
            drawCircle(colors.onyx.copy(alpha = 0.10f), style = Stroke(width = stroke))
            drawArc(
                color = colors.onyx,
                startAngle = -90f,
                sweepAngle = 360f * progress.coerceAtLeast(0.006f),
                useCenter = false,
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
        }
        Text(
            "$percentage%",
            style = RdFontStyle.LargeTitle.toTextStyle().copy(fontWeight = FontWeight.Bold),
            color = colors.onyx,
            textAlign = TextAlign.Center,
        )
    }
}

private enum class LoadingStepStatus { Pending, Active, Completed }

private fun stepStatus(index: Int, progress: Float): LoadingStepStatus {
    val lower = index / 3f
    val upper = (index + 1) / 3f
    return when {
        progress >= upper || progress >= 1f -> LoadingStepStatus.Completed
        progress >= lower -> LoadingStepStatus.Active
        else -> LoadingStepStatus.Pending
    }
}

@Composable
private fun LoadingStepRow(
    status: LoadingStepStatus,
    highlight: String,
    sentence: String,
    compact: Boolean,
) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.white)
            .border(
                1.dp,
                colors.onyx.copy(alpha = if (status == LoadingStepStatus.Active) .20f else .06f),
                RoundedCornerShape(14.dp),
            )
            .padding(horizontal = 14.dp, vertical = if (compact) 9.dp else 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(28.dp).clip(CircleShape)
                .background(if (status == LoadingStepStatus.Completed) colors.onyx else colors.onyx.copy(.055f)),
            contentAlignment = Alignment.Center,
        ) {
            when (status) {
                LoadingStepStatus.Completed -> Icon(Icons.Filled.Check, null, tint = colors.white, modifier = Modifier.size(12.dp))
                LoadingStepStatus.Active -> CircularProgressIndicator(
                    modifier = Modifier.size(15.dp),
                    strokeWidth = 2.dp,
                    color = colors.onyx,
                    trackColor = Color.Transparent,
                )
                LoadingStepStatus.Pending -> Box(Modifier.size(5.dp).clip(CircleShape).background(colors.slate.copy(.48f)))
            }
        }
        Spacer(Modifier.width(12.dp))
        Text(
            buildAnnotatedString {
                val start = sentence.indexOf(highlight)
                val body = SpanStyle(color = if (status == LoadingStepStatus.Pending) colors.slate.copy(.78f) else colors.slate)
                if (start < 0) {
                    withStyle(body) { append(sentence) }
                } else {
                    withStyle(body) { append(sentence.substring(0, start)) }
                    withStyle(SpanStyle(color = colors.onyx, fontWeight = FontWeight.SemiBold)) { append(highlight) }
                    withStyle(body) { append(sentence.substring(start + highlight.length)) }
                }
            },
            style = RdFontStyle.Footnote.toTextStyle(),
            modifier = Modifier.weight(1f),
            maxLines = 2,
        )
    }
}

private data class LoadingTestimonial(
    @DrawableRes val avatarRes: Int,
    @StringRes val nameRes: Int,
    @StringRes val roleRes: Int,
    @StringRes val headlineRes: Int,
    @StringRes val bodyRes: Int,
)

private val loadingTestimonials = listOf(
    LoadingTestimonial(
        avatarRes = R.drawable.ob_testimonial_avatar_elif,
        nameRes = RdR.string.rd_testimonial_elif_name,
        roleRes = RdR.string.rd_testimonial_elif_role,
        headlineRes = RdR.string.rd_testimonial_elif_headline,
        bodyRes = RdR.string.rd_testimonial_elif_body,
    ),
    LoadingTestimonial(
        avatarRes = R.drawable.ob_testimonial_avatar_mert,
        nameRes = RdR.string.rd_testimonial_mert_name,
        roleRes = RdR.string.rd_testimonial_mert_role,
        headlineRes = RdR.string.rd_testimonial_mert_headline,
        bodyRes = RdR.string.rd_testimonial_mert_body,
    ),
    LoadingTestimonial(
        avatarRes = R.drawable.ob_testimonial_avatar_selin,
        nameRes = RdR.string.rd_testimonial_selin_name,
        roleRes = RdR.string.rd_testimonial_selin_role,
        headlineRes = RdR.string.rd_testimonial_selin_headline,
        bodyRes = RdR.string.rd_testimonial_selin_body,
    ),
    LoadingTestimonial(
        avatarRes = R.drawable.ob_testimonial_avatar_burak,
        nameRes = RdR.string.rd_testimonial_burak_name,
        roleRes = RdR.string.rd_testimonial_burak_role,
        headlineRes = RdR.string.rd_testimonial_burak_headline,
        bodyRes = RdR.string.rd_testimonial_burak_body,
    ),
)

@Composable
private fun LoadingTestimonialCarousel(compact: Boolean, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    var index by remember { mutableIntStateOf(0) }

    LaunchedEffect(Unit) {
        while (true) {
            delay(2_700)
            index = (index + 1) % loadingTestimonials.size
        }
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(if (compact) 7.dp else 9.dp)) {
        Text(
            stringResource(RdR.string.rd_loading_testimonials_title),
            style = RdFontStyle.Subheadline.toTextStyle().copy(fontWeight = FontWeight.Bold),
            color = colors.onyx,
        )
        Crossfade(targetState = index, animationSpec = tween(240), label = "loading-testimonial") { target ->
            val testimonial = loadingTestimonials[target]
            Column(
                Modifier.fillMaxWidth().height(if (compact) 164.dp else 184.dp)
                    .shadow(12.dp, RoundedCornerShape(18.dp), ambientColor = colors.onyx.copy(.055f))
                    .clip(RoundedCornerShape(18.dp)).background(colors.white)
                    .border(1.dp, colors.onyx.copy(.08f), RoundedCornerShape(18.dp))
                    .padding(if (compact) 13.dp else 15.dp),
                verticalArrangement = Arrangement.spacedBy(if (compact) 7.dp else 9.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Image(
                        painter = painterResource(testimonial.avatarRes),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.size(if (compact) 38.dp else 44.dp)
                            .clip(CircleShape)
                            .border(1.dp, colors.onyx.copy(alpha = .10f), CircleShape),
                    )
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(testimonial.nameRes), style = RdFontStyle.Subheadline.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.onyx)
                        Text(stringResource(testimonial.roleRes), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate, maxLines = 2)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(1.dp)) {
                        repeat(5) { Icon(Icons.Filled.Star, null, tint = colors.planPlus, modifier = Modifier.size(10.dp)) }
                    }
                }
                Text(stringResource(testimonial.headlineRes), style = RdFontStyle.Subheadline.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.onyx)
                Text(stringResource(testimonial.bodyRes), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate, maxLines = if (compact) 3 else 4)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            loadingTestimonials.indices.forEach { itemIndex ->
                Box(
                    Modifier.padding(horizontal = 2.5.dp)
                        .width(if (itemIndex == index) 16.dp else 5.dp).height(5.dp)
                        .clip(CircleShape)
                        .background(if (itemIndex == index) colors.onyx else colors.onyx.copy(.15f)),
                )
            }
        }
    }
}
