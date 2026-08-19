package com.riskdetectedan.core.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.sqrt
import kotlin.math.roundToInt

/**
 * Claude Design paywall → Compose birebir port.
 *
 * Kaynak: `App/Views/Paywall/Design/PaywallDesignKit.swift` (393×852 iPhone çerçevesi).
 * CSS px → SwiftUI pt → Compose dp aynı sayıyla taşınır. iOS portu güvenli alanı yok sayıp
 * durum çubuğunun altına çizdiği için 44pt'lik bir üst boşluk taşır; Android tarafında tüm
 * uygulama `MainActivity`'de `safeDrawingPadding()` ile zaten güvenli alana yerleşir, bu yüzden
 * o boşluk [RdPaywallDesignMetric.HeroHeight] içinden düşülür (300 − 44) ve kapatma düğmesi
 * 56 yerine 12dp yukarıdan başlar. Geri kalan tüm ölçüler iOS ile aynıdır.
 *
 * Ekran genişliği iPhone çerçevesinden farklı olabildiği için yalnızca hero bloğu genişlikle
 * orantılı ölçeklenir; tipografi ve kart ölçüleri sabit dp kalır (bkz. [rdPaywallHeroHeight]).
 */
object RdPaywallDesignColor {
    val Ink = Color(0xFF16232E)
    val Muted = Color(0xFF8A94A6)
    val Orange = Color(0xFFFF9500)
    val OrangeSoft = Color(0xFFFF9500).copy(alpha = 0.55f)
    val IdleMark = Color(0xFFC7CDD6)
    val IdleRail = Color(0xFFD9DEE5)
    val CardBorder = Color(0xFFE5E7EB)
    val OrangeCardBg = Color(0xFFFFF7ED)
    val Green = Color(0xFF1FAA59)
    val GreenCardBg = Color(0xFFF0FAF4)
    val Amber = Color(0xFFFFB800)
    val AmberCardBg = Color(0xFFFFFAEB)
    val AmberInk = Color(0xFFB8860B)
    val Footer = Color(0xFF9AA3B2)
    val RuleStrong = Color(0xFFEEEEEE)
    val Rule = Color(0xFFF2F2F2)
    val ErrorInk = Color(0xFFB3261E)
    val ErrorBg = Color(0xFFFDECEA)
    val Surface = Color.White

    /** Kayan özellik şeridi etiketleri: vurgu rengi göz yorduğu için nötr gri zemin. */
    val ChipBg = Color(0xFFF4F5F7)
    val ChipBorder = Color(0xFFE3E6EB)
}

object RdPaywallDesignMetric {
    val ScreenPadding = 20.dp

    /** iOS: 300pt hero − 44pt durum çubuğu payı (Android'de safe area zaten uygulanmış). */
    val HeroHeight = 256.dp

    /** Tasarım referans genişliği (iPhone 393pt çerçevesi). */
    val ReferenceWidth = 393.dp

    /** rd_paywall_hero_face.jpg → 1320 × 990 (4:3, iOS'taki 1448/1086 ile aynı oran). */
    const val HeroImageAspect = 1448f / 1086f

    val SocialProofBoxWidth = 188.dp
    val SocialProofBoxHeight = 56.dp

    /** rd_paywall_social_proof.jpg → 600 × 337 (iOS'taki 1672/941 ile aynı oran). */
    val SocialProofImageWidth = 198.4.dp
    const val SocialProofImageAspect = 1672f / 941f

    /**
     * iOS'taki yerleşimin kaynak-dikdörtgen karşılığı: 198.4×111.7dp'lik görsel, (−5.7, −24.2)dp
     * kaydırılıp 188×56dp'lik kutuya kırpılır. Aşağıdaki oranlar bu dört sayıdan türetilmiştir.
     */
    private val SocialProofImageHeightDp = 198.4f / SocialProofImageAspect
    const val SocialProofCropLeft = 5.7f / 198.4f
    val SocialProofCropTop = 24.2f / SocialProofImageHeightDp
    const val SocialProofCropWidth = 188f / 198.4f
    val SocialProofCropHeight = 56f / SocialProofImageHeightDp

    /**
     * Hero kutusu 256dp, görsel ise genişlik/en-boy kadar uzun. Görünen dikey oran genişlikten
     * bağımsız sabittir: (256·ölçek) / (genişlik/en-boy) = 256·en-boy/393.
     */
    val HeroVisibleImageFraction = (256f * HeroImageAspect) / 393f

    val MarkColumnWidth = 52.dp
    val CardRadius = 16.dp
}

/** Hero bloğu ekran genişliğiyle orantılı ölçeklenir; 393dp referansta ölçek 1.0'dır. */
fun rdPaywallHeroScale(availableWidth: Dp): Float =
    (availableWidth / RdPaywallDesignMetric.ReferenceWidth).coerceIn(0.80f, 1.25f)

fun rdPaywallHeroHeight(availableWidth: Dp): Dp =
    RdPaywallDesignMetric.HeroHeight * rdPaywallHeroScale(availableWidth)

// MARK: - Tipografi

/**
 * CSS `line-height` bloğunun karşılığı: satır yüksekliği çarpanla verilir ve artan boşluk
 * satırın üstüne/altına eşit dağıtılır (iOS portundaki half-leading davranışı).
 */
internal fun rdPaywallText(
    size: Float,
    weight: FontWeight = FontWeight.Normal,
    color: Color = RdPaywallDesignColor.Ink,
    lineHeightMultiple: Float? = null,
    letterSpacing: Float = 0f,
): TextStyle = TextStyle(
    fontSize = size.sp,
    fontWeight = weight,
    color = color,
    fontFamily = FontFamily.SansSerif,
    letterSpacing = letterSpacing.sp,
    lineHeight = if (lineHeightMultiple == null) TextStyle.Default.lineHeight else (size * lineHeightMultiple).sp,
    lineHeightStyle = LineHeightStyle(
        alignment = LineHeightStyle.Alignment.Center,
        trim = LineHeightStyle.Trim.None,
    ),
    platformStyle = PlatformTextStyle(includeFontPadding = false),
)

