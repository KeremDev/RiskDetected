package com.riskdetectedan.feature.onboarding.nova

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import com.riskdetectedan.core.data.auth.CODE_UNREACHABLE
import com.riskdetectedan.core.data.auth.IsgPasswordRules
import com.riskdetectedan.core.designsystem.isg.novaPress
import com.riskdetectedan.core.designsystem.isg.rememberNovaHaptics
import com.riskdetectedan.feature.onboarding.R
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale
import javax.inject.Inject

internal enum class NovaLoginPhase { Form, Signup, Code, Forgot, ResetCode, NewPassword, Done }
internal enum class NovaLoginDone { Login, Signup, Reset }

internal const val WRONG_PASSWORD_MESSAGE =
    "Şifren yanlış. Şifreni bilmiyorsan aşağıdan kodla yenisini belirleyebilirsin. Apple veya Google ile kaydolduysan o butonla giriş yap."
internal const val PASSWORD_RULES_MESSAGE = "Şifre en az 8 karakter olmalı; büyük harf, küçük harf ve rakam içermeli."

/**
 * `İSGADA Giriş.dc.html` (iOS `NovaLoginScreen`): providers on top, mail and password below.
 * "Mail ile devam et" signs an existing account straight in and answers a wrong password on this
 * page; an address without an account signs up with the same password and gets its code on its
 * own page. "Hesap oluştur" opens the signup page for the same result. A reset mails a code, then
 * asks for the new password.
 */
@HiltViewModel
class NovaLoginViewModel @Inject constructor(private val auth: NovaOBAuth) : ViewModel() {
    internal var phase by mutableStateOf(NovaLoginPhase.Form)
    internal var email by mutableStateOf("")
    internal var password by mutableStateOf("")
    internal var showPassword by mutableStateOf(false)
    internal var error by mutableStateOf("")
    internal var busy by mutableStateOf(false)
    internal var signupPassword by mutableStateOf("")
    internal var showSignupPassword by mutableStateOf(false)
    internal var digits by mutableStateOf(List(6) { "" })
    internal var codeVerified by mutableStateOf(false)
    internal var codeError by mutableStateOf("")
    /** [codeError] is an unreachable server, not a wrong code. */
    internal var codeRetryable by mutableStateOf(false)
    internal var codeChecking by mutableStateOf(false)
    internal var resendNote by mutableStateOf("")
    /** Where the signup code page's back button leads: the signup page, or sign-in. */
    internal var codeReturn by mutableStateOf(NovaLoginPhase.Signup)
    /** The password typed for the signup the code page confirms. */
    private var codePassword = ""
    internal var newPassword by mutableStateOf("")
    internal var showNewPassword by mutableStateOf(false)
    internal var done by mutableStateOf(NovaLoginDone.Login)

    private val address get() = email.trim().lowercase(Locale.ROOT)

