package com.riskdetectedan.feature.onboarding.nova

import android.content.Context
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.designsystem.isg.novaPress
import com.riskdetectedan.core.designsystem.isg.rememberNovaHaptics
import com.riskdetectedan.feature.onboarding.R
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale
import javax.inject.Inject

internal enum class NovaLoginPhase { Form, Sheet, Forgot, Done }

/**
 * `İSGADA Giriş.dc.html` — one surface for sign-in and sign-up (iOS `NovaLoginScreen`): providers
 * on top, mail below. A known address signs straight in; an unknown one opens the verification sheet.
 */
@HiltViewModel
class NovaLoginViewModel @Inject constructor(private val auth: NovaOBAuth) : ViewModel() {
    internal var phase by mutableStateOf(NovaLoginPhase.Form)
    internal var email by mutableStateOf("")
    internal var password by mutableStateOf("")
    internal var showPassword by mutableStateOf(false)
    internal var error by mutableStateOf("")
    internal var busy by mutableStateOf(false)
    internal var code by mutableStateOf("")
    internal var codeVerified by mutableStateOf(false)
    internal var resendNote by mutableStateOf("")
    internal var resetBusy by mutableStateOf(false)
    internal var resetSent by mutableStateOf(false)
    /** True once the account was created here rather than signed into. */
    internal var createdAccount by mutableStateOf(false)

    private val address get() = email.trim().lowercase(Locale.ROOT)

    internal fun openForm() { phase = NovaLoginPhase.Form; error = ""; resetSent = false; codeVerified = false }
    internal fun openForgot() { phase = NovaLoginPhase.Forgot; error = ""; resetSent = false }

    internal fun runApple() {
        if (busy) return
        busy = true
        error = ""
        viewModelScope.launch {
            // Success only means the Custom Tab opened; the session comes back through the deep
            // link and the app routes on it.
            val result = auth.appleSignIn()
            if (result is RdResult.Failure && !NovaOBAuth.isCancellation(result)) error = NovaOBAuth.message(result, "Apple ile giriş yapılamadı")
            busy = false
        }
    }

    internal fun runGoogle(activity: Context) {
        if (busy) return
        busy = true
        error = ""
        viewModelScope.launch {
            when (val result = auth.googleSignIn(activity)) {
                is RdResult.Success -> { createdAccount = false; phase = NovaLoginPhase.Done }
                is RdResult.Failure -> if (!NovaOBAuth.isCancellation(result)) error = NovaOBAuth.message(result, "Giriş yapılamadı")
            }
            busy = false
        }
    }

    /** Known address signs in; anything else gets a verification code (the prototype's registered/new split). */
    internal fun submitMail(onFailure: () -> Unit) {
        if (busy) return
        when {
            !NovaOBAuth.isValidEmail(address) -> { onFailure(); error = "Geçerli bir e-posta adresi yaz."; return }
            password.length < 6 -> { onFailure(); error = "Şifren en az 6 karakter olmalı."; return }
        }
        busy = true
        error = ""
        viewModelScope.launch {
            if (auth.signIn(address, password) is RdResult.Success) {
                createdAccount = false
                phase = NovaLoginPhase.Done
            } else {
                when (val sent = auth.sendCode(address)) {
                    is RdResult.Success -> { code = ""; codeVerified = false; phase = NovaLoginPhase.Sheet }
                    is RdResult.Failure -> error = NovaOBAuth.message(sent, "Doğrulama kodu gönderilemedi", "Kod gönderilemedi")
                }
            }
            busy = false
        }
    }

    internal fun verify(value: String, onSuccess: () -> Unit, onFailure: () -> Unit) {
        error = ""
        viewModelScope.launch {
            when (auth.verifyCode(address, value)) {
                is RdResult.Success -> {
                    onSuccess()
                    codeVerified = true
                    delay(900)
                    createdAccount = true
                    phase = NovaLoginPhase.Done
                }
                is RdResult.Failure -> {
                    onFailure()
                    codeVerified = false
                    code = ""
                    error = "Geçersiz kod. Kodu kontrol edip yeniden dene."
                }
            }
        }
    }