// MARK: - Vektör ikonlar (SVG path'lerin birebir karşılığı)

private fun viewBoxPath(viewBox: Size, target: Size, build: Path.() -> Unit): Path {
    val path = Path().apply(build)
    val matrix = Matrix().apply { scale(target.width / viewBox.width, target.height / viewBox.height) }
    path.transform(matrix)
    return path
}

private fun strokeScale(viewBox: Size, target: Size): Float =
    sqrt((target.width / viewBox.width) * (target.height / viewBox.height))

private fun DrawScope.strokeViewBox(
    viewBox: Size,
    color: Color,
    lineWidth: Float,
    cap: StrokeCap = StrokeCap.Butt,
    join: StrokeJoin = StrokeJoin.Miter,
    build: Path.() -> Unit,
) {
    drawPath(
        path = viewBoxPath(viewBox, size, build),
        color = color,
        style = Stroke(
            width = lineWidth * strokeScale(viewBox, size),
            cap = cap,
            join = join,
        ),
    )
}

private fun DrawScope.fillViewBox(viewBox: Size, color: Color, build: Path.() -> Unit) {
    drawPath(path = viewBoxPath(viewBox, size, build), color = color)
}

/** Tik işareti — viewBox 15×12. */
@Composable
fun RdPaywallCheckIcon(width: Dp, height: Dp, lineWidth: Float, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(width, height)) {
        strokeViewBox(Size(15f, 12f), color, lineWidth, StrokeCap.Round, StrokeJoin.Round) {
            moveTo(1f, 6f)
            lineTo(5.5f, 10.5f)
            lineTo(14f, 1f)
        }
    }
}

/** Çarpı — viewBox `side`×`side`, path 1..(side − 1). */
@Composable
fun RdPaywallCrossIcon(
    width: Dp,
    height: Dp,
    viewBoxSide: Float,
    lineWidth: Float,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier.size(width, height)) {
        val far = viewBoxSide - 1f
        strokeViewBox(Size(viewBoxSide, viewBoxSide), color, lineWidth, StrokeCap.Round) {
            moveTo(1f, 1f)
            lineTo(far, far)
            moveTo(far, 1f)
            lineTo(1f, far)
        }
    }
}

/** Zil — viewBox 14×15. */
@Composable
fun RdPaywallBellIcon(
    modifier: Modifier = Modifier,
    width: Dp = 14.dp,
    height: Dp = 15.dp,
    color: Color = Color.White,
) {
    Canvas(modifier.size(width, height)) {
        val viewBox = Size(14f, 15f)
        strokeViewBox(viewBox, color, 1.4f, join = StrokeJoin.Round) {
            moveTo(7f, 1f)
            cubicTo(4.5f, 1f, 3f, 2.8f, 3f, 5.2f)
            lineTo(3f, 7.5f)
            lineTo(1.5f, 10f)
            lineTo(12.5f, 10f)
            lineTo(11f, 7.5f)
            lineTo(11f, 5.2f)
            cubicTo(11f, 2.8f, 9.5f, 1f, 7f, 1f)
            close()
        }
        strokeViewBox(viewBox, color, 1.4f, StrokeCap.Round) {
            arcTo(
                rect = Rect(center = Offset(7f, 12.5f), radius = 1.7f),
                startAngleDegrees = 0f,
                sweepAngleDegrees = 180f,
                forceMoveTo = true,
            )
        }
    }
}

/** Kart — viewBox 15×12. */
@Composable
fun RdPaywallCardIcon(
    modifier: Modifier = Modifier,
    width: Dp = 15.dp,
    height: Dp = 12.dp,
    color: Color = Color.White,
) {
    Canvas(modifier.size(width, height)) {
        val viewBox = Size(15f, 12f)
        strokeViewBox(viewBox, color, 1.4f) {
            addRoundRect(
                RoundRect(
                    rect = Rect(left = 1f, top = 1f, right = 14f, bottom = 11f),
                    cornerRadius = CornerRadius(1.5f, 1.5f),
                ),
            )
        }
        fillViewBox(viewBox, color) {
            addRect(Rect(left = 1f, top = 3.4f, right = 14f, bottom = 5.4f))
        }
    }
}

/** Yıldız — viewBox 24×24, dolu. */
@Composable
fun RdPaywallStarIcon(color: Color, modifier: Modifier = Modifier, width: Dp = 18.dp, height: Dp = 18.dp) {
    Canvas(modifier.size(width, height)) {
        fillViewBox(Size(24f, 24f), color) {
            moveTo(12f, 2f)
            lineTo(15.09f, 8.26f)
            lineTo(22f, 9.27f)
            lineTo(17f, 14.14f)
            lineTo(18.18f, 21.02f)
            lineTo(12f, 17.77f)
            lineTo(5.82f, 21.02f)
            lineTo(7f, 14.14f)
            lineTo(2f, 9.27f)
            lineTo(8.91f, 8.26f)
            close()
        }
    }
}

/** Taç — viewBox 24×20, dolu. */
@Composable
fun RdPaywallCrownIcon(color: Color, modifier: Modifier = Modifier, width: Dp = 20.dp, height: Dp = 18.dp) {
    Canvas(modifier.size(width, height)) {
        fillViewBox(Size(24f, 20f), color) {
            moveTo(2f, 6f)
            lineTo(6.5f, 9f)
            lineTo(12f, 2f)
            lineTo(17.5f, 9f)
            lineTo(22f, 6f)
            lineTo(20f, 18f)
            lineTo(4f, 18f)
            close()
        }
    }
}

/** Chevron — viewBox 8×14. */
@Composable
fun RdPaywallChevronIcon(color: Color, modifier: Modifier = Modifier, width: Dp = 8.dp, height: Dp = 14.dp) {
    Canvas(modifier.size(width, height)) {
        strokeViewBox(Size(8f, 14f), color, 2f, StrokeCap.Round, StrokeJoin.Round) {
            moveTo(1f, 1f)
            lineTo(7f, 7f)
            lineTo(1f, 13f)
        }
    }
}

