package com.riskdetectedan.feature.onboarding.nova

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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.auth.IsgPasswordRules
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.isg.novaPress
import com.riskdetectedan.core.designsystem.isg.rememberNovaHaptics
import com.riskdetectedan.core.designsystem.isg.rememberNovaReduceMotion
import com.riskdetectedan.feature.onboarding.R

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
internal fun NovaOBEmailFormScreen(controller: NovaOnboardingController) {
    val focus = LocalFocusManager.current
    val haptics = rememberNovaHaptics()
    val hasError = controller.authError.isNotEmpty()
    ObFittedScroll(PaddingValues(start = 24.dp, end = 24.dp, top = obPadTop(70f), bottom = obPadBottom(34f)), 18.dp,
        Modifier.background(NovaOB.surface)) {
            ObBackButton(Modifier.offset(x = (-12).dp)) { controller.go(NovaOBScreen.Signup) }
            Image(painterResource(R.drawable.nova_ob_email_art), null, Modifier.size(124.dp).align(Alignment.CenterHorizontally)
                .offset(y = (-10).dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ObText("Mail ile hesap oluştur", 27f, weight = 700, lineHeight = 1.2f, tracking = -0.3f)
                ObText("Adresini doğrulamak için 6 haneli bir kod göndereceğiz.", 15.5f, color = NovaOB.muted, lineHeight = 1.45f)
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ObField(controller.email, { controller.email = it }, "E-posta adresin", leadingIcon = NovaOB.MAIL,
                    keyboardType = KeyboardType.Email, errorBorder = hasError && !NovaOBAuth.isValidEmail(controller.email))
                ObField(controller.password, { controller.password = it }, "Parola oluştur", leadingIcon = NovaOB.LOCK,
                    keyboardType = KeyboardType.Password, secure = !controller.showPassword,
                    errorBorder = hasError && !IsgPasswordRules.evaluate(controller.password).valid) {
                    ObText(if (controller.showPassword) "Gizle" else "Göster", 14f,
                        Modifier.padding(end = 8.dp).novaPress { controller.showPassword = !controller.showPassword }
                            .padding(horizontal = 12.dp, vertical = 12.dp))
                }
                ObPasswordStrength(controller.password)
                ObText("En az 8 karakter; büyük harf, küçük harf ve rakam içermeli.", 13f, color = NovaOB.muted, lineHeight = 1.4f)
                if (hasError) ObErrorNote(controller.authError)
                Row(Modifier.fillMaxWidth().novaPress(scale = 1f) { controller.marketing = !controller.marketing }.padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    val shape = RoundedCornerShape(7.dp)
                    Box(Modifier.padding(top = 1.dp).size(24.dp).clip(shape).background(if (controller.marketing) NovaOB.ink else NovaOB.surface)
                        .border(1.5.dp, if (controller.marketing) NovaOB.ink else NovaOB.line2, shape), contentAlignment = Alignment.Center) {
                        if (controller.marketing) ObIcon(NovaOB.CHECK, 13f, Color.White, lineWidth = 2.2f, viewBox = 14f)
                    }
                    ObText("İSGADA güncellemeleri ve bilgilendirmelerini e-posta ile almak istiyorum. (İsteğe bağlı)", 13.5f,
                        Modifier.weight(1f), color = NovaOB.muted, lineHeight = 1.4f)
                }
            }
            Spacer(Modifier.weight(1f))
            ObPrimaryButton(if (controller.busy) "İşleniyor…" else "Hesap oluştur", enabled = !controller.busy, showsArrow = true) {
                focus.clearFocus()
                controller.submitSignup(onFailure = haptics::failure)
            }
    }
}

private class ObPasswordRule(val ok: Boolean, val path: String)

/** Four-bar meter plus the rule chips from the prototype. */
@Composable
internal fun ObPasswordStrength(password: String) {
    val rules = listOf(
        ObPasswordRule(password.length >= 8, "M4 12h16"),
        ObPasswordRule(Regex("[a-zçğıöşü]").containsMatchIn(password) && Regex("[A-ZÇĞİÖŞÜ]").containsMatchIn(password),
            "M5 18L9.5 6l4.5 12M6.8 14h5.4M17 18v-6a2.6 2.6 0 10-2.6 2.6"),
        ObPasswordRule(Regex("\\d").containsMatchIn(password), "M7 8.5L10 6.5V18M14 9a3 3 0 115.6 1.6L14 18h6"),
        ObPasswordRule(Regex("[^A-Za-z0-9ÇĞİÖŞÜçğıöşü]").containsMatchIn(password), "M12 4.5v15M4.5 12h15M7 7l10 10M17 7L7 17"),
    )
    val score = rules.count { it.ok }
    val (label, color) = when (score) {
        0 -> if (password.isEmpty()) "Parola gücü" to NovaOB.muted2 else "Çok zayıf" to Color(0xFFB4564C)
        1 -> "Zayıf" to Color(0xFFB4564C)
        2 -> "Orta" to Color(0xFFC08A3E)
        3 -> "Güçlü" to NovaOB.ink
        else -> "Çok güçlü" to NovaOB.ink
    }
    Column(Modifier.padding(vertical = 2.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            repeat(4) { index ->
                val bar by animateColorAsState(if (index < score) color else NovaOB.line, tween(260), label = "ob-strength")
                Box(Modifier.weight(1f).height(5.dp).clip(CircleShape).background(bar))
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                ObIcon("M12 3l7 3v5.5c0 4.3-2.9 7.7-7 9.5-4.1-1.8-7-5.2-7-9.5V6z|M8.8 12.2l2.3 2.3 4.1-4.5", 16f, color, lineWidth = 1.9f)
                ObText(label, 13f, weight = 600, color = color)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                rules.forEach { rule ->
                    Box(Modifier.size(26.dp).clip(CircleShape).background(if (rule.ok) Color(0xFFF0F0F0) else Color(0xFFF2F2F2)),
                        contentAlignment = Alignment.Center) {
                        ObIcon(rule.path, 14f, if (rule.ok) NovaOB.ink else Color(0xFFADADAD), lineWidth = 2f)
                    }
                }
            }
        }
    }
}

// MARK: - Doğrulama kodu

@Composable
internal fun NovaOBOtpScreen(controller: NovaOnboardingController) {
    val haptics = rememberNovaHaptics()
    val address = controller.email.trim()
    ObFittedScroll(PaddingValues(start = 24.dp, end = 24.dp, top = obPadTop(70f), bottom = obPadBottom(34f)), 18.dp,
        Modifier.background(NovaOB.surface)) {
            ObBackButton(Modifier.offset(x = (-12).dp)) { controller.go(NovaOBScreen.EmailForm) }
            Image(painterResource(R.drawable.nova_ob_otp_art), null, Modifier.size(130.dp).align(Alignment.CenterHorizontally)
                .offset(y = (-12).dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ObText("Kodu gir", 27f, weight = 700, tracking = -0.3f)
                ObText(if (address.isEmpty()) "Kodu e-posta adresine gönderdik." else "Kodu $address adresine gönderdik.", 15.5f,
                    color = NovaOB.muted, lineHeight = 1.45f)
            }
            ObCodeField(controller.otpCode, { controller.otpCode = it },
                when {
                    controller.otpError.isNotEmpty() -> ObCodeState.Invalid
                    controller.otpVerified -> ObCodeState.Verified
                    else -> ObCodeState.Idle
                }) { code -> controller.verifyOtp(code, onSuccess = haptics::success, onFailure = haptics::failure) }
            if (controller.otpError.isNotEmpty()) ObErrorNote(controller.otpError)
            if (controller.otpVerified) ObInfoNote("Kod doğrulandı, yönlendiriliyorsun…", NovaOB.DONE_CIRCLE)
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.height(40.dp).clip(CircleShape).background(NovaOB.fill).novaPress(onClick = controller::resendCode)
                    .padding(horizontal = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    ObIcon(NovaOB.RESEND, 16f, NovaOB.ink, lineWidth = 1.9f)
                    ObText("Kodu yeniden gönder", 14.5f, weight = 600)
                }
                if (controller.resendNote) ObText("Yeni kod gönderildi.", 13.5f)
            }
            Spacer(Modifier.weight(1f))
    }
}

internal enum class ObCodeState { Idle, Invalid, Verified }

/**
 * Six single-digit boxes that behave like one field: paste fills them all, backspace walks back,
 * and a full code fires [onComplete].
 */
@Composable
internal fun ObCodeField(code: String, onCodeChange: (String) -> Unit, state: ObCodeState, onComplete: (String) -> Unit) {
    val requester = remember { FocusRequester() }
    LaunchedEffect(Unit) { requester.requestFocus() }
    BasicTextField(code, { value ->
        val digits = value.filter(Char::isDigit).take(6)
        onCodeChange(digits)
        if (digits.length == 6 && digits != code) onComplete(digits)
    }, Modifier.fillMaxWidth().focusRequester(requester), singleLine = true, cursorBrush = SolidColor(Color.Transparent),
        textStyle = obStyle(1f, color = Color.Transparent),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
        decorationBox = { inner ->
            Box {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    repeat(6) { index ->
                        val digit = code.getOrNull(index)?.toString().orEmpty()
                        val shape = RoundedCornerShape(14.dp)
                        val border = when (state) {
                            ObCodeState.Invalid -> NovaOB.errorBorder
                            ObCodeState.Verified -> NovaOB.ink
                            ObCodeState.Idle -> if (digit.isEmpty()) NovaOB.line2 else NovaOB.ink
                        }
                        val background = when (state) {
                            ObCodeState.Invalid -> Color(0xFFFDF3F2)
                            ObCodeState.Verified -> Color(0xFFF5F5F5)
                            ObCodeState.Idle -> NovaOB.surface
                        }
                        Box(Modifier.weight(1f).height(62.dp).clip(shape).background(background).border(1.5.dp, border, shape),
                            contentAlignment = Alignment.Center) {
                            ObText(digit, 24f, weight = 700)
                        }
                    }
                }
                Box(Modifier.size(1.dp)) { inner() }
            }
        })
}