    internal fun resend() {
        viewModelScope.launch {
            resendNote = when (auth.sendCode(address)) {
                is RdResult.Success -> { code = ""; "Yeni kod gönderildi." }
                is RdResult.Failure -> "Kod gönderilemedi, tekrar dene."
            }
        }
    }

    internal fun submitReset() {
        if (resetBusy) return
        if (!NovaOBAuth.isValidEmail(address)) {
            error = "Geçerli bir e-posta adresi yaz."
            resetSent = false
            return
        }
        resetBusy = true
        error = ""
        resetSent = false
        viewModelScope.launch {
            when (val result = auth.recoverPassword(address)) {
                is RdResult.Success -> resetSent = true
                is RdResult.Failure -> error = NovaOBAuth.message(result, "Sıfırlama bağlantısı gönderilemedi", "Bağlantı gönderilemedi")
            }
            resetBusy = false
        }
    }
}

@Composable
fun NovaLoginScreen(model: NovaLoginViewModel = hiltViewModel()) {
    Box(Modifier.fillMaxSize().background(NovaOB.surface)) {
        AnimatedContent(if (model.phase == NovaLoginPhase.Sheet) NovaLoginPhase.Form else model.phase,
            transitionSpec = { fadeIn(tween(240)) togetherWith fadeOut(tween(240)) }, label = "nova-login") { phase ->
            when (phase) {
                NovaLoginPhase.Forgot -> NovaLoginForgot(model)
                NovaLoginPhase.Done -> NovaLoginDone(model.createdAccount)
                else -> NovaLoginForm(model)
            }
        }
        AnimatedVisibility(model.phase == NovaLoginPhase.Sheet, enter = fadeIn(tween(340)), exit = fadeOut(tween(240))) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.42f))
                .clickable(remember { MutableInteractionSource() }, null) { model.openForm() })
        }
        AnimatedVisibility(model.phase == NovaLoginPhase.Sheet, Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(tween(340, easing = CubicBezierEasing(0.2f, 0.85f, 0.25f, 1f))) { it },
            exit = slideOutVertically(tween(240)) { it }) {
            NovaLoginVerificationSheet(model)
        }
    }
}

@Composable
private fun NovaLoginForm(model: NovaLoginViewModel) {
    val context = LocalContext.current
    val focus = LocalFocusManager.current
    val haptics = rememberNovaHaptics()
    val logo = remember { Animatable(0f) }
    LaunchedEffect(Unit) { logo.animateTo(1f, tween(420, easing = CubicBezierEasing(0.2f, 0.8f, 0.25f, 1f))) }
    ObFittedScroll(PaddingValues(start = 24.dp, end = 24.dp, top = obPadTop(64f), bottom = obPadBottom(28f)), 16.dp) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Image(painterResource(R.drawable.nova_ob_logo), null, Modifier.padding(top = 28.dp, bottom = 56.dp).width(168.dp)
                .scale(0.7f + 0.3f * logo.value).alpha(logo.value))
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp)) {
                ObText("Hoş geldin", 28f, weight = 700, lineHeight = 1.15f, tracking = -0.5f)
                ObText("Giriş yap ya da saniyeler içinde hesabını oluştur. Ayrı bir kayıt adımı yok.", 15.5f, Modifier.widthIn(max = 290.dp),
                    color = NovaOB.muted, lineHeight = 1.45f, align = TextAlign.Center)
            }
        }
        Box(Modifier.padding(top = 4.dp)) {
            ObProviderButtons(onApple = model::runApple, onGoogle = { model.runGoogle(context) })
        }
        ObDivider("veya mail ile", Modifier.padding(vertical = 2.dp))
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            ObField(model.email, { model.email = it }, "E-posta adresin", leadingIcon = NovaOB.MAIL, keyboardType = KeyboardType.Email)
            ObField(model.password, { model.password = it }, "Şifren", leadingIcon = NovaOB.LOCK, keyboardType = KeyboardType.Password,
                secure = !model.showPassword) {
                Box(Modifier.padding(end = 6.dp).size(44.dp).novaPress { model.showPassword = !model.showPassword },
                    contentAlignment = Alignment.Center) {
                    val eye = "M2.4 12S6 5.6 12 5.6 21.6 12 21.6 12 18 18.4 12 18.4 2.4 12 2.4 12z|circle:12,12,3.1"
                    ObIcon(if (model.showPassword) eye else "$eye|M4 20L20 4", 20f, if (model.showPassword) NovaOB.ink else NovaOB.muted,
                        lineWidth = 1.7f)
                }
            }
            if (model.error.isNotEmpty() && model.phase == NovaLoginPhase.Form) ObErrorNote(model.error)
            ObOutlineButton(if (model.busy) "Kontrol ediliyor" else "Mail ile devam et", busy = model.busy,
                icon = { ObIcon(NovaOB.MAIL, 20f, NovaOB.ink, lineWidth = 1.8f) }) {
                focus.clearFocus()
                model.submitMail(onFailure = haptics::failure)
            }
            Box(Modifier.fillMaxWidth().height(40.dp).novaPress(onClick = model::openForgot), contentAlignment = Alignment.Center) {
                ObText("Şifremi unuttum", 14.5f, weight = 600, color = NovaOB.muted)
            }
        }
        Spacer(Modifier.weight(1f))
        ObLegalLine("Devam ederek", TextAlign.Center)
    }
}