/** Dolu daire içinde tik (karşılaştırma tablosu + zaman çizelgesi rozeti). */
@Composable
fun RdPaywallCheckBadge(
    diameter: Dp,
    checkWidth: Dp,
    checkHeight: Dp,
    checkLineWidth: Float,
    background: Color,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.size(diameter).clip(CircleShape).background(background),
        contentAlignment = Alignment.Center,
    ) {
        RdPaywallCheckIcon(checkWidth, checkHeight, checkLineWidth, Color.White)
    }
}

// MARK: - Hero

@Composable
fun RdPaywallDesignHero(label: String, onClose: () -> Unit, modifier: Modifier = Modifier) {
    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .background(RdPaywallDesignColor.Surface),
    ) {
        val heroWidth = maxWidth
        val scale = rdPaywallHeroScale(heroWidth)
        val closeLabel = stringResource(R.string.rd_paywall_design_close)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(rdPaywallHeroHeight(heroWidth))
                .clipToBounds(),
        ) {
            // Sosyal kanıt rozetiyle aynı gerekçe: kutudan uzun bir görseli üstten hizalayıp
            // kırpmak yerine kaynak dikdörtgeni doğrudan verilir. Görünen oran genişlikten
            // bağımsızdır (256·en_boy/393), bu yüzden her ekran genişliğinde aynı kadraj çıkar.
            val heroArtwork = ImageBitmap.imageResource(R.drawable.rd_paywall_hero_face)
            Canvas(modifier = Modifier.fillMaxSize()) {
                val visibleFraction = RdPaywallDesignMetric.HeroVisibleImageFraction
                drawImage(
                    image = heroArtwork,
                    srcOffset = IntOffset.Zero,
                    srcSize = IntSize(
                        width = heroArtwork.width,
                        height = (heroArtwork.height * visibleFraction).roundToInt()
                            .coerceAtMost(heroArtwork.height),
                    ),
                    dstSize = IntSize(size.width.roundToInt(), size.height.roundToInt()),
                    filterQuality = FilterQuality.High,
                )
            }

            // Görselin üstündeki beyaza doğru yumuşama (iOS: 0.85 → 0, 48pt).
            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .height(48.dp * scale)
                    .background(
                        Brush.verticalGradient(
                            listOf(
                                RdPaywallDesignColor.Surface.copy(alpha = 0.85f),
                                RdPaywallDesignColor.Surface.copy(alpha = 0f),
                            ),
                        ),
                    ),
            )

            // Alt yumuşama: içerik beyaz zemine karışarak biter.
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(34.dp * scale)
                    .background(
                        Brush.verticalGradient(
                            listOf(
                                RdPaywallDesignColor.Surface.copy(alpha = 0f),
                                RdPaywallDesignColor.Surface,
                            ),
                        ),
                    ),
            )

            Text(
                text = label,
                style = rdPaywallText(12.5f, FontWeight.Bold, RdPaywallDesignColor.Ink),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 10.dp)
                    .clip(CircleShape)
                    .background(RdPaywallDesignColor.Surface.copy(alpha = 0.78f))
                    .padding(horizontal = 14.dp, vertical = 5.dp)
                    .testTag(RdPaywallDesignTag.HeroLabel),
            )

            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 12.dp, end = 16.dp)
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(RdPaywallDesignColor.Surface.copy(alpha = 0.6f))
                    .border(1.dp, Color.Black.copy(alpha = 0.06f), CircleShape)
                    .clickable(onClick = onClose)
                    .semantics { contentDescription = closeLabel }
                    .testTag(RdPaywallDesignTag.Close),
                contentAlignment = Alignment.Center,
            ) {
                RdPaywallCrossIcon(13.dp, 13.dp, viewBoxSide = 13f, lineWidth = 1.8f, color = RdPaywallDesignColor.Ink)
            }
        }
    }
}

// MARK: - Sosyal kanıt

@Composable
fun RdPaywallDesignSocialProof(modifier: Modifier = Modifier) {
    val description = stringResource(R.string.rd_paywall_design_social_proof)
    val artwork = ImageBitmap.imageResource(R.drawable.rd_paywall_social_proof)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 6.dp, start = RdPaywallDesignMetric.ScreenPadding, end = RdPaywallDesignMetric.ScreenPadding),
        contentAlignment = Alignment.TopCenter,
    ) {
        // iOS'ta bu rozet, kutudan büyük bir görselin negatif offset'le kaydırılıp kırpılmasıyla
        // elde ediliyor. Compose'da "kutudan büyük çocuk + offset + clip" zinciri ebeveyn
        // kısıtlarına takılıp görseli ezdiği için kırpma doğrudan kaynak dikdörtgeni verilerek
        // yapılır: sonuç aynı, ölçümü belirlenimci.
        Canvas(
            modifier = Modifier
                .size(RdPaywallDesignMetric.SocialProofBoxWidth, RdPaywallDesignMetric.SocialProofBoxHeight)
                .semantics { contentDescription = description }
                .testTag(RdPaywallDesignTag.SocialProof),
        ) {
            val srcX = (RdPaywallDesignMetric.SocialProofCropLeft * artwork.width).roundToInt()
            val srcY = (RdPaywallDesignMetric.SocialProofCropTop * artwork.height).roundToInt()
            val srcWidth = (RdPaywallDesignMetric.SocialProofCropWidth * artwork.width).roundToInt()
            val srcHeight = (RdPaywallDesignMetric.SocialProofCropHeight * artwork.height).roundToInt()
            drawImage(
                image = artwork,
                srcOffset = IntOffset(srcX, srcY),
                srcSize = IntSize(
                    width = srcWidth.coerceAtMost(artwork.width - srcX),
                    height = srcHeight.coerceAtMost(artwork.height - srcY),
                ),
                dstSize = IntSize(size.width.roundToInt(), size.height.roundToInt()),
                filterQuality = FilterQuality.High,
            )
        }
    }
}

// MARK: - Ücretsiz deneme zaman çizelgesi

