package com.riskdetectedan.feature.onboarding.nova

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.auth.AuthRouteHold
import com.riskdetectedan.core.data.auth.CODE_UNREACHABLE
import com.riskdetectedan.core.data.auth.IsgPasswordRules
import com.riskdetectedan.core.data.auth.RdAppLanguage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.onboarding.OnboardingAnswersRepository
import com.riskdetectedan.core.data.release.AndroidRuntimeGateName
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import com.riskdetectedan.feature.onboarding.GoogleAuthClient
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale
import javax.inject.Inject

/**
 * Every auth side effect the Nova funnel and the Nova sign-in surface need (iOS
 * `NovaOBAuthBridge`), behind the same release gate the legacy auth screen honours.
 */
class NovaOBAuth @Inject constructor(
    private val authRepository: AuthRepository,
    private val googleAuthClient: GoogleAuthClient,
    private val releasePolicyRepository: ReleasePolicyRepository,
    private val routeHold: AuthRouteHold,
) {
    val currentUserIdFlow get() = authRepository.currentUserIdFlow
    val isAuthenticated get() = authRepository.currentUserId != null

    private val language get() = RdAppLanguage.current()

    suspend fun signIn(email: String, password: String) = gated { authRepository.signInWithPassword(email, password) }
    suspend fun signUp(email: String, password: String) = gated { authRepository.signUpWithPassword(email, password, language) }
    /** The signup code comes with [signUp]; this only sends it again. */
    suspend fun resendSignupCode(email: String) = gated { authRepository.resendSignupCode(email) }
    /** [password] is the one typed for this signup; see `AuthRepository.verifySignupCode`. */
    suspend fun verifySignupCode(email: String, code: String, password: String) =
        gated { authRepository.verifySignupCode(email, code, password) }
    /** Sends the reset code. The server answers the same whether or not the address has an account. */
    suspend fun recoverPassword(email: String) = gated { authRepository.requestPasswordRecovery(email) }

    /** Opens the account's session with the reset code and keeps the app on the sign-in surface
     * until [finishRecovery] or [cancelRecovery], so the new password comes first. */
    suspend fun verifyRecoveryCode(email: String, code: String): RdResult<Unit> = gated {
        routeHold.hold()
        authRepository.verifyRecoveryCode(email, code).also { if (it is RdResult.Failure) routeHold.release() }
    }
    suspend fun setNewPassword(password: String) = authRepository.setNewPassword(password)
    fun finishRecovery() = routeHold.release()
    /** Signs the recovery session out when the new-password page is left. */
    suspend fun cancelRecovery() {
        authRepository.signOut()
        routeHold.release()
    }

    /** Opens Sign in with Apple in a Custom Tab. The session arrives later through the app deep link. */
    suspend fun appleSignIn() = gated { authRepository.signInWithAppleOAuth() }

    suspend fun googleSignIn(activity: Context): RdResult<Unit> = gated {
        when (val token = googleAuthClient.requestIdToken(activity)) {
            is RdResult.Failure -> token
            is RdResult.Success -> token.value.let {
                authRepository.signInWithGoogleIdToken(it.idToken, it.rawNonce, it.email, it.displayName)
            }
        }
    }

    private suspend fun gated(action: suspend () -> RdResult<Unit>): RdResult<Unit> {
        val decision = releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Auth)
        if (!decision.enabled) return RdResult.Failure("auth_gate_closed", "Android girişi şu an kapalı: ${decision.reason}")
        return action()
    }

    companion object {
        fun message(failure: RdResult.Failure, context: String, fallbackTitle: String = context): String =
            AppErrorMessages.make(failure.message, context = context, fallbackTitle = fallbackTitle).message

        fun isCancellation(failure: RdResult.Failure): Boolean {
            val text = "${failure.code} ${failure.message}".lowercase(Locale.ROOT)
            return "cancel" in text || "vazgeç" in text || "iptal" in text
        }

        fun isValidEmail(value: String): Boolean {
            val address = value.trim()
            val at = address.indexOf('@')
            if (at <= 0) return false
            val domain = address.substring(at + 1)
            return domain.isNotEmpty() && '.' in domain && !domain.endsWith('.') && !domain.startsWith('.') &&
                ' ' !in address && address.count { it == '@' } == 1
        }
    }
}

