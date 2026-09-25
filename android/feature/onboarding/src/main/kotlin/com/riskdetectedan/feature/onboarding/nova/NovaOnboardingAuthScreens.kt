package com.riskdetectedan.feature.onboarding.nova

import android.content.Context
import android.graphics.Rect
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.riskdetectedan.core.data.auth.IsgPasswordRules
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.isg.novaPress
import com.riskdetectedan.core.designsystem.isg.rememberNovaHaptics
import com.riskdetectedan.core.designsystem.isg.rememberNovaReduceMotion
import com.riskdetectedan.feature.onboarding.R
import kotlinx.coroutines.delay

// MARK: - Shared auth chrome

internal object NovaOBBrandIcon {
    const val apple = "M17.05 12.04c-.03-2.6 2.12-3.85 2.22-3.91-1.21-1.77-3.09-2.01-3.76-2.04-1.6-.13-3.12.93-3.93.93-.81 0-2.06-.91-3.39-.88-1.74.03-3.35 1.01-4.25 2.57-1.81 3.15-.46 7.81 1.3 10.37.86 1.25 1.89 2.65 3.24 2.6 1.3-.05 1.79-.84 3.36-.84 1.57 0 2.01.84 3.38.82 1.39-.02 2.27-1.27 3.12-2.53.98-1.45 1.38-2.85 1.4-2.92-.03-.01-2.69-1.03-2.72-4.09zM14.7 4.2c.71-.86 1.19-2.06 1.06-3.25-1.05.04-2.32.7-3.06 1.56-.66.76-1.24 1.98-1.09 3.15 1.17.09 2.38-.6 3.09-1.46z"
}

/** Apple / Google buttons, identical on the signup and login surfaces. */
@Composable
internal fun ObProviderButtons(onApple: () -> Unit, onGoogle: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth().height(54.dp).clip(shape).background(NovaOB.ink).novaPress(onClick = onApple),
            horizontalArrangement = Arrangement.spacedBy(9.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            ObIcon(NovaOBBrandIcon.apple, 19f, Color.White, lineWidth = 0f, modifier = Modifier.offset(y = (-2).dp), filled = true)
            ObText("Apple ile devam et", 17f, weight = 500, color = Color.White)
        }
        Row(Modifier.fillMaxWidth().height(54.dp).clip(shape).background(NovaOB.surface).border(1.dp, Color(0xFFDADCE0), shape)
            .novaPress(onClick = onGoogle),
            horizontalArrangement = Arrangement.spacedBy(9.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            ObGoogleMark()
            ObText("Google ile devam et", 17f, weight = 500)
        }
    }
}

private val googleParts = listOf(
    "M23.52 12.27c0-.85-.08-1.67-.22-2.45H12v4.64h6.44c-.28 1.5-1.13 2.77-2.4 3.62v3.01h3.88c2.27-2.09 3.6-5.17 3.6-8.82z" to Color(0xFF4285F4),
    "M12 24c3.24 0 5.96-1.08 7.95-2.91l-3.88-3.01c-1.08.72-2.45 1.15-4.07 1.15-3.13 0-5.78-2.11-6.72-4.96H1.29v3.12C3.26 21.3 7.31 24 12 24z" to Color(0xFF34A853),
    "M5.28 14.27A7.2 7.2 0 014.9 12c0-.79.14-1.56.38-2.27V6.61H1.29A11.98 11.98 0 000 12c0 1.94.46 3.77 1.29 5.39l3.99-3.12z" to Color(0xFFFBBC05),
    "M12 4.75c1.77 0 3.35.61 4.6 1.8l3.44-3.44C17.95 1.19 15.24 0 12 0 7.31 0 3.26 2.7 1.29 6.61l3.99 3.12C6.22 6.88 8.87 4.75 12 4.75z" to Color(0xFFEA4335),
)

/** The four-colour Google glyph, drawn as its official quadrant paths. */
@Composable
private fun ObGoogleMark() {
    val paths = remember { googleParts.map { (d, color) -> ObSvgPath.parse(d) to color } }
    Canvas(Modifier.size(19.dp)) {
        val factor = size.width / 24f
        scale(factor, factor, pivot = androidx.compose.ui.geometry.Offset.Zero) { paths.forEach { (path, color) -> drawPath(path, color) } }
    }
}