    internal fun openForm() { phase = NovaLoginPhase.Form; error = "" }
    internal fun openForgot() { phase = NovaLoginPhase.Forgot; error = "" }

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
                is RdResult.Success -> { done = NovaLoginDone.Login; phase = NovaLoginPhase.Done }
                is RdResult.Failure -> if (!NovaOBAuth.isCancellation(result)) error = NovaOBAuth.message(result, "Giriş yapılamadı")
            }
            busy = false
        }
    }

    /** "Mail ile devam et": an existing account signs in, a new address signs up with the same
     * password and gets its code. Supabase answers a wrong password and an unknown address the
     * same way, so a refused sign-in tries signup, which reports an existing account without
     * sending mail. Every password account was made under [IsgPasswordRules], so a password that
     * breaks them is refused here, before any request. */
    internal fun submitMail(onFailure: () -> Unit) {
        if (busy) return
        when {
            !NovaOBAuth.isValidEmail(address) -> { onFailure(); error = "Geçerli bir e-posta adresi yaz."; return }
            password.isEmpty() -> { onFailure(); error = "Şifreni yaz."; return }
            !IsgPasswordRules.evaluate(password).valid -> { onFailure(); error = PASSWORD_RULES_MESSAGE; return }
        }
        busy = true
        error = ""
        viewModelScope.launch {
            when (val result = auth.signIn(address, password)) {
                is RdResult.Success -> { done = NovaLoginDone.Login; phase = NovaLoginPhase.Done }
                is RdResult.Failure -> when (result.code) {
                    "password_invalid_credentials" -> signUpFromForm(onFailure)
                    // The account was created but its code never entered: finish the signup.
                    "password_email_not_confirmed" -> {
                        val sent = auth.resendSignupCode(address) is RdResult.Success
                        openCode(NovaLoginPhase.Form, password)
                        if (!sent) resendNote = "Kod gönderilemedi. Bir dakika sonra tekrar dene."
                    }
                    else -> { onFailure(); error = NovaOBAuth.message(result, "Giriş yapılamadı") }
                }
            }
            busy = false
        }
    }

    private suspend fun signUpFromForm(onFailure: () -> Unit) {
        when (val result = auth.signUp(address, password)) {
            is RdResult.Success -> openCode(NovaLoginPhase.Form, password)
            is RdResult.Failure -> when (result.code) {
                "password_confirmation_required" -> openCode(NovaLoginPhase.Form, password)
                "password_account_exists" -> { onFailure(); error = WRONG_PASSWORD_MESSAGE }
                else -> { onFailure(); error = NovaOBAuth.message(result, "Giriş yapılamadı") }
            }
        }
    }

    internal fun openSignup() { error = ""; signupPassword = ""; phase = NovaLoginPhase.Signup }

    internal fun submitSignup(onFailure: () -> Unit) {
        if (busy) return
        when {
            !NovaOBAuth.isValidEmail(address) -> { onFailure(); error = "Geçerli bir e-posta adresi yaz."; return }
            !IsgPasswordRules.evaluate(signupPassword).valid -> {
                onFailure()
                error = "Parola en az 8 karakter olmalı; büyük harf, küçük harf ve rakam içermeli."
                return
            }
        }
        busy = true
        error = ""
        viewModelScope.launch {
            when (val result = auth.signUp(address, signupPassword)) {
                is RdResult.Success -> openCode(NovaLoginPhase.Signup, signupPassword)
                is RdResult.Failure -> when (result.code) {
                    "password_confirmation_required" -> openCode(NovaLoginPhase.Signup, signupPassword)
                    "password_account_exists" -> { onFailure(); error = ACCOUNT_EXISTS_MESSAGE }
                    else -> { onFailure(); error = NovaOBAuth.message(result, "Hesap oluşturulamadı") }
                }
            }
            busy = false
        }
    }

    private fun openCode(returnTo: NovaLoginPhase, typedPassword: String) {
        resetCodeState()
        codeReturn = returnTo
        codePassword = typedPassword
        phase = NovaLoginPhase.Code
    }

    private fun resetCodeState() {
        digits = List(6) { "" }
        codeVerified = false
        codeChecking = false
        clearCodeError()
        resendNote = ""
    }

    internal fun clearCodeError() {
        codeError = ""
        codeRetryable = false
    }

    /** A refused code keeps its digits, so one wrong box can be fixed and checked again. */
    private fun showCodeFailure(result: RdResult.Failure, onFailure: () -> Unit) {
        onFailure()
        codeVerified = false
        codeRetryable = result.code == CODE_UNREACHABLE
        codeError = if (codeRetryable) CODE_UNREACHABLE_MESSAGE else CODE_REJECTED_MESSAGE
    }

    internal fun leaveCode() { error = ""; phase = codeReturn }

    internal fun verify(value: String, onSuccess: () -> Unit, onFailure: () -> Unit) {
        if (codeChecking || codeVerified) return
        codeChecking = true
        clearCodeError()
        viewModelScope.launch {
            val result = auth.verifySignupCode(address, value, codePassword)
            codeChecking = false
            when (result) {
                is RdResult.Success -> {
                    onSuccess()
                    codeVerified = true
                    delay(900)
                    done = NovaLoginDone.Signup
                    phase = NovaLoginPhase.Done
                }
                is RdResult.Failure -> showCodeFailure(result, onFailure)
            }
        }
    }

    internal fun resend() {
        viewModelScope.launch {
            resendNote = when (auth.resendSignupCode(address)) {
                is RdResult.Success -> { digits = List(6) { "" }; clearCodeError(); "Yeni kod gönderildi." }
                is RdResult.Failure -> "Kod gönderilemedi. Bir dakika sonra tekrar dene."
            }
        }
    }

    // MARK: reset

    internal fun submitReset(onFailure: () -> Unit) {
        if (busy) return
        if (!NovaOBAuth.isValidEmail(address)) { onFailure(); error = "Geçerli bir e-posta adresi yaz."; return }
        busy = true
        error = ""
        viewModelScope.launch {
            when (auth.recoverPassword(address)) {
                is RdResult.Success -> { resetCodeState(); phase = NovaLoginPhase.ResetCode }
                is RdResult.Failure -> { onFailure(); error = "Kod gönderilemedi. Bir dakika sonra tekrar dene." }
            }
            busy = false
        }
    }

    internal fun verifyReset(value: String, onSuccess: () -> Unit, onFailure: () -> Unit) {
        if (codeChecking || codeVerified) return
        codeChecking = true
        clearCodeError()
        viewModelScope.launch {
            val result = auth.verifyRecoveryCode(address, value)
            codeChecking = false
            when (result) {
                is RdResult.Success -> {
                    onSuccess()
                    codeVerified = true
                    delay(700)
                    newPassword = ""
                    error = ""
                    phase = NovaLoginPhase.NewPassword
                }
                is RdResult.Failure -> showCodeFailure(result, onFailure)
            }
        }
    }

    internal fun resendReset() {
        viewModelScope.launch {
            resendNote = when (auth.recoverPassword(address)) {
                is RdResult.Success -> { digits = List(6) { "" }; clearCodeError(); "Yeni kod gönderildi." }
                is RdResult.Failure -> "Kod gönderilemedi. Bir dakika sonra tekrar dene."
            }
        }
    }

    /** The code opened a session; leaving without a new password ends it. */
    internal fun leaveNewPassword() {
        viewModelScope.launch { auth.cancelRecovery() }
        openForm()
    }

    internal fun saveNewPassword(onSuccess: () -> Unit, onFailure: () -> Unit) {
        if (busy) return
        if (!IsgPasswordRules.evaluate(newPassword).valid) {
            onFailure()
            error = PASSWORD_RULES_MESSAGE
            return
        }
        busy = true
        error = ""
        viewModelScope.launch {
            val result = auth.setNewPassword(newPassword)
            // Already the account's password: the reset has what it wanted.
            if (result is RdResult.Failure && result.code != "password_same_password") {
                onFailure()
                error = "Şifre kaydedilemedi. Bağlantını kontrol edip yeniden dene."
                busy = false
                return@launch
            }
            onSuccess()
            done = NovaLoginDone.Reset
            phase = NovaLoginPhase.Done
            busy = false
            delay(1200)
            auth.finishRecovery()
        }
    }
}