@Composable
fun RdPaywallDesignTrialTimeline(
    trialDays: Int,
    tierName: String,
    accent: Color,
    modifier: Modifier = Modifier,
) {
    val reminderDay = maxOf(1, trialDays - 2)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 16.dp, start = RdPaywallDesignMetric.ScreenPadding, end = RdPaywallDesignMetric.ScreenPadding)
            .testTag(RdPaywallDesignTag.TrialTimeline),
    ) {
        TimelineRow(
            circleColor = RdPaywallDesignColor.Orange,
            railColor = RdPaywallDesignColor.Orange,
            icon = { RdPaywallCheckIcon(13.dp, 10.5.dp, lineWidth = 2f, color = Color.White) },
        ) {
            // Diğer basamaklarla aynı biçim: başlık üstte, açıklama altında.
            // Alt boşluk bağlantı çizgisinin görünmesi için diğer satırlarla eşittir.
            TimelineTodayStep(
                tierName = tierName,
                accent = accent,
                modifier = Modifier.padding(bottom = 22.dp),
            )
        }

        TimelineRow(
            circleColor = RdPaywallDesignColor.IdleMark,
            railColor = RdPaywallDesignColor.IdleRail,
            icon = { RdPaywallBellIcon(width = 12.5.dp, height = 13.5.dp) },
        ) {
            TimelineStep(
                title = stringResource(R.string.rd_paywall_design_timeline_day_format, reminderDay.toString()),
                detail = stringResource(R.string.rd_paywall_design_timeline_reminder),
                modifier = Modifier.padding(bottom = 22.dp),
            )
        }

        TimelineRow(
            circleColor = RdPaywallDesignColor.IdleMark,
            railColor = null,
            icon = { RdPaywallCardIcon(width = 13.dp, height = 10.5.dp) },
        ) {
            TimelineStep(
                title = stringResource(R.string.rd_paywall_design_timeline_day_format, trialDays.toString()),
                detail = stringResource(R.string.rd_paywall_design_timeline_billing),
            )
        }
    }
}

/**
 * Zaman çizelgesi satırı: solda daire + bağlantı çizgisi, sağda içerik.
 *
 * Bağlantı çizgisi satırın arka planına çizilir, ayrı bir yerleşim öğesi olarak konmaz —
 * `IntrinsicSize.Min` ile ölçmek özellik ızgarasının ikinci satırını kırpıyordu (iç içe esnek
 * genişlikli metinlerde iç ölçüm gerçek yükseklikten küçük çıkıyor). Arka plana çizmek satırın
 * gerçek yüksekliğini kullanır, dolayısıyla içerik ne kadar uzarsa çizgi de o kadar uzar.
 */
@Composable
private fun TimelineRow(
    circleColor: Color,
    railColor: Color?,
    icon: @Composable () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val circleSize = 28.dp
    val railInset = 3.dp
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (railColor == null) {
                    Modifier
                } else {
                    Modifier.drawBehind {
                        val x = circleSize.toPx() / 2f
                        val top = circleSize.toPx() + railInset.toPx()
                        val bottom = size.height - railInset.toPx()
                        if (bottom > top) {
                            drawLine(
                                color = railColor,
                                start = Offset(x, top),
                                end = Offset(x, bottom),
                                strokeWidth = 2.dp.toPx(),
                            )
                        }
                    }
                },
            ),
    ) {
        Box(
            modifier = Modifier.size(circleSize).clip(CircleShape).background(circleColor),
            contentAlignment = Alignment.Center,
        ) { icon() }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f), content = content)
    }
}

/** Bugün satırı: açıklamanın başında taç ikonu, paket adı vurgu renginde. */
@Composable
private fun TimelineTodayStep(tierName: String, accent: Color, modifier: Modifier = Modifier) {
    val detail = stringResource(R.string.rd_paywall_design_timeline_today_detail_format, tierName)
    // Paket adı cümlenin içinde geçtiği yerde vurgulanır; çeviri sırası değişse de yer
    // tutucunun karşılığı aranarak bulunur, sabit bir ön/son ek varsayılmaz.
    val highlight = detail.indexOf(tierName)
    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = stringResource(R.string.rd_paywall_design_timeline_today),
            style = rdPaywallText(13.5f, FontWeight.Bold, RdPaywallDesignColor.Ink),
        )
        // Taç paket adının hemen soluna, metnin içine yerleşir: satır kaydığında ikon da
        // adla birlikte taşınır (satır içi yerleştirme `InlineTextContent` ile yapılır).
        val crownId = "rd-paywall-today-crown"
        Text(
            text = if (highlight < 0) {
                buildAnnotatedString { append(detail) }
            } else {
                buildAnnotatedString {
                    append(detail.substring(0, highlight))
                    // Yer tutucunun alternatif metni boş olamaz; ekran okuyucuda
                    // yalnızca boşluk olarak duyulur, görsel boşluk da buradan gelir.
                    appendInlineContent(crownId, " ")
                    append(" ")
                    withStyle(SpanStyle(color = accent, fontWeight = FontWeight.Bold)) {
                        append(tierName)
                    }
                    append(detail.substring(highlight + tierName.length))
                }
            },
            inlineContent = mapOf(
                crownId to InlineTextContent(
                    Placeholder(
                        width = 13.sp,
                        height = 11.7.sp,
                        placeholderVerticalAlign = PlaceholderVerticalAlign.TextCenter,
                    ),
                ) {
                    RdPaywallCrownIcon(color = accent, width = 13.dp, height = 11.7.dp)
                },
            ),
            style = rdPaywallText(12.5f, color = RdPaywallDesignColor.Muted, lineHeightMultiple = 1.4f),
            modifier = Modifier.padding(top = 3.dp),
        )
    }
}

@Composable
private fun TimelineStep(title: String, detail: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxWidth()) {
        Text(title, style = rdPaywallText(13.5f, FontWeight.Bold, RdPaywallDesignColor.Ink))
        Text(
            text = detail,
            style = rdPaywallText(12.5f, color = RdPaywallDesignColor.Muted, lineHeightMultiple = 1.4f),
            modifier = Modifier.padding(top = 2.dp),
        )
    }
}