/** Padlock whose shackle lifts on a loop (`isgLock`); Reduce Motion keeps it closed. */
@Composable
internal fun ObAnimatedLock(tint: Color = Color.White, bodyColor: Color = Color.White, keyholeColor: Color = NovaOB.ink, size: Float = 21f) {
    val reduceMotion = rememberNovaReduceMotion()
    val phase by rememberInfiniteTransition(label = "ob-lock").animateFloat(0f, 1f,
        infiniteRepeatable(tween(2_200, easing = LinearEasing), RepeatMode.Restart), label = "ob-lock-phase")
    val p = if (reduceMotion) 0f else phase
    val angle = when {
        p < 0.26f -> 0f
        p < 0.46f -> -30f * ((p - 0.26f) / 0.2f)
        p < 0.74f -> -30f
        p < 0.94f -> -30f * (1 - (p - 0.74f) / 0.2f)
        else -> 0f
    }
    val lift = if (p in 0.26f..0.94f) -2f else 0f
    val unit = size / 24f
    Box(Modifier.size(size.dp), contentAlignment = Alignment.Center) {
        ObIcon("M8.1 11.4V8.5a3.9 3.9 0 017.8 0v2.9", size, tint, lineWidth = 2f, modifier = Modifier.graphicsLayer {
            rotationZ = angle
            transformOrigin = TransformOrigin(1f, 1f)
            translationY = lift * density
        })
        Box(Modifier.offset(y = (4f * unit).dp).size((14.8f * unit).dp, (9.6f * unit).dp).clip(RoundedCornerShape((2.6f * unit).dp))
            .background(bodyColor))
        Box(Modifier.offset(y = (4f * unit).dp).size((3f * unit).dp).clip(CircleShape).background(keyholeColor))
    }
}

@Composable
internal fun ObDivider(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f).height(1.dp).background(NovaOB.line))
        ObText(text, 13f, color = NovaOB.muted)
        Box(Modifier.weight(1f).height(1.dp).background(NovaOB.line))
    }
}

