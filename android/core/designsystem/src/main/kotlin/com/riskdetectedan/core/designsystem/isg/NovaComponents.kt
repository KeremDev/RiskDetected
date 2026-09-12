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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.tooling.preview.Preview
import com.riskdetectedan.core.designsystem.R

private val NovaFontFamily = FontFamily(
    Font(R.font.plus_jakarta_sans_regular, FontWeight.Normal),
    Font(R.font.plus_jakarta_sans_medium, FontWeight.Medium),
    Font(R.font.plus_jakarta_sans_semibold, FontWeight.SemiBold),
    Font(R.font.plus_jakarta_sans_bold, FontWeight.Bold),
    Font(R.font.plus_jakarta_sans_extrabold, FontWeight.ExtraBold),
)
private val LocalNovaDark = staticCompositionLocalOf { false }

fun NovaRGBA.color() = Color(red / 255f, green / 255f, blue / 255f, alpha.toFloat())

@Composable
internal fun NovaColorToken.color() = rgba(LocalNovaDark.current).color()

fun NovaTypeToken.textStyle(): TextStyle = spec.let {
    TextStyle(fontFamily = NovaFontFamily, fontWeight = FontWeight(it.weight),
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
             color: Color = Color.Unspecified) {
    Text(text, modifier, color = if (color == Color.Unspecified) NovaColorToken.text.color() else color,
        style = style.textStyle())
}

@Composable
fun NovaCard(modifier: Modifier = Modifier, padding: Int = 11, border: Color = Color.Transparent,
             content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(NovaDimensionToken.radiusCard.value.dp)
    Surface(modifier.shadow(2.dp, shape), shape = shape, color = NovaColorToken.surface.color(),
        border = androidx.compose.foundation.BorderStroke(1.5.dp, border)) {
        Column(Modifier.padding(padding.dp), content = content)
    }
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
               loading: Boolean = false, loadingDescription: String = "İşlem sürüyor") {
    val palette = when (variant) {
        // Explicit accessibility adaptation; source white-on-green remains in the reference tokens.
        NovaButtonVariant.Primary -> NovaColorToken.accent.color() to Color(0xFF111111)
        NovaButtonVariant.Surface -> NovaColorToken.surface.color() to NovaColorToken.text.color()
        NovaButtonVariant.Muted -> NovaColorToken.surfaceMuted.color() to NovaColorToken.textSecondary.color()
        NovaButtonVariant.Danger -> NovaColorToken.statusDangerBg.color() to NovaColorToken.statusDangerInk.color()
    }
    val active = enabled && !loading
    val ink = if (active) palette.second else NovaColorToken.textSecondary.color()
    Button(onClick, modifier.fillMaxWidth().heightIn(min = 52.dp).semantics {
        if (loading) stateDescription = loadingDescription
    }, enabled = active, shape = CircleShape,
        contentPadding = PaddingValues(horizontal = 18.dp, vertical = 12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = palette.first, contentColor = ink,
            disabledContainerColor = NovaColorToken.surfaceMuted.color(), disabledContentColor = ink)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (loading) CircularProgressIndicator(Modifier.size(16.dp).clearAndSetSemantics {}, color = ink, strokeWidth = 2.dp)
            NovaText(label, style = NovaTypeToken.button, color = ink)
        }
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
