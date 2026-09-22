package com.riskdetectedan.core.designsystem.isg

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.border
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.tooling.preview.Preview
import com.riskdetectedan.core.designsystem.R

val NovaFontFamilyPublic = FontFamily(
    Font(R.font.plus_jakarta_sans_regular, FontWeight.Normal),
    Font(R.font.plus_jakarta_sans_medium, FontWeight.Medium),
    Font(R.font.plus_jakarta_sans_semibold, FontWeight.SemiBold),
    Font(R.font.plus_jakarta_sans_bold, FontWeight.Bold),
    Font(R.font.plus_jakarta_sans_extrabold, FontWeight.ExtraBold),
)
val LocalNovaDark = staticCompositionLocalOf { false }

fun NovaRGBA.color() = Color(red / 255f, green / 255f, blue / 255f, alpha.toFloat())

@Composable
fun NovaColorToken.color() = rgba(LocalNovaDark.current).color()

fun NovaTypeToken.textStyle(): TextStyle = spec.let {
    TextStyle(fontFamily = NovaFontFamilyPublic, fontWeight = FontWeight(it.weight),
        fontSize = it.size.sp, letterSpacing = it.tracking.sp, lineHeight = it.lineHeight.sp,
        platformStyle = PlatformTextStyle(includeFontPadding = false))
}

/** Scoped to new expert surfaces only; never changes Activity system bars or the legacy theme. */
@Composable
fun NovaTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalNovaDark provides dark) { content() }
}

@Composable
fun NovaText(text: String, modifier: Modifier = Modifier, style: NovaTypeToken = NovaTypeToken.body,
             color: Color = Color.Unspecified, textAlign: TextAlign? = null, maxLines: Int = Int.MAX_VALUE) {
    Text(text, modifier, color = if (color == Color.Unspecified) NovaFont.defaultInk(style) else color,
        style = novaTextStyle(style), textAlign = textAlign, maxLines = maxLines,
        overflow = if (maxLines == Int.MAX_VALUE) TextOverflow.Clip else TextOverflow.Ellipsis)
}

@Composable
fun NovaCard(modifier: Modifier = Modifier, padding: Int = 11, border: Color = Color.Transparent,
             tint: Color? = null, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(NovaDimensionToken.radiusCard.value.dp)
    val fill = tint ?: NovaPopupStyle.controlBackground()
    Column(modifier.shadow(3.dp, shape, ambientColor = Color.Black.copy(alpha = 0.04f), spotColor = Color.Black.copy(alpha = 0.04f))
        .background(fill, shape).border(1.5.dp, border, shape).padding(padding.dp), content = content)
}

/** Full-page canvas is distinct from white rounded card surfaces on every İSGADA destination. */
@Composable
fun NovaPageSurface(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.fillMaxSize().background(NovaColorToken.canvas.color()), content = content)
}

enum class NovaStatus(val background: NovaColorToken, val ink: NovaColorToken) {
    Success(NovaColorToken.statusSuccessBg, NovaColorToken.statusSuccessInk),
    Warning(NovaColorToken.statusWarningBg, NovaColorToken.statusWarningInk),
    Danger(NovaColorToken.statusDangerBg, NovaColorToken.statusDangerInk),
    Info(NovaColorToken.statusInfoBg, NovaColorToken.statusInfoInk),
    Neutral(NovaColorToken.statusNeutralBg, NovaColorToken.statusNeutralInk),
}

@Composable
fun NovaStatusPill(label: String, status: NovaStatus, modifier: Modifier = Modifier, showsDot: Boolean = true) {
    Row(modifier.background(status.background.color(), CircleShape)
        .padding(horizontal = 10.dp, vertical = 6.dp)
        .clearAndSetSemantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        if (showsDot) Box(Modifier.size(6.dp).background(status.ink.color(), CircleShape))
        NovaText(label, style = NovaTypeToken.badge, color = status.ink.color())
    }
}

enum class NovaButtonVariant { Primary, Surface, Muted, Danger }