@Composable
private fun NovaLoginVerificationSheet(model: NovaLoginViewModel) {
    val haptics = rememberNovaHaptics()
    val address = model.email.trim().ifEmpty { "E-posta" }
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp)).background(NovaOB.surface)
        .clickable(remember { MutableInteractionSource() }, null) {}
        .padding(start = 22.dp, end = 22.dp, top = 12.dp, bottom = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.size(44.dp, 5.dp).clip(CircleShape).background(NovaOB.line))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(NovaOB.fill), contentAlignment = Alignment.Center) {
                ObAnimatedLock(NovaOB.ink, NovaOB.ink, Color.White)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                ObText("Doğrulama", 21f, weight = 700, tracking = -0.3f)
                ObText("$address adresine gönderdiğimiz doğrulama kodunu gir.", 14.5f, color = NovaOB.muted, lineHeight = 1.4f)
            }
            Box(Modifier.size(34.dp).clip(CircleShape).background(NovaOB.fill2).novaPress(onClick = model::openForm),
                contentAlignment = Alignment.Center) {
                ObIcon("M6 6l12 12|M18 6L6 18", 13f, NovaOB.ink, lineWidth = 2.4f)
            }
        }
        ObCodeField(model.code, { model.code = it }, when {
            model.error.isNotEmpty() -> ObCodeState.Invalid
            model.codeVerified -> ObCodeState.Verified
            else -> ObCodeState.Idle
        }) { value -> model.verify(value, onSuccess = haptics::success, onFailure = haptics::failure) }
        if (model.codeVerified) {
            ObInfoNote("Kod doğrulandı, hesabın oluşturuluyor…", NovaOB.DONE_CIRCLE)
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.novaPress(onClick = model::resend).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(7.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    ObIcon(NovaOB.RESEND, 14f, NovaOB.ink, lineWidth = 1.9f)
                    ObText("Yeniden gönder", 13f, weight = 600)
                }
                ObText(model.resendNote.ifEmpty { "Kod gelmediyse spam klasörünü kontrol et." }, 12f, Modifier.weight(1f),
                    color = NovaOB.muted2, lineHeight = 1.35f, align = TextAlign.End)
            }
        }
        if (model.error.isNotEmpty()) ObErrorNote(model.error)
    }
}