// MARK: - Şerit ikonları

/**
 * Şerit etiketlerinin çizgisel ikonları (iOS'taki `PaywallDesignFeatureGlyph` karşılığı).
 * Hepsi 20×20 viewBox üzerine çizilir ve yalnızca kontur olarak boyanır — içi dolu ikon yok.
 */
enum class RdPaywallDesignGlyph {
    /** Kalkan + tik — risk analizi */
    Shield,

    /** Sütun grafik — detaylı analiz */
    Chart,

    /** Üst üste iki kare + ufuk çizgisi — çoklu fotoğraf */
    Photos,

    /** Bina — firma yönetimi */
    Building,

    /** Gösterge kadranı — Fine-Kinney risk puanlaması */
    Gauge,

    /** Izgara — 5x5 matris */
    Grid,

    /** Büyüteç — derin araştırma */
    Magnifier,

    /** Ayar sürgüleri — rapor özelleştirme */
    Sliders,

    /** Kapaklı kutu — arşiv yönetimi */
    Archive,

    /** Kişi + tik — sorumlu atama */
    Assignee,

    /** Nişangâh — odaklı analiz */
    Target,
}

/**
 * Şerit etiketi: metin ve ona ait ikon birlikte taşınır; ikon seçimi çeviriye değil içerik
 * tanımına bağlıdır (bkz. `RdPaywallDesignCopy.timelineFeatures`).
 */
data class RdPaywallDesignFeature(
    val title: String,
    val glyph: RdPaywallDesignGlyph,
)

/** Kontur genişliği ölçekten bağımsız sabit dp'dir; iOS portundaki 1.5pt ile aynı. */
@Composable
fun RdPaywallFeatureIcon(
    glyph: RdPaywallDesignGlyph,
    size: Dp,
    color: Color,
    modifier: Modifier = Modifier,
    lineWidth: Dp = 1.5.dp,
) {
    Canvas(modifier.size(size)) {
        val viewBox = Size(20f, 20f)
        val path = viewBoxPath(viewBox, this.size) {
            when (glyph) {
                RdPaywallDesignGlyph.Shield -> shieldGlyph()
                RdPaywallDesignGlyph.Chart -> chartGlyph()
                RdPaywallDesignGlyph.Photos -> photosGlyph()
                RdPaywallDesignGlyph.Building -> buildingGlyph()
                RdPaywallDesignGlyph.Gauge -> gaugeGlyph()
                RdPaywallDesignGlyph.Grid -> gridGlyph()
                RdPaywallDesignGlyph.Magnifier -> magnifierGlyph()
                RdPaywallDesignGlyph.Sliders -> slidersGlyph()
                RdPaywallDesignGlyph.Archive -> archiveGlyph()
                RdPaywallDesignGlyph.Assignee -> assigneeGlyph()
                RdPaywallDesignGlyph.Target -> targetGlyph()
            }
        }
        drawPath(
            path = path,
            color = color,
            style = Stroke(
                width = lineWidth.toPx(),
                cap = StrokeCap.Round,
                join = StrokeJoin.Round,
            ),
        )
    }
}

private fun Path.shieldGlyph() {
    moveTo(10f, 2.4f)
    lineTo(16.4f, 5f)
    lineTo(16.4f, 9.8f)
    // iOS'taki iki quad eğrinin kübik karşılığı (C1 = P0 + 2/3·(C−P0), C2 = P2 + 2/3·(C−P2)).
    cubicTo(16.4f, 13.1333f, 14.2667f, 15.7333f, 10f, 17.6f)
    cubicTo(5.7333f, 15.7333f, 3.6f, 13.1333f, 3.6f, 9.8f)
    lineTo(3.6f, 5f)
    close()
    moveTo(7.3f, 9.9f)
    lineTo(9.3f, 11.9f)
    lineTo(12.8f, 8f)
}

private fun Path.chartGlyph() {
    moveTo(3.4f, 3f)
    lineTo(3.4f, 16.4f)
    lineTo(16.8f, 16.4f)
    moveTo(7f, 16.4f)
    lineTo(7f, 11.6f)
    moveTo(10.6f, 16.4f)
    lineTo(10.6f, 8.4f)
    moveTo(14.2f, 16.4f)
    lineTo(14.2f, 5.2f)
}

private fun Path.photosGlyph() {
    addRoundRect(RoundRect(Rect(6.6f, 2.4f, 17.6f, 13.4f), CornerRadius(2.4f)))
    addRoundRect(RoundRect(Rect(2.4f, 6.6f, 13.4f, 17.6f), CornerRadius(2.4f)))
    addOval(Rect(4.5f, 8.7f, 6.7f, 10.9f))
    moveTo(3.2f, 15.4f)
    lineTo(6.6f, 11.8f)
    lineTo(9.2f, 14.4f)
    lineTo(10.8f, 12.9f)
    lineTo(12.9f, 15f)
}

private fun Path.buildingGlyph() {
    moveTo(4f, 17f)
    lineTo(4f, 3.4f)
    lineTo(12.2f, 3.4f)
    lineTo(12.2f, 17f)
    moveTo(12.2f, 8.6f)
    lineTo(16.4f, 8.6f)
    lineTo(16.4f, 17f)
    moveTo(2.6f, 17f)
    lineTo(17.6f, 17f)
    moveTo(6.7f, 6.6f)
    lineTo(9.5f, 6.6f)
    moveTo(6.7f, 9.8f)
    lineTo(9.5f, 9.8f)
    moveTo(6.7f, 13f)
    lineTo(9.5f, 13f)
    moveTo(14f, 11.6f)
    lineTo(14.8f, 11.6f)
    moveTo(14f, 14.2f)
    lineTo(14.8f, 14.2f)
}