@Composable
fun NovaButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier,
               variant: NovaButtonVariant = NovaButtonVariant.Primary, enabled: Boolean = true,
               loading: Boolean = false, loadingDescription: String = "İşlem sürüyor",
               symbol: String? = null, compact: Boolean = false) {
    val inPopup = LocalNovaPopup.current
    val active = enabled && !loading
    val (fill, ink) = when {
        !active -> NovaColorToken.surfaceMuted.color() to NovaColorToken.textSecondary.color()
        // Recorded accessibility adaptation: white on #2ed256 is only ~2:1.
        variant == NovaButtonVariant.Primary -> NovaColorToken.accent.color() to Color(0xFF111111)
        variant == NovaButtonVariant.Surface -> NovaPopupStyle.controlBackground(inPopup) to NovaColorToken.text.color()
        variant == NovaButtonVariant.Muted -> NovaColorToken.surfaceMuted.color() to NovaColorToken.textSecondary.color()
        else -> NovaColorToken.statusDangerBg.color() to NovaColorToken.statusDangerInk.color()
    }
    val small = compact || inPopup
    Row(modifier.then(if (compact) Modifier else Modifier.fillMaxWidth())
        .heightIn(min = if (compact) 44.dp else if (inPopup) 46.dp else 52.dp)
        .clip(CircleShape).background(fill, CircleShape)
        .novaPress(enabled = active, onClick = onClick)
        .semantics(mergeDescendants = true) {
            contentDescription = label
            if (loading) stateDescription = loadingDescription
        }
        .padding(horizontal = if (small) 12.dp else 18.dp, vertical = if (compact) 8.dp else if (inPopup) 10.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
        if (loading) NovaSpinner(ink)
        else if (symbol != null) NovaIcon(symbol, if (compact) 14.dp else if (inPopup) 16.dp else 18.dp, tint = ink)
        NovaText(label, style = if (small) NovaTypeToken.buttonSm else NovaTypeToken.button, color = ink,
            textAlign = TextAlign.Center, maxLines = if (small) 2 else Int.MAX_VALUE)
    }
}

/** Synthetic-only gallery. Not connected to application routes, Auth, analytics or services. */
@Composable
internal fun NovaComponentGallery() {
    var taps by remember { mutableIntStateOf(0) }
    Column(Modifier.fillMaxSize().background(NovaColorToken.canvas.color()).verticalScroll(rememberScrollState())
        .padding(NovaDimensionToken.spaceScreenX.value.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaText("İSG Adası · Tasarım laboratuvarı", style = NovaTypeToken.screenTitle)
        NovaText("Sentetik örnekler — canlı kayıt içermez", style = NovaTypeToken.metaQuiet)
        NovaCard(Modifier.fillMaxWidth()) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaText("Örnek çalışma alanı", style = NovaTypeToken.cardTitle)
                NovaText("Uzun açıklamalar ve büyük metin boyutları için kart yüksekliği içeriğe göre büyür.")
                NovaStatusPill("İşlem tamamlandı", NovaStatus.Success)
                NovaStatusPill("İnceleme bekliyor", NovaStatus.Warning)
                NovaStatusPill("İşlem tamamlanamadı", NovaStatus.Danger)
                NovaStatusPill("Bilgilendirme", NovaStatus.Info)
                NovaStatusPill("Henüz kayıt yok", NovaStatus.Neutral)
            }
        }
        NovaButton("Örnek eylem ($taps)", { taps++ })
        NovaButton("İkincil eylem", {}, variant = NovaButtonVariant.Surface)
        NovaButton("İşlem sürüyor", {}, loading = true)
        NovaButton("Kullanılamıyor", {}, enabled = false)
    }
}

@Preview(name = "Light", showBackground = true)
@Composable private fun NovaLightPreview() = NovaTheme(false) { NovaComponentGallery() }
@Preview(name = "Dark", showBackground = true)
@Composable private fun NovaDarkPreview() = NovaTheme(true) { NovaComponentGallery() }
@Preview(name = "Large text", fontScale = 2f, widthDp = 320)
@Composable private fun NovaLargeTextPreview() = NovaTheme(false) { NovaComponentGallery() }