/** Terms + privacy line that opens the app's real legal documents. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ObLegalLine(prefix: String, align: TextAlign = TextAlign.Start) {
    val context = LocalContext.current
    var document by remember { mutableStateOf<String?>(null) }
    val base = obStyle(12.5f, 300, NovaOB.muted, lineHeight = 1.45f)
    val linkStyle = TextLinkStyles(SpanStyle(color = NovaOB.ink))
    Text(buildAnnotatedString {
        append("$prefix ")
        withLink(LinkAnnotation.Clickable("terms", linkStyle) { document = "terms" }) { append("Kullanım Koşulları") }
        append(" ve ")
        withLink(LinkAnnotation.Clickable("privacy", linkStyle) { document = "privacy" }) { append("Gizlilik Bildirimi") }
        append("’ni kabul edersin.")
    }, Modifier.fillMaxWidth(), style = base, textAlign = align)
    val kind = document
    if (kind != null) {
        var documents by remember { mutableStateOf<List<RdLegalDocument>>(emptyList()) }
        LaunchedEffect(Unit) {
            documents = LegalDocumentAssets.load(context).map { RdLegalDocument(kind = it.kind, title = it.title, text = it.text) }
        }
        ModalBottomSheet(onDismissRequest = { document = null }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
            RdLegalDocumentSheet(documents = documents, initialKind = kind, onClose = { document = null })
        }
    }
}

// MARK: - Hesap oluştur

@Composable
internal fun NovaOBSignupScreen(controller: NovaOnboardingController, onLogin: () -> Unit) {
    val context = LocalContext.current
    val name = controller.answers.name.trim()
    ObFittedScroll(PaddingValues(start = 24.dp, end = 24.dp, top = obPadTop(70f), bottom = obPadBottom(34f)), 18.dp,
        Modifier.background(NovaOB.surface)) {
            ObBackButton(Modifier.offset(x = (-12).dp)) { controller.toCard() }
            Image(painterResource(R.drawable.nova_ob_signup_art), null, Modifier.size(148.dp).align(Alignment.CenterHorizontally)
                .offset(y = (-6).dp))
            ObText("Şimdi hesabına bağlayalım.", 27f, weight = 700, lineHeight = 1.2f, tracking = -0.3f)
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(NovaOB.fill).padding(horizontal = 14.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(38.dp).clip(CircleShape).background(NovaOB.ink), contentAlignment = Alignment.Center) { ObAnimatedLock() }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    ObText(if (name.isEmpty()) "Yanıtların güvende." else "$name, yanıtların güvende.", 15.5f, weight = 600)
                    ObText("Hesabını oluşturduğun anda profilin kalıcı olarak kaydedilir.", 13f, color = NovaOB.muted, lineHeight = 1.4f)
                }
            }
            ObProviderButtons(onApple = controller::runApple, onGoogle = { controller.runGoogle(context) })
            ObDivider("veya")
            val shape = RoundedCornerShape(14.dp)
            Row(Modifier.fillMaxWidth().height(54.dp).clip(shape).background(NovaOB.surface).border(1.5.dp, NovaOB.line2, shape)
                .novaPress { controller.go(NovaOBScreen.EmailForm) },
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                ObIcon(NovaOB.MAIL, 21f, NovaOB.ink, lineWidth = 1.7f)
                ObText("Mail ile devam et", 17f, weight = 500)
            }
            if (controller.authError.isNotEmpty()) ObErrorNote(controller.authError)
            Spacer(Modifier.weight(1f))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                ObLegalLine("Hesap oluşturarak")
                Box(Modifier.fillMaxWidth().height(44.dp).novaPress(onClick = onLogin), contentAlignment = Alignment.Center) {
                    ObText("Zaten hesabın var mı? Giriş yap", 15f, weight = 600)
                }
            }
    }
}

// MARK: - Mail ile kayıt

@Composable
internal fun NovaOBEmailFormScreen(controller: NovaOnboardingController, onLogin: () -> Unit) {
    val haptics = rememberNovaHaptics()
    ObSignupPage(
        email = controller.email, onEmail = { controller.email = it },
        password = controller.password, onPassword = { controller.password = it },
        showPassword = controller.showPassword, onShowPassword = { controller.showPassword = it },
        marketing = controller.marketing, onMarketing = { controller.marketing = it },
        error = controller.authError, busy = controller.busy,
        onBack = { controller.go(NovaOBScreen.Signup) },
        onLogin = onLogin,
        onSubmit = { controller.submitSignup(onFailure = haptics::failure) },
    )
}

/**
 * "Mail ile hesap oluştur": the one place a new password account starts, from the funnel and
 * from the login screen (iOS `NovaOBSignupPage`). The code page follows it. [marketing] is the
 * optional updates checkbox; the login screen leaves it out.
 */