/** A code the server refused, and one that never got an answer (iOS `NovaOBController`). */
internal const val CODE_REJECTED_MESSAGE =
    "Kod yanlış ya da süresi dolmuş. Hatalı rakama dokunup düzelt ya da yeni kod iste."
internal const val CODE_UNREACHABLE_MESSAGE = "Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene."

/** Signup for an address that already has an account (iOS `NovaOBController.accountExistsMessage`). */
internal const val ACCOUNT_EXISTS_MESSAGE =
    "Bu e-posta adresiyle bir hesap var. Giriş yap'a dokunup şifrenle ya da Apple veya Google ile gir."

/** Screen identifiers, one per `sc-if` branch in the prototype. */
internal enum class NovaOBScreen { Splash, Reveal, Intro1, Intro2, Intro3, Social, Questions, Prep, Card, Signup, EmailForm, Otp, Trial, TrialHow, Push }

/** State and transitions of the Nova onboarding funnel (iOS `NovaOBController`). */
@HiltViewModel
class NovaOnboardingController @Inject constructor(
    internal val auth: NovaOBAuth,
    private val answersRepository: OnboardingAnswersRepository,
) : ViewModel() {
    internal var screen by mutableStateOf(NovaOBScreen.Splash)
    internal var questionIndex by mutableIntStateOf(0)
    internal var answers by mutableStateOf(NovaOBAnswers())
    internal val skipped = mutableStateListOf<String>()
    internal var search by mutableStateOf("")
    internal var skipModal by mutableStateOf(false)

    internal var prepPercent by mutableIntStateOf(0)
    internal var prepDone by mutableStateOf(false)

    internal var email by mutableStateOf("")
    internal var password by mutableStateOf("")
    internal var showPassword by mutableStateOf(false)
    internal var marketing by mutableStateOf(false)
    internal var otpDigits by mutableStateOf(List(6) { "" })
    internal var otpError by mutableStateOf("")
    /** [otpError] is an unreachable server, not a wrong code. */
    internal var otpRetryable by mutableStateOf(false)
    internal var otpVerified by mutableStateOf(false)
    internal var authError by mutableStateOf("")
    internal var busy by mutableStateOf(false)
    internal var resendNote by mutableStateOf("")

    /** Set once a Custom Tab provider flow is launched; its session lands asynchronously. */
    private var awaitingProvider = false
    private var prepJob: Job? = null

    init {
        viewModelScope.launch {
            auth.currentUserIdFlow.collect { userId ->
                if (userId != null && awaitingProvider && screen == NovaOBScreen.Signup) {
                    awaitingProvider = false
                    go(NovaOBScreen.Trial)
                }
            }
        }
    }

    internal val question get() = NovaOBCatalogue.questions[questionIndex]
    internal val sectionLabel get() = NovaOBCatalogue.sections.firstOrNull { questionIndex in it.second }?.first
        ?: NovaOBCatalogue.sections[0].first
    internal val stepLabel get() = "${questionIndex + 1} / ${NovaOBCatalogue.questions.size}"
    internal val progress get() = (questionIndex + 1).toFloat() / NovaOBCatalogue.questions.size
    internal val primaryLabel get() = when {
        questionIndex == NovaOBCatalogue.questions.size - 1 -> "Profilimi hazırla"
        else -> "Devam et"
    }

    // MARK: navigation

    internal fun go(next: NovaOBScreen) {
        authError = ""
        screen = next
    }

    internal fun startQuestions() {
        questionIndex = 0
        search = ""
        screen = NovaOBScreen.Questions
    }

    internal fun next() {
        if (!canContinue) return
        advance()
    }

    internal fun skipQuestion() {
        if (question.id !in skipped) skipped.add(question.id)
        advance()
    }

    private fun advance() {
        when {
            questionIndex >= NovaOBCatalogue.questions.size - 1 -> startPrep()
            else -> { questionIndex += 1; search = "" }
        }
    }

    internal fun back() {
        when (screen) {
            NovaOBScreen.Otp -> go(NovaOBScreen.EmailForm)
            NovaOBScreen.TrialHow -> go(NovaOBScreen.Trial)
            NovaOBScreen.EmailForm -> go(NovaOBScreen.Signup)
            NovaOBScreen.Questions -> when {
                questionIndex == 0 -> go(NovaOBScreen.Social)
                else -> { questionIndex -= 1; search = "" }
            }
            else -> go(NovaOBScreen.Card)
        }
    }

    internal fun toCard() {
        prepJob?.cancel()
        screen = NovaOBScreen.Card
    }

    // MARK: answers

    internal val canContinue: Boolean get() = when (question.kind) {
        NovaOBQuestionKind.Text -> answers.name.isNotBlank()
        NovaOBQuestionKind.Counter -> true
        NovaOBQuestionKind.Slider -> answers.exp != null || answers.expLess
        NovaOBQuestionKind.Single -> answers.single(question.id) != null
        NovaOBQuestionKind.Multi -> answers.list(question.id).isNotEmpty()
    }

    internal fun unskip(id: String) { skipped.remove(id) }

    internal fun setName(value: String) {
        answers = answers.copy(name = value)
        unskip("name")
    }

    internal fun setOther(value: String) { answers = answers.withOther(question.id, value) }

    internal fun pickSingle(value: String) {
        unskip(question.id)
        answers = answers.withSingle(question.id, if (answers.single(question.id) == value) null else value)
    }

    internal fun toggleMulti(value: String) {
        val current = answers.list(question.id)
        unskip(question.id)
        val exclusive = question.exclusive
        val updated = when {
            exclusive != null && value == exclusive -> if (value in current) emptyList() else listOf(value)
            value in current -> current - value
            else -> {
                val base = if (exclusive != null) current - exclusive else current
                val max = question.max
                if (max != null && base.size >= max) return
                base + value
            }
        }
        answers = answers.withList(question.id, updated)
    }

    internal fun isSelected(value: String): Boolean =
        if (question.kind == NovaOBQuestionKind.Single) answers.single(question.id) == value else value in answers.list(question.id)

    internal fun isBlocked(value: String): Boolean {
        if (isSelected(value)) return false
        val chosen = answers.list(question.id)
        val max = question.max
        if (max != null && chosen.size >= max) return true
        val exclusive = question.exclusive
        return exclusive != null && exclusive in chosen && value != exclusive
    }

    /** "Sana uygun olabilir" — the assist step nudges what the growth step picked. */
    internal fun isSuggested(option: NovaOBOption): Boolean {
        val source = option.suggestedBy ?: return false
        return !isSelected(option.value) && source in answers.growth
    }

    internal val selectionNote: String get() {
        val count = answers.list(question.id).size
        question.max?.let { return "$count / $it seçildi — en fazla $it seçim yapabilirsin." }
        return if (question.kind == NovaOBQuestionKind.Multi && count > 0) "$count seçim yapıldı." else ""
    }

    internal val visibleOptions: List<NovaOBOption> get() {
        if (!question.searchable || search.isBlank()) return question.options
        val locale = Locale.forLanguageTag("tr-TR")
        val needle = search.trim().lowercase(locale)
        val chosen = answers.list(question.id)
        return question.options.filter { needle in it.label.lowercase(locale) || it.value in chosen }
    }

    internal val showsOtherField: Boolean get() {
        val other = question.other ?: return false
        return if (question.kind == NovaOBQuestionKind.Single) answers.single(question.id) == other else other in answers.list(question.id)
    }

    // MARK: experience slider and counter

    internal fun pickStop(index: Int) {
        unskip("exp")
        answers = answers.copy(exp = index, expLess = false)
    }

    internal fun toggleLessThanYear() {
        unskip("exp")
        answers = answers.copy(expLess = !answers.expLess, exp = null)
    }

    internal fun bumpInspections(delta: Int) {
        unskip("inspections")
        answers = answers.copy(inspections = maxOf(0, answers.inspections + delta))
    }

    internal fun setInspections(value: Int) {
        answers = answers.copy(inspections = value.coerceIn(0, 999))
        unskip("inspections")
    }

    // MARK: prep

    internal fun startPrep() {
        prepJob?.cancel()
        prepPercent = 0
        prepDone = false
        screen = NovaOBScreen.Prep
        prepJob = viewModelScope.launch {
            val duration = 3_400.0
            val start = System.currentTimeMillis()
            while (true) {
                val percent = minOf(100, ((System.currentTimeMillis() - start) / duration * 100).toInt())
                prepPercent = percent
                if (percent >= 100) break
                delay(40)
            }
            prepDone = true
            delay(700)
            if (screen == NovaOBScreen.Prep) toCard()
        }
    }

    // MARK: auth actions

    /** Stores the profile before the account exists, so the session-time sync lands it. */
    /** The mail signup page was submitted, so [marketing] is an answer rather than a default. */
    private var marketingAnswered = false

    /** Every answer, with the skipped questions and the updates choice, kept on the device until
     * the first session sends it. */
    internal fun saveDraft() {
        answersRepository.savePending(answers.makeDraft(skipped.toSet(), if (marketingAnswered) marketing else null))
    }

    internal fun submitSignup(onFailure: () -> Unit) {
        if (busy) return
        val address = email.trim()
        when {
            address.isEmpty() -> { onFailure(); authError = "E-posta adresini yaz."; return }
            !NovaOBAuth.isValidEmail(address) -> { onFailure(); authError = "Bu e-posta adresi geçerli görünmüyor."; return }
            !IsgPasswordRules.evaluate(password).valid -> {
                onFailure()
                authError = "Parola en az 8 karakter olmalı; büyük harf, küçük harf ve rakam içermeli."
                return
            }
        }
        // The draft must already hold the updates choice made on this page when the session starts.
        marketingAnswered = true
        saveDraft()
        busy = true
        authError = ""
        viewModelScope.launch {
            when (val result = auth.signUp(address, password)) {
                is RdResult.Success -> openCodePage()
                is RdResult.Failure -> when (result.code) {
                    // Supabase created the account and imported a session instead of asking for
                    // confirmation; the address is still verified the same way.
                    "password_confirmation_required" -> openCodePage()
                    "password_account_exists" -> { onFailure(); authError = ACCOUNT_EXISTS_MESSAGE }
                    else -> { onFailure(); authError = NovaOBAuth.message(result, "Hesap oluşturulamadı") }
                }
            }
            busy = false
        }
    }

    /** Signup already sent the code; asking for another here would only replace it or be
     * refused by the one-mail-a-minute limit. */
    private fun openCodePage() {
        otpDigits = List(6) { "" }
        clearOtpError()
        otpVerified = false
        resendNote = ""
        screen = NovaOBScreen.Otp
    }

    internal fun verifyOtp(code: String, onSuccess: () -> Unit, onFailure: () -> Unit) {
        if (busy || otpVerified) return
        busy = true
        clearOtpError()
        viewModelScope.launch {
            when (val result = auth.verifySignupCode(email.trim(), code, password)) {
                is RdResult.Success -> {
                    onSuccess()
                    otpVerified = true
                    busy = false
                    delay(700)
                    go(NovaOBScreen.Trial)
                }
                is RdResult.Failure -> {
                    // The digits stay: one wrong box can be fixed, and a full code is checked again.
                    onFailure()
                    otpRetryable = result.code == CODE_UNREACHABLE
                    otpError = if (otpRetryable) CODE_UNREACHABLE_MESSAGE else CODE_REJECTED_MESSAGE
                    busy = false
                }
            }
        }
    }

    internal fun clearOtpError() {
        otpError = ""
        otpRetryable = false
    }

    internal fun resendCode() {
        if (email.isBlank()) return
        viewModelScope.launch {
            resendNote = when (auth.resendSignupCode(email.trim())) {
                is RdResult.Success -> { otpDigits = List(6) { "" }; clearOtpError(); "Yeni kod gönderildi." }
                is RdResult.Failure -> "Kod gönderilemedi. Bir dakika sonra tekrar dene."
            }
            delay(2_600)
            resendNote = ""
        }
    }

    internal fun runApple() {
        if (busy) return
        busy = true
        authError = ""
        viewModelScope.launch {
            when (val result = auth.appleSignIn()) {
                is RdResult.Success -> awaitingProvider = true
                is RdResult.Failure -> if (!NovaOBAuth.isCancellation(result)) {
                    authError = NovaOBAuth.message(result, "Apple ile giriş yapılamadı")
                }
            }
            busy = false
        }
    }

    internal fun runGoogle(activity: Context) {
        if (busy) return
        busy = true
        authError = ""
        viewModelScope.launch {
            when (val result = auth.googleSignIn(activity)) {
                is RdResult.Success -> go(NovaOBScreen.Trial)
                is RdResult.Failure -> if (!NovaOBAuth.isCancellation(result)) {
                    authError = NovaOBAuth.message(result, "Google ile giriş yapılamadı")
                }
            }
            busy = false
        }
    }
}