private fun Path.gaugeGlyph() {
    arcTo(
        rect = Rect(center = Offset(10f, 13.2f), radius = 6.8f),
        startAngleDegrees = 180f,
        sweepAngleDegrees = 180f,
        forceMoveTo = true,
    )
    // İbre: sağ üst çeyreğe bakar (yüksek risk skoru okuması).
    moveTo(9.4f, 13.6f)
    lineTo(14.2f, 8.2f)
    moveTo(3.2f, 15.6f)
    lineTo(16.8f, 15.6f)
}

private fun Path.gridGlyph() {
    addRoundRect(RoundRect(Rect(2.8f, 2.8f, 17.2f, 17.2f), CornerRadius(2.4f)))
    for (offset in listOf(7.6f, 12.4f)) {
        moveTo(offset, 2.8f)
        lineTo(offset, 17.2f)
        moveTo(2.8f, offset)
        lineTo(17.2f, offset)
    }
}

private fun Path.magnifierGlyph() {
    addOval(Rect(3f, 3f, 14.2f, 14.2f))
    moveTo(12.6f, 12.6f)
    lineTo(17.2f, 17.2f)
}

private fun Path.slidersGlyph() {
    for ((y, knob) in listOf(5.6f to 13.2f, 10f to 7.2f, 14.4f to 14f)) {
        moveTo(3f, y)
        lineTo(17f, y)
        addOval(Rect(knob - 1.8f, y - 1.8f, knob + 1.8f, y + 1.8f))
    }
}

private fun Path.archiveGlyph() {
    addRoundRect(RoundRect(Rect(2.6f, 3.2f, 17.4f, 7.2f), CornerRadius(1.2f)))
    moveTo(4.2f, 7.2f)
    lineTo(4.2f, 15f)
    quadraticBezierTo(4.2f, 16.6f, 5.8f, 16.6f)
    lineTo(14.2f, 16.6f)
    quadraticBezierTo(15.8f, 16.6f, 15.8f, 15f)
    lineTo(15.8f, 7.2f)
    moveTo(8f, 10.6f)
    lineTo(12f, 10.6f)
}

private fun Path.assigneeGlyph() {
    addOval(Rect(5.2f, 3.4f, 11.6f, 9.8f))
    moveTo(2.2f, 17f)
    quadraticBezierTo(7.2f, 11f, 12.2f, 17f)
    moveTo(13.4f, 11.4f)
    lineTo(15.1f, 13.1f)
    lineTo(18.4f, 9.4f)
}

private fun Path.targetGlyph() {
    addOval(Rect(3.4f, 3.4f, 16.6f, 16.6f))
    addOval(Rect(7.6f, 7.6f, 12.4f, 12.4f))
    moveTo(10f, 1.2f)
    lineTo(10f, 3.2f)
    moveTo(10f, 16.8f)
    lineTo(10f, 18.8f)
    moveTo(1.2f, 10f)
    lineTo(3.2f, 10f)
    moveTo(16.8f, 10f)
    lineTo(18.8f, 10f)
}

// MARK: - Kayan özellik şeridi

/**
 * Zaman çizelgesinin altındaki sürekli sola kayan özellik etiketleri (iOS'taki
 * `PaywallDesignFeatureMarquee` karşılığı). Şerit iki özdeş kopyadan oluşur; ilk kopya
 * tam genişliği kadar kayınca başa döner, böylece dikiş yeri görünmez.
 *
 * İçerik ekrandan geniş olduğu için ölçüyü `Box` verir, satır `offset` ile yalnızca çizilir;
 * aksi halde kendi genişliğini ebeveyne dayatıp sayfayı yana kaydırırdı.
 */
@Composable
fun RdPaywallDesignFeatureMarquee(
    features: List<RdPaywallDesignFeature>,
    accent: Color,
    modifier: Modifier = Modifier,
) {
    val spacing = 8.dp
    var rowWidthPx by remember { mutableIntStateOf(0) }
    val density = LocalDensity.current
    val spacingPx = with(density) { spacing.roundToPx() }
    val travelPx = rowWidthPx + spacingPx

    // Saniyede ~34dp: okunacak kadar yavaş, duruyor izlenimi vermeyecek kadar canlı.
    val durationMillis = remember(travelPx) {
        val travelDp = with(density) { travelPx.toDp().value }
        ((travelDp / 34f) * 1000f).toInt().coerceAtLeast(6_000)
    }

    val transition = rememberInfiniteTransition(label = "paywall-feature-marquee")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "paywall-feature-marquee-offset",
    )

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 12.dp)
            .clipToBounds()
            .testTag(RdPaywallDesignTag.FeatureMarquee),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(spacing),
            modifier = Modifier.offset { IntOffset(-(progress * travelPx).toInt(), 0) },
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(spacing),
                modifier = Modifier.onSizeChanged { rowWidthPx = it.width },
            ) {
                features.forEach { MarqueeChip(it, accent) }
            }
            // İkinci kopya yalnızca görsel süreklilik için.
            Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
                features.forEach { MarqueeChip(it, accent) }
            }
        }
    }
}

@Composable
private fun MarqueeChip(feature: RdPaywallDesignFeature, accent: Color) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(RdPaywallDesignColor.ChipBg)
            .border(1.dp, RdPaywallDesignColor.ChipBorder, CircleShape)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        RdPaywallFeatureIcon(glyph = feature.glyph, size = 15.dp, color = accent)
        Text(
            text = feature.title,
            style = rdPaywallText(12.5f, FontWeight.SemiBold, RdPaywallDesignColor.Ink),
            maxLines = 1,
        )
    }
}

// MARK: - Karşılaştırma tablosu

sealed interface RdPaywallDesignMark {
    data object Cross : RdPaywallDesignMark
    data class Check(val color: Color) : RdPaywallDesignMark
    data class Value(val text: String, val color: Color) : RdPaywallDesignMark
}

data class RdPaywallDesignRow(
    val title: String,
    val left: RdPaywallDesignMark,
    val right: RdPaywallDesignMark,
)

/** Sütun başlığında paket adının solunda duran işaret. */
enum class RdPaywallDesignEmblem { None, Crown, Star }

data class RdPaywallDesignColumn(
    val title: String,
    val color: Color,
    val weight: FontWeight,
    val emblem: RdPaywallDesignEmblem = RdPaywallDesignEmblem.None,
)