@Composable
fun NovaLoginScreen(model: NovaLoginViewModel = hiltViewModel()) {
    ObResizesForKeyboard()
    // System back walks the pages like their back buttons; only the sign-in form leaves the app.
    BackHandler(enabled = model.phase != NovaLoginPhase.Form && model.phase != NovaLoginPhase.Done) {
        when (model.phase) {
            NovaLoginPhase.Code -> model.leaveCode()
            NovaLoginPhase.ResetCode -> model.openForgot()
            NovaLoginPhase.NewPassword -> model.leaveNewPassword()
            else -> model.openForm()
        }
    }
    val haptics = rememberNovaHaptics()
    Box(Modifier.fillMaxSize().background(NovaOB.surface)) {
        AnimatedContent(model.phase, transitionSpec = { fadeIn(tween(240)) togetherWith fadeOut(tween(240)) }, label = "nova-login") { phase ->
            when (phase) {
                NovaLoginPhase.Form -> NovaLoginForm(model)
                NovaLoginPhase.Signup -> ObSignupPage(
                    email = model.email, onEmail = { model.email = it },
                    password = model.signupPassword, onPassword = { model.signupPassword = it },
                    showPassword = model.showSignupPassword, onShowPassword = { model.showSignupPassword = it },
                    error = model.error, busy = model.busy,
                    onBack = model::openForm, onLogin = model::openForm,
                    onSubmit = { model.submitSignup(onFailure = haptics::failure) },
                )
                NovaLoginPhase.Code -> ObCodePage(
                    email = model.email, digits = { model.digits }, onDigits = { model.digits = it },
                    error = model.codeError, retryable = model.codeRetryable, checking = model.codeChecking,
                    verified = model.codeVerified,
                    verifiedNote = "Kod doğrulandı, hesabın oluşturuluyor…", resendNote = model.resendNote,
                    onBack = model::leaveCode, onEdit = model::clearCodeError,
                    onComplete = { value -> model.verify(value, onSuccess = haptics::success, onFailure = haptics::failure) },
                    onResend = model::resend,
                )
                NovaLoginPhase.Forgot -> ObResetEmailPage(
                    email = model.email, onEmail = { model.email = it }, error = model.error, busy = model.busy,
                    onBack = model::openForm, onSubmit = { model.submitReset(onFailure = haptics::failure) },
                )
                NovaLoginPhase.ResetCode -> ObCodePage(
                    email = model.email, digits = { model.digits }, onDigits = { model.digits = it },
                    error = model.codeError, retryable = model.codeRetryable, checking = model.codeChecking,
                    verified = model.codeVerified,
                    verifiedNote = "Kod doğrulandı.", resendNote = model.resendNote,
                    onBack = model::openForgot, onEdit = model::clearCodeError,
                    onComplete = { value -> model.verifyReset(value, onSuccess = haptics::success, onFailure = haptics::failure) },
                    onResend = model::resendReset,
                )
                NovaLoginPhase.NewPassword -> ObNewPasswordPage(
                    password = model.newPassword, onPassword = { model.newPassword = it },
                    showPassword = model.showNewPassword, onShowPassword = { model.showNewPassword = it },
                    error = model.error, busy = model.busy, onBack = model::leaveNewPassword,
                    onSubmit = { model.saveNewPassword(onSuccess = haptics::success, onFailure = haptics::failure) },
                )
                NovaLoginPhase.Done -> NovaLoginDone(model.done)
            }
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
                ObText("Giriş yap ya da saniyeler içinde hesabını oluştur.", 15.5f, Modifier.widthIn(max = 290.dp),
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
            if (model.error.isNotEmpty()) ObErrorNote(model.error)
            ObOutlineButton(if (model.busy) "Kontrol ediliyor" else "Mail ile devam et", busy = model.busy,
                icon = { ObIcon(NovaOB.MAIL, 20f, NovaOB.ink, lineWidth = 1.8f) }) {
                focus.clearFocus()
                model.submitMail(onFailure = haptics::failure)
            }
            Box(Modifier.fillMaxWidth().height(40.dp).novaPress(onClick = model::openForgot), contentAlignment = Alignment.Center) {
                ObText("Şifreni bilmiyor musun?", 14.5f, weight = 600, color = NovaOB.muted)
            }
            Row(Modifier.fillMaxWidth().height(40.dp).novaPress(onClick = model::openSignup),
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                ObText("Hesabın yok mu? ", 14.5f, weight = 600, color = NovaOB.muted)
                ObText("Hesap oluştur", 14.5f, weight = 600)
            }
        }
        Spacer(Modifier.weight(1f))
        ObLegalLine("Devam ederek", TextAlign.Center)
    }
}

@Composable
private fun NovaLoginDone(kind: NovaLoginDone) {
    Column(Modifier.fillMaxSize().padding(horizontal = 30.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically)) {
        Image(painterResource(R.drawable.nova_ob_logo), null, Modifier.width(120.dp))
        Box(Modifier.size(78.dp).clip(CircleShape).background(NovaOB.ink), contentAlignment = Alignment.Center) {
            ObIcon("M5 12.6l4.4 4.4L19 7", 38f, Color.White, lineWidth = 2.2f)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            ObText(when (kind) {
                NovaLoginDone.Login -> "Tekrar hoş geldin"
                NovaLoginDone.Signup -> "Hesabın hazır"
                NovaLoginDone.Reset -> "Şifren kaydedildi"
            }, 26f, weight = 700, tracking = -0.4f)
            ObText(when (kind) {
                NovaLoginDone.Login -> "Giriş yaptın. Çalışma alanın olduğu gibi duruyor."
                NovaLoginDone.Signup -> "Hesabını oluşturduk. Kurulumu uygulama içinde tamamlayacaksın."
                NovaLoginDone.Reset -> "Yeni şifrenle giriş yaptın. Sonraki girişlerinde bu şifreyi kullan."
            }, 15.5f, color = NovaOB.muted, lineHeight = 1.45f, align = TextAlign.Center)
        }
        Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
            ObSpinner(15f)
            ObText("Uygulamaya yönlendiriliyorsun…", 13.5f, color = NovaOB.muted2)
        }
    }
}