@Composable
private fun NovaLoginForgot(model: NovaLoginViewModel) {
    val focus = LocalFocusManager.current
    val address = model.email.trim().ifEmpty { "Adresin" }
    ObFittedScroll(PaddingValues(start = 24.dp, end = 24.dp, top = obPadTop(56f), bottom = obPadBottom(28f)), 16.dp) {
        ObBackButton(Modifier.offset(x = (-10).dp), onClick = model::openForm)
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(60.dp).clip(RoundedCornerShape(18.dp)).background(NovaOB.fill2), contentAlignment = Alignment.Center) {
                ObIcon("M8.1 11.4V8.5a3.9 3.9 0 017.8 0|M4.6 11.2h14.8v9.6H4.6z|circle:12,16,1.5", 26f, NovaOB.ink, lineWidth = 2f)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp)) {
                ObText("Şifreni sıfırlayalım", 26f, weight = 700, lineHeight = 1.18f, tracking = -0.4f)
                ObText("Kayıtlı e-posta adresini yaz; sıfırlama bağlantısını hemen gönderelim.", 15.5f, Modifier.widthIn(max = 296.dp),
                    color = NovaOB.muted, lineHeight = 1.45f, align = TextAlign.Center)
            }
        }
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            ObField(model.email, { model.email = it }, "E-posta adresin", leadingIcon = "M2.5 4.5h19v15h-19z|M3 7l9 6 9-6",
                keyboardType = KeyboardType.Email)
            if (model.error.isNotEmpty()) ObErrorNote(model.error)
            if (model.resetSent) ObInfoNote("$address ile kayıtlı bir hesap varsa sıfırlama bağlantısını gönderdik.",
                "circle:12,12,9.2|M7.8 12.3l2.9 2.9 5.5-5.9")
            Box(Modifier.padding(top = 2.dp)) {
                ObOutlineButton(when {
                    model.resetBusy -> "Gönderiliyor"
                    model.resetSent -> "Tekrar gönder"
                    else -> "Sıfırlama bağlantısı gönder"
                }, busy = model.resetBusy) {
                    focus.clearFocus()
                    model.submitReset()
                }
            }
            Box(Modifier.fillMaxWidth().height(44.dp).novaPress(onClick = model::openForm), contentAlignment = Alignment.Center) {
                ObText("Girişe dön", 14.5f, weight = 600, color = NovaOB.muted)
            }
        }
        Spacer(Modifier.weight(1f))
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(NovaOB.fill3).padding(horizontal = 14.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            ObIcon("circle:12,12,9.2|M12 11v5.2|M12 7.8v.1", 15f, NovaOB.muted2, lineWidth = 1.8f, modifier = Modifier.padding(top = 1.dp))
            ObText("Bağlantı 30 dakika geçerlidir. Apple veya Google ile giriş yaptıysan şifre gerekmez.", 12.5f, Modifier.weight(1f),
                color = NovaOB.muted, lineHeight = 1.4f)
        }
    }
}

@Composable
private fun NovaLoginDone(createdAccount: Boolean) {
    Column(Modifier.fillMaxSize().padding(horizontal = 30.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically)) {
        Image(painterResource(R.drawable.nova_ob_logo), null, Modifier.width(120.dp))
        Box(Modifier.size(78.dp).clip(CircleShape).background(NovaOB.ink), contentAlignment = Alignment.Center) {
            ObIcon("M5 12.6l4.4 4.4L19 7", 38f, Color.White, lineWidth = 2.2f)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            ObText(if (createdAccount) "Hesabın hazır" else "Tekrar hoş geldin", 26f, weight = 700, tracking = -0.4f)
            ObText(if (createdAccount) "Hesabını oluşturduk. Kurulumu uygulama içinde tamamlayacaksın."
                else "Giriş yaptın. Çalışma alanın olduğu gibi duruyor.", 15.5f, color = NovaOB.muted, lineHeight = 1.45f, align = TextAlign.Center)
        }
        Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
            ObSpinner(15f)
            ObText("Uygulamaya yönlendiriliyorsun…", 13.5f, color = NovaOB.muted2)
        }
    }
}