@Composable
fun RdPaywallDesignComparisonTable(
    left: RdPaywallDesignColumn,
    right: RdPaywallDesignColumn,
    rows: List<RdPaywallDesignRow>,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 16.dp, start = RdPaywallDesignMetric.ScreenPadding, end = RdPaywallDesignMetric.ScreenPadding)
            .testTag(RdPaywallDesignTag.ComparisonTable),
    ) {
        Row(modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
            Spacer(Modifier.weight(1f))
            ComparisonHeader(left)
            ComparisonHeader(right)
        }

        Box(Modifier.fillMaxWidth().height(1.dp).background(RdPaywallDesignColor.RuleStrong))

        rows.forEachIndexed { index, row ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = row.title,
                    style = rdPaywallText(13.5f, color = RdPaywallDesignColor.Ink),
                    modifier = Modifier.weight(1f),
                )
                ComparisonMark(row.left)
                ComparisonMark(row.right)
            }
            if (index < rows.lastIndex) {
                Box(Modifier.fillMaxWidth().height(1.dp).background(RdPaywallDesignColor.Rule))
            }
        }
    }
}

@Composable
private fun ComparisonHeader(column: RdPaywallDesignColumn) {
    Row(
        modifier = Modifier.width(RdPaywallDesignMetric.MarkColumnWidth),
        horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        when (column.emblem) {
            RdPaywallDesignEmblem.None -> Unit
            RdPaywallDesignEmblem.Crown -> RdPaywallCrownIcon(
                color = RdPaywallDesignColor.Orange,
                width = 11.dp,
                height = 9.9.dp,
            )
            RdPaywallDesignEmblem.Star -> RdPaywallStarIcon(
                color = RdPaywallDesignColor.Green,
                width = 10.5.dp,
                height = 10.5.dp,
            )
        }
        Text(
            text = column.title,
            style = rdPaywallText(12f, column.weight, column.color),
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
    }
}

@Composable
private fun ComparisonMark(mark: RdPaywallDesignMark) {
    Box(
        modifier = Modifier.width(RdPaywallDesignMetric.MarkColumnWidth),
        contentAlignment = Alignment.Center,
    ) {
        when (mark) {
            RdPaywallDesignMark.Cross -> RdPaywallCrossIcon(
                width = 10.dp,
                height = 10.dp,
                viewBoxSide = 12f,
                lineWidth = 1.8f,
                color = RdPaywallDesignColor.IdleMark,
            )
            is RdPaywallDesignMark.Check -> RdPaywallCheckBadge(
                diameter = 15.dp,
                checkWidth = 7.dp,
                checkHeight = 6.dp,
                checkLineWidth = 2.4f,
                background = mark.color,
            )
            is RdPaywallDesignMark.Value -> Text(
                text = mark.text,
                style = rdPaywallText(11f, FontWeight.Bold, mark.color),
                maxLines = 1,
                overflow = TextOverflow.Visible,
                textAlign = TextAlign.Center,
            )
        }
    }
}

// MARK: - Plan kartları

@Composable
fun RdPaywallDesignPlanCard(
    title: String,
    price: String,
    caption: String,
    trialNote: String?,
    badgeLabel: String?,
    badgeDiscount: String?,
    accent: Color,
    selectedBackground: Color,
    isSelected: Boolean,
    testTag: String,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight()
                .clip(RoundedCornerShape(RdPaywallDesignMetric.CardRadius))
                .background(if (isSelected) selectedBackground else RdPaywallDesignColor.Surface)
                .border(
                    width = 1.5.dp,
                    color = if (isSelected) accent else RdPaywallDesignColor.CardBorder,
                    shape = RoundedCornerShape(RdPaywallDesignMetric.CardRadius),
                )
                .clickable(onClick = onTap)
                .padding(vertical = 14.dp, horizontal = 12.dp)
                .testTag(testTag),
        ) {
            Row(
                modifier = Modifier.padding(bottom = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(22.dp)
                        .border(2.dp, if (isSelected) accent else RdPaywallDesignColor.IdleMark, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    if (isSelected) {
                        Box(Modifier.size(9.dp).clip(CircleShape).background(accent))
                    }
                }
                Text(title, style = rdPaywallText(14f, FontWeight.Bold, RdPaywallDesignColor.Ink))
            }

            // iOS ile ayni: fiyat kartin en agir ogesi olmamali; 14.5sp yari kalin.
            Text(
                text = price,
                style = rdPaywallText(14.5f, FontWeight.SemiBold, RdPaywallDesignColor.Ink),
                maxLines = 1,
            )
            Text(
                text = caption,
                style = rdPaywallText(12f, color = RdPaywallDesignColor.Muted),
                modifier = Modifier.padding(top = 2.dp),
            )
            if (trialNote != null) {
                Text(
                    text = trialNote,
                    style = rdPaywallText(11f, FontWeight.Bold, accent),
                    modifier = Modifier.padding(top = 7.dp),
                )
            }
        }

        if (badgeLabel != null) {
            Column(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = (-12).dp, y = (-10).dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = badgeLabel,
                    style = rdPaywallText(10f, FontWeight.Bold, Color.White),
                    maxLines = 1,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(accent)
                        .padding(horizontal = 9.dp, vertical = 3.dp),
                )
                if (!badgeDiscount.isNullOrEmpty()) {
                    Text(
                        text = badgeDiscount,
                        style = rdPaywallText(9f, FontWeight.ExtraBold, accent),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

// MARK: - Çapraz satış kartı

@Composable
fun RdPaywallDesignUpsellCard(
    icon: @Composable () -> Unit,
    borderColor: Color,
    background: Color,
    prefix: String,
    highlight: String,
    highlightColor: Color,
    suffix: String,
    testTag: String,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdPaywallDesignMetric.CardRadius))
            .background(background)
            .border(1.5.dp, borderColor, RoundedCornerShape(RdPaywallDesignMetric.CardRadius))
            .clickable(onClick = onTap)
            .padding(vertical = 14.dp, horizontal = 16.dp)
            .testTag(testTag),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        icon()
        Text(
            text = buildAnnotatedString {
                append(prefix)
                withStyle(SpanStyle(fontWeight = FontWeight.ExtraBold, color = highlightColor)) {
                    append(highlight)
                }
                append(suffix)
            },
            style = rdPaywallText(13f, color = RdPaywallDesignColor.Ink, lineHeightMultiple = 1.4f),
            modifier = Modifier.weight(1f),
        )
        RdPaywallChevronIcon(color = borderColor)
    }
}

// MARK: - Uyarı kartı

@Composable
fun RdPaywallDesignNotice(text: String, isError: Boolean, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = rdPaywallText(
            size = 12f,
            color = if (isError) RdPaywallDesignColor.ErrorInk else RdPaywallDesignColor.Ink,
            lineHeightMultiple = 1.4f,
        ),
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (isError) RdPaywallDesignColor.ErrorBg else RdPaywallDesignColor.OrangeCardBg)
            .border(
                width = 1.dp,
                color = (if (isError) RdPaywallDesignColor.ErrorInk else RdPaywallDesignColor.Orange).copy(alpha = 0.25f),
                shape = RoundedCornerShape(12.dp),
            )
            .padding(vertical = 10.dp, horizontal = 12.dp)
            .testTag(if (isError) RdPaywallDesignTag.Error else RdPaywallDesignTag.Notice),
    )
}