@Composable
internal fun ObSignupPage(
    email: String, onEmail: (String) -> Unit,
    password: String, onPassword: (String) -> Unit,
    showPassword: Boolean, onShowPassword: (Boolean) -> Unit,
    marketing: Boolean? = null, onMarketing: (Boolean) -> Unit = {},
    error: String, busy: Boolean,
    onBack: () -> Unit, onLogin: () -> Unit, onSubmit: () -> Unit,
) {
    val focus = LocalFocusManager.current
    val hasError = error.isNotEmpty()
    ObFittedScroll(PaddingValues(start = 24.dp, end = 24.dp, top = obPadTop(70f), bottom = obPadBottom(34f)), 18.dp,
        Modifier.background(NovaOB.surface)) {
            ObBackButton(Modifier.offset(x = (-12).dp), onClick = onBack)
            Image(painterResource(R.drawable.nova_ob_email_art), null, Modifier.size(124.dp).align(Alignment.CenterHorizontally)
                .offset(y = (-10).dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ObText("Mail ile hesap oluştur", 27f, weight = 700, lineHeight = 1.2f, tracking = -0.3f)
                ObText("Adresini doğrulamak için 6 haneli bir kod göndereceğiz.", 15.5f, color = NovaOB.muted, lineHeight = 1.45f)
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ObField(email, onEmail, "E-posta adresin", leadingIcon = NovaOB.MAIL,
                    keyboardType = KeyboardType.Email, errorBorder = hasError && !NovaOBAuth.isValidEmail(email))
                ObNewPasswordField("Parola oluştur", password, onPassword, showPassword, onShowPassword, hasError)
                if (hasError) ObErrorNote(error)
                if (marketing != null) {
                    Row(Modifier.fillMaxWidth().novaPress(scale = 1f) { onMarketing(!marketing) }.padding(vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        val shape = RoundedCornerShape(7.dp)
                        Box(Modifier.padding(top = 1.dp).size(24.dp).clip(shape).background(if (marketing) NovaOB.ink else NovaOB.surface)
                            .border(1.5.dp, if (marketing) NovaOB.ink else NovaOB.line2, shape), contentAlignment = Alignment.Center) {
                            if (marketing) ObIcon(NovaOB.CHECK, 13f, Color.White, lineWidth = 2.2f, viewBox = 14f)
                        }
                        ObText("İSGADA güncellemeleri ve bilgilendirmelerini e-posta ile almak istiyorum. (İsteğe bağlı)", 13.5f,
                            Modifier.weight(1f), color = NovaOB.muted, lineHeight = 1.4f)
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            ObPrimaryButton(if (busy) "İşleniyor…" else "Hesap oluştur", enabled = !busy, showsArrow = true) {
                focus.clearFocus()
                onSubmit()
            }
            Box(Modifier.fillMaxWidth().height(40.dp).novaPress(onClick = onLogin), contentAlignment = Alignment.Center) {
                ObText("Zaten hesabın var mı? Giriş yap", 14.5f, weight = 600, color = NovaOB.muted)
            }
    }
}

/** A password being chosen, on signup and at the end of a reset (iOS `NovaOBNewPasswordField`). The
 * rules under it are checked as the user types: a met rule turns green, a missing one red, and the
 * field turns green once all are met. While the field is focused the rules are kept above the
 * keyboard ([ObResizesForKeyboard] makes the page end there). [showsError]: a refused submit, which marks missing rules
 * red even with nothing typed. */
@Composable
internal fun ObNewPasswordField(
    placeholder: String, password: String, onPassword: (String) -> Unit,
    showPassword: Boolean, onShowPassword: (Boolean) -> Unit, showsError: Boolean,
) {
    val rulesInView = remember { BringIntoViewRequester() }
    var focused by remember { mutableStateOf(false) }
    // Follows the keyboard as it opens; the last run, once it has settled, leaves the rules in sight.
    val keyboard = WindowInsets.ime.getBottom(LocalDensity.current)
    LaunchedEffect(focused, keyboard) {
        if (focused && keyboard > 0) {
            delay(60)
            rulesInView.bringIntoView()
        }
    }
    val state = when {
        IsgPasswordRules.evaluate(password).valid -> NovaOB.successBorder
        password.isNotEmpty() || showsError -> NovaOB.errorBorder
        else -> null
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ObField(password, onPassword, placeholder,
            Modifier.onFocusChanged { focused = it.isFocused },
            leadingIcon = NovaOB.LOCK, keyboardType = KeyboardType.Password, secure = !showPassword,
            focusBorder = state ?: NovaOB.ink, idleBorder = state ?: NovaOB.line) {
            ObText(if (showPassword) "Gizle" else "Göster", 14f,
                Modifier.padding(end = 8.dp).novaPress { onShowPassword(!showPassword) }
                    .padding(horizontal = 12.dp, vertical = 12.dp))
        }
        ObPasswordRules(password, showsError, Modifier.bringIntoViewRequester(rulesInView).padding(bottom = 12.dp))
    }
}

/** The four rules of [IsgPasswordRules], two per row (iOS `NovaOBPasswordRules`). Neutral while nothing is typed. */
@Composable
internal fun ObPasswordRules(password: String, flagged: Boolean, modifier: Modifier = Modifier) {
    val rules = IsgPasswordRules.evaluate(password)
    val marked = password.isNotEmpty() || flagged
    Column(modifier, verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            ObPasswordRule(rules.minimumCharacters && rules.maximumBytes,
                if (rules.maximumBytes) "En az 8 karakter" else "En fazla 72 karakter", marked, Modifier.weight(1f))
            ObPasswordRule(rules.uppercase, "Büyük harf", marked, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            ObPasswordRule(rules.lowercase, "Küçük harf", marked, Modifier.weight(1f))
            ObPasswordRule(rules.digit, "Rakam", marked, Modifier.weight(1f))
        }
    }
}

@Composable
private fun ObPasswordRule(met: Boolean, title: String, marked: Boolean, modifier: Modifier) {
    val color by animateColorAsState(when {
        met -> NovaOB.successInk
        marked -> NovaOB.errorInk
        else -> NovaOB.muted2
    }, tween(200), label = "ob-password-rule")
    Row(modifier.semantics(mergeDescendants = true) { stateDescription = if (met) "tamam" else "eksik" },
        horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(17.dp).clip(CircleShape).then(
            when {
                met -> Modifier.background(color)
                else -> Modifier.border(1.5.dp, if (marked) color else NovaOB.line2, CircleShape)
            }), contentAlignment = Alignment.Center) {
            if (met) ObIcon("M7 12.4l3.2 3.2L17 8.8", 12f, Color.White, lineWidth = 2.6f)
            else if (marked) ObIcon("M8.5 8.5l7 7|M15.5 8.5l-7 7", 10f, color, lineWidth = 2.4f)
        }
        ObText(title, 13.5f, weight = 500, color = color)
    }
}

// MARK: - Şifre sıfırlama

/** "Şifreni belirle", step one: the address the 6-digit code goes to (iOS `NovaOBResetEmailPage`). It
 * serves a forgotten password and an account that never had one (everyone signed in with mailed codes
 * before passwords). The code page follows, then [ObNewPasswordPage]. */
@Composable
internal fun ObResetEmailPage(
    email: String, onEmail: (String) -> Unit, error: String, busy: Boolean,
    onBack: () -> Unit, onSubmit: () -> Unit,
) {
    val focus = LocalFocusManager.current
    val hasError = error.isNotEmpty()
    ObFittedScroll(PaddingValues(start = 24.dp, end = 24.dp, top = obPadTop(70f), bottom = obPadBottom(34f)), 18.dp,
        Modifier.background(NovaOB.surface)) {
            ObBackButton(Modifier.offset(x = (-12).dp), onClick = onBack)
            Image(painterResource(R.drawable.nova_ob_email_art), null, Modifier.size(124.dp).align(Alignment.CenterHorizontally)
                .offset(y = (-10).dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ObText("Şifreni belirle", 27f, weight = 700, lineHeight = 1.2f, tracking = -0.3f)
                ObText("Mailine 6 haneli bir kod gönderelim; kodu girince yeni şifreni belirlersin.", 15.5f,
                    color = NovaOB.muted, lineHeight = 1.45f)
            }
            ObField(email, onEmail, "E-posta adresin", leadingIcon = NovaOB.MAIL,
                keyboardType = KeyboardType.Email, errorBorder = hasError && !NovaOBAuth.isValidEmail(email))
            if (hasError) ObErrorNote(error)
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(NovaOB.fill3)
                .padding(horizontal = 14.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                ObIcon("circle:12,12,9.2|M12 11v5.2|M12 7.8v.1", 15f, NovaOB.muted2, lineWidth = 1.8f, modifier = Modifier.padding(top = 1.dp))
                ObText("Apple veya Google ile kaydolduysan şifre gerekmez; o butonla giriş yap.", 12.5f, Modifier.weight(1f),
                    color = NovaOB.muted, lineHeight = 1.4f)
            }
            Spacer(Modifier.weight(1f))
            ObPrimaryButton(if (busy) "Gönderiliyor…" else "Kod gönder", enabled = !busy, showsArrow = true) {
                focus.clearFocus()
                onSubmit()
            }
            Box(Modifier.fillMaxWidth().height(40.dp).novaPress(onClick = onBack), contentAlignment = Alignment.Center) {
                ObText("Girişe dön", 14.5f, weight = 600, color = NovaOB.muted)
            }
    }
}

/** Reset, last step: the new password, once the code from the reset mail is verified (iOS `NovaOBNewPasswordPage`). */
@Composable
internal fun ObNewPasswordPage(
    password: String, onPassword: (String) -> Unit,
    showPassword: Boolean, onShowPassword: (Boolean) -> Unit,
    error: String, busy: Boolean, onBack: () -> Unit, onSubmit: () -> Unit,
) {
    val focus = LocalFocusManager.current
    val hasError = error.isNotEmpty()
    ObFittedScroll(PaddingValues(start = 24.dp, end = 24.dp, top = obPadTop(70f), bottom = obPadBottom(34f)), 18.dp,
        Modifier.background(NovaOB.surface)) {
            ObBackButton(Modifier.offset(x = (-12).dp), onClick = onBack)
            Image(painterResource(R.drawable.nova_ob_email_art), null, Modifier.size(124.dp).align(Alignment.CenterHorizontally)
                .offset(y = (-10).dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ObText("Yeni şifreni belirle", 27f, weight = 700, lineHeight = 1.2f, tracking = -0.3f)
                ObText("Kod doğrulandı. Bundan sonra bu şifreyle giriş yapacaksın.", 15.5f, color = NovaOB.muted, lineHeight = 1.45f)
            }
            ObNewPasswordField("Yeni şifre", password, onPassword, showPassword, onShowPassword, hasError)
            if (hasError) ObErrorNote(error)
            Spacer(Modifier.weight(1f))
            ObPrimaryButton(if (busy) "Kaydediliyor…" else "Şifreyi kaydet", enabled = !busy, showsArrow = true) {
                focus.clearFocus()
                onSubmit()
            }
    }
}

// MARK: - Doğrulama kodu

@Composable
internal fun NovaOBOtpScreen(controller: NovaOnboardingController) {
    val haptics = rememberNovaHaptics()
    ObCodePage(
        email = controller.email, digits = { controller.otpDigits }, onDigits = { controller.otpDigits = it },
        error = controller.otpError, retryable = controller.otpRetryable, checking = controller.busy,
        verified = controller.otpVerified,
        verifiedNote = "Kod doğrulandı, yönlendiriliyorsun…", resendNote = controller.resendNote,
        onBack = { controller.go(NovaOBScreen.EmailForm) },
        onEdit = controller::clearOtpError,
        onComplete = { code -> controller.verifyOtp(code, onSuccess = haptics::success, onFailure = haptics::failure) },
        onResend = controller::resendCode,
    )
}

/** "Kodu gir": a mailed code as its own page (iOS `NovaOBCodePage`). The funnel and the login screen use
 * it for the signup code, the login screen also for the reset code. A full code is checked on its own;
 * a right one turns the boxes green and the owner moves on, a wrong one turns them red with the digits
 * kept for fixing, and an unreachable server ([retryable]) offers "Tekrar dene" instead. */
@Composable
internal fun ObCodePage(
    email: String, digits: () -> List<String>, onDigits: (List<String>) -> Unit,
    error: String, retryable: Boolean = false, checking: Boolean = false,
    verified: Boolean, verifiedNote: String, resendNote: String,
    onBack: () -> Unit, onEdit: () -> Unit = {}, onComplete: (String) -> Unit, onResend: () -> Unit,
) {
    val address = email.trim()
    val helpInView = remember { BringIntoViewRequester() }
    // The keyboard stays up after a refused code; keep the warning and resend in sight.
    LaunchedEffect(error) {
        if (error.isNotEmpty()) {
            delay(60)
            helpInView.bringIntoView()
        }
    }
    ObFittedScroll(PaddingValues(start = 24.dp, end = 24.dp, top = obPadTop(70f), bottom = obPadBottom(34f)), 18.dp,
        Modifier.background(NovaOB.surface)) {
            ObBackButton(Modifier.offset(x = (-12).dp), onClick = onBack)
            Image(painterResource(R.drawable.nova_ob_otp_art), null, Modifier.size(130.dp).align(Alignment.CenterHorizontally)
                .offset(y = (-12).dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ObText("Kodu gir", 27f, weight = 700, tracking = -0.3f)
                ObText(if (address.isEmpty()) "Kodu e-posta adresine gönderdik." else "Kodu $address adresine gönderdik.", 15.5f,
                    color = NovaOB.muted, lineHeight = 1.45f)
            }
            ObCodeField(digits, onDigits,
                when {
                    verified -> ObCodeState.Verified
                    error.isNotEmpty() && !retryable -> ObCodeState.Invalid
                    else -> ObCodeState.Idle
                }, onEdit, onComplete)
            Column(Modifier.bringIntoViewRequester(helpInView).padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                if (checking) {
                    Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
                        ObSpinner(15f)
                        ObText("Kod kontrol ediliyor…", 13.5f, color = NovaOB.muted)
                    }
                }
                if (error.isNotEmpty()) {
                    ObErrorNote(error)
                    if (retryable) {
                        Box(Modifier.height(40.dp).clip(CircleShape).background(NovaOB.fill)
                            .novaPress { onComplete(digits().joinToString("")) }.padding(horizontal = 14.dp),
                            contentAlignment = Alignment.Center) {
                            ObText("Tekrar dene", 14.5f, weight = 600)
                        }
                    }
                }
                if (verified) ObInfoNote(verifiedNote, NovaOB.DONE_CIRCLE)
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Row(Modifier.height(40.dp).clip(CircleShape).background(NovaOB.fill).novaPress(onClick = onResend)
                        .padding(horizontal = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        ObIcon(NovaOB.RESEND, 16f, NovaOB.ink, lineWidth = 1.9f)
                        ObText("Kodu yeniden gönder", 14.5f, weight = 600)
                    }
                    if (resendNote.isNotEmpty()) ObText(resendNote, 13.5f, Modifier.weight(1f))
                }
                ObText("Kod gelmediyse spam klasörünü kontrol et.", 13f, color = NovaOB.muted2)
            }
            Spacer(Modifier.weight(1f))
    }
}

internal enum class ObCodeState { Idle, Invalid, Verified }

/**
 * Six digit boxes backed by [ObCodeKeysView], a view that holds no text and reports every key (iOS
 * `NovaOBCodeField`), so the boxes own the digits and which one is selected. Typing fills the
 * selected box and moves on; backspace clears it, or the nearest filled one before it; a tap selects
 * any box, so one wrong digit of a refused code can be replaced; paste and keyboard suggestions fill
 * all six. A full code fires [onComplete] after every change, so a fixed digit is checked again
 * without a button. [digits] is read live, not captured: keys can arrive faster than a
 * recomposition, and each one must see the digit before it. (A hidden text field reset after every
 * key lost digits the same way.)
 */
@Composable
internal fun ObCodeField(
    digits: () -> List<String>, onDigits: (List<String>) -> Unit, state: ObCodeState,
    onEdit: () -> Unit, onComplete: (String) -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    var cursor by remember { mutableIntStateOf(digits().indexOfFirst { it.isEmpty() }.let { if (it < 0) 5 else it }) }
    var keys by remember { mutableStateOf<ObCodeKeysView?>(null) }
    val verified = state == ObCodeState.Verified
    val shown = digits()
    val allEmpty = shown.all { it.isEmpty() }
    // A new code (resend) empties the boxes: start again at the first one, unless typing has
    // already begun by the time this runs.
    LaunchedEffect(allEmpty) { if (allEmpty && digits().all { it.isEmpty() }) cursor = 0 }

    fun commit(next: List<String>) {
        if (next == digits()) return
        onDigits(next)
        onEdit()
        if (next.all { it.isNotEmpty() }) onComplete(next.joinToString(""))
    }

    fun type(text: String) {
        val entered = text.filter(Char::isDigit)
        if (verified || entered.isEmpty()) return
        val next = digits().toMutableList()
        if (entered.length >= 6) {
            // Paste or a keyboard suggestion: the whole code.
            entered.take(6).forEachIndexed { index, digit -> next[index] = digit.toString() }
            cursor = 5
        } else {
            var index = cursor
            for (digit in entered) {
                next[index] = digit.toString()
                if (index == 5) break
                index += 1
            }
            cursor = index
        }
        commit(next)
    }

    // Clears the selected box, else the nearest filled one before it, else the last filled one:
    // holding backspace always ends with every box empty, wherever the selection was.
    fun backspace() {
        if (verified) return
        val next = digits().toMutableList()
        if (next[cursor].isEmpty()) {
            val filled = next.indices.filter { next[it].isNotEmpty() }
            cursor = filled.lastOrNull { it < cursor } ?: filled.lastOrNull() ?: return
        }
        next[cursor] = ""
        commit(next)
    }

    fun select(index: Int) {
        if (verified) return
        // A filled box can be replaced; past the first empty one there is nothing to edit yet.
        val now = digits()
        val firstEmpty = now.indexOfFirst { it.isEmpty() }
        cursor = if (now[index].isEmpty() && firstEmpty >= 0) firstEmpty else index
        keys?.showKeyboard()
    }

    Box {
        AndroidView(
            factory = { context ->
                ObCodeKeysView(context).also { view ->
                    view.onFocus = { focused = it }
                    keys = view
                    view.post { view.showKeyboard() }
                }
            },
            modifier = Modifier.size(1.dp).alpha(0f),
            update = { view ->
                view.onInsert = ::type
                view.onDelete = ::backspace
            },
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            repeat(6) { index ->
                val digit = shown.getOrNull(index).orEmpty()
                val selected = focused && index == cursor && !verified
                val shape = RoundedCornerShape(14.dp)
                val border = when (state) {
                    ObCodeState.Verified -> NovaOB.successBorder
                    ObCodeState.Invalid -> if (selected) NovaOB.errorInk else NovaOB.errorBorder
                    ObCodeState.Idle -> if (selected || digit.isNotEmpty()) NovaOB.ink else NovaOB.line2
                }
                val background = when (state) {
                    ObCodeState.Verified -> Color(0xFFEEF7F1)
                    ObCodeState.Invalid -> Color(0xFFFDF3F2)
                    ObCodeState.Idle -> if (selected && digit.isNotEmpty()) NovaOB.fill3 else NovaOB.surface
                }
                Box(Modifier.weight(1f).height(62.dp).clip(shape).background(background)
                    .border(if (selected) 2.2.dp else 1.5.dp, border, shape)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { select(index) },
                    contentAlignment = Alignment.Center) {
                    if (selected && digit.isEmpty()) Box(Modifier.size(2.dp, 26.dp).background(NovaOB.ink))
                    else ObText(digit, 24f, weight = 700)
                }
            }
        }
    }
}

/**
 * The keyboard side of [ObCodeField] (iOS `NovaOBCodeKeys`): a focusable view with a number-pad input
 * connection that never holds text. Every digit the keyboard commits and every backspace, from the soft
 * keyboard or a hardware one, is reported as it comes, so nothing can drift however fast keys arrive.
 */
internal class ObCodeKeysView(context: Context) : View(context) {
    var onInsert: (String) -> Unit = {}
    var onDelete: () -> Unit = {}
    var onFocus: (Boolean) -> Unit = {}

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        contentDescription = "Doğrulama kodu"
    }

    fun showKeyboard() {
        requestFocus()
        context.getSystemService(InputMethodManager::class.java)?.showSoftInput(this, 0)
    }

    override fun onFocusChanged(gainFocus: Boolean, direction: Int, previouslyFocusedRect: Rect?) {
        super.onFocusChanged(gainFocus, direction, previouslyFocusedRect)
        onFocus(gainFocus)
    }

    override fun onCheckIsTextEditor() = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_CLASS_NUMBER
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN
        return object : BaseInputConnection(this, false) {
            override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
                if (!text.isNullOrEmpty()) onInsert(text.toString())
                return true
            }

            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                repeat(beforeLength) { onDelete() }
                return true
            }

            override fun sendKeyEvent(event: KeyEvent): Boolean = handle(event) || super.sendKeyEvent(event)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean = handle(event) || super.onKeyDown(keyCode, event)

    private fun handle(event: KeyEvent): Boolean {
        val digit = event.unicodeChar.toChar().takeIf(Char::isDigit)
        if (event.keyCode != KeyEvent.KEYCODE_DEL && digit == null) return false
        if (event.action == KeyEvent.ACTION_DOWN) {
            if (digit != null) onInsert(digit.toString()) else onDelete()
        }
        return true
    }
}