// MARK: - Alt aksiyon barı

@Composable
fun RdPaywallDesignFooter(
    ctaTitle: String,
    isLoading: Boolean,
    isDisabled: Boolean,
    accent: Color,
    notice: String?,
    errorMessage: String?,
    /**
     * Seçili planın mağazadan gelen yenileme fiyatı, dönem ekiyle birlikte. Fiyat
     * yüklenmediyse null olur ve satır yalnızca otomatik yenileme cümlesini gösterir.
     */
    renewalPrice: String?,
    onCta: () -> Unit,
    onRestore: () -> Unit,
    onTerms: () -> Unit,
    onPrivacy: () -> Unit,
    onManageSubscription: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(RdPaywallDesignColor.Surface)
            .padding(
                top = 14.dp,
                start = RdPaywallDesignMetric.ScreenPadding,
                end = RdPaywallDesignMetric.ScreenPadding,
                bottom = 16.dp,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (errorMessage != null) {
            RdPaywallDesignNotice(errorMessage, isError = true, modifier = Modifier.padding(bottom = 10.dp))
        } else if (notice != null) {
            RdPaywallDesignNotice(notice, isError = false, modifier = Modifier.padding(bottom = 10.dp))
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .clip(RoundedCornerShape(RdPaywallDesignMetric.CardRadius))
                .background(if (isDisabled) RdPaywallDesignColor.IdleMark else accent)
                .clickable(enabled = !isDisabled, onClick = onCta)
                .testTag(RdPaywallDesignTag.Cta),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    color = Color.White,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(8.dp))
            }
            Text(
                text = ctaTitle,
                style = rdPaywallText(17f, FontWeight.Bold, Color.White, letterSpacing = 0.2f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        val autoRenew = stringResource(R.string.rd_paywall_design_footer_auto_renew)
        Text(
            text = buildAnnotatedString {
                append(autoRenew)
                if (renewalPrice != null) {
                    append(" ")
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(renewalPrice) }
                }
            },
            style = rdPaywallText(11f, color = RdPaywallDesignColor.Footer, lineHeightMultiple = 1.4f),
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 10.dp)
                .testTag(RdPaywallDesignTag.AutoRenew),
        )

        Row(
            modifier = Modifier.padding(top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FooterLink(stringResource(R.string.rd_geri_yukle), RdPaywallDesignTag.Restore, onRestore)
            FooterSeparator()
            FooterLink(stringResource(R.string.rd_paywall_design_footer_terms), RdPaywallDesignTag.Terms, onTerms)
            FooterSeparator()
            FooterLink(stringResource(R.string.rd_gizlilik), RdPaywallDesignTag.Privacy, onPrivacy)
            FooterSeparator()
            FooterLink(
                stringResource(R.string.rd_paywall_design_footer_manage),
                RdPaywallDesignTag.Manage,
                onManageSubscription,
            )
        }
    }
}

@Composable
private fun FooterSeparator() {
    Text("·", style = rdPaywallText(11f, color = RdPaywallDesignColor.Footer))
}

@Composable
private fun FooterLink(title: String, tag: String, onClick: () -> Unit) {
    Text(
        text = title,
        style = rdPaywallText(11f, color = RdPaywallDesignColor.Footer),
        modifier = Modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            )
            .testTag(tag),
    )
}

/** Test etiketleri — iOS'taki `accessibilityIdentifier` değerleriyle birebir aynı. */
object RdPaywallDesignTag {
    const val Plus = "in_app_paywall.plus"
    const val Pro = "in_app_paywall.pro"
    const val Close = "in_app_paywall.close"
    const val HeroLabel = "in_app_paywall.hero_label"
    const val SocialProof = "in_app_paywall.social_proof"
    const val TrialTimeline = "in_app_paywall.trial_timeline"
    const val AutoRenew = "in_app_paywall.auto_renew"
    const val FeatureMarquee = "in_app_paywall.feature_marquee"
    const val ComparisonTable = "in_app_paywall.comparison_table"
    const val PlanYearly = "in_app_paywall.plan.yearly"
    const val PlanMonthly = "in_app_paywall.plan.monthly"
    const val CrossSellPro = "in_app_paywall.plus.pro_link"
    const val CrossSellPlus = "in_app_paywall.pro.plus_link"
    const val Cta = "in_app_paywall.cta"
    const val Restore = "in_app_paywall.restore"
    const val Terms = "in_app_paywall.terms"
    const val Privacy = "in_app_paywall.privacy"
    const val Manage = "in_app_paywall.manage"
    const val Notice = "in_app_paywall.notice"
    const val Error = "in_app_paywall.error"
}
