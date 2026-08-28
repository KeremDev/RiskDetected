package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Pin
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.foundation.text.ClickableText
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.auth.RdAppLanguage
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdHeroTile
import com.riskdetectedan.core.designsystem.RdHeroTint
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.feature.onboarding.R as OnboardingR

enum class EmailPhase { Hidden, Email, Otp }

/**
 * Standalone sign-in surface used by the root Auth destination. This is intentionally separate
 * from [AuthScreen], which is OBAuthView's "Son adım" and belongs only to onboarding step 8.
 *
 * Visual source: live iOS `AuthView.swift` / `AuthHero`. Android keeps the agreed v1 provider
 * policy (email OTP + Google; no Apple CTA) while preserving the photo, logo, type scale,
 * gradients, button geometry and legal-link hierarchy of the iOS screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginScreen(
    onAuthenticated: () -> Unit,
    viewModel: AuthViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val state by viewModel.state.collectAsState()
    var phase by remember { mutableStateOf(EmailPhase.Hidden) }
    var email by remember { mutableStateOf("") }
    var otp by remember { mutableStateOf("") }
    var sentTo by remember { mutableStateOf("") }
    var legalDocumentKind by remember { mutableStateOf<String?>(null) }

    val isLoading = state is AuthUiState.Loading
    val normalizedEmail = email.trim().lowercase()
    val failure = (state as? AuthUiState.Failed)?.error?.message

    LaunchedEffect(state) {
        when (state) {
            is AuthUiState.SignedIn -> onAuthenticated()
            is AuthUiState.OtpSent -> {
                sentTo = normalizedEmail
                otp = ""
                phase = EmailPhase.Otp
            }
            else -> Unit
        }
    }
    LaunchedEffect(otp) {
        if (phase == EmailPhase.Otp && otp.length == 6 && !isLoading) {
            viewModel.verifyEmailOtp(sentTo, otp)
        }
    }

    LoginScreenContent(
        phase = phase,
        email = email,
        onEmailChange = { email = it },
        otp = otp,
        onOtpChange = { otp = it },
        sentTo = sentTo,
        isLoading = isLoading,
        error = failure,
        onStartEmail = { phase = EmailPhase.Email },
        onGoogle = { viewModel.signInWithGoogle(context) },
        onSendCode = { viewModel.sendEmailOtp(normalizedEmail, resolveAppLanguage()) },
        onVerifyCode = { viewModel.verifyEmailOtp(sentTo, otp) },
        onResend = { viewModel.sendEmailOtp(sentTo, resolveAppLanguage()) },
        onChangeEmail = { phase = EmailPhase.Email; otp = "" },
        onCloseEmail = { phase = EmailPhase.Hidden },
        onOpenDocument = { legalDocumentKind = it },
    )

    if (legalDocumentKind != null) {
        var legalDocuments by remember { mutableStateOf<List<RdLegalDocument>>(emptyList()) }
        LaunchedEffect(Unit) {
            legalDocuments = LegalDocumentAssets.load(context)
                .map { RdLegalDocument(kind = it.kind, title = it.title, text = it.text) }
        }
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { legalDocumentKind = null }, sheetState = sheetState) {
            RdLegalDocumentSheet(
                documents = legalDocuments,
                initialKind = legalDocumentKind,
                onClose = { legalDocumentKind = null },
            )
        }
    }
}

@Composable
fun LoginScreenContent(
    phase: EmailPhase = EmailPhase.Hidden,
    email: String = "",
    onEmailChange: (String) -> Unit = {},
    otp: String = "",
    onOtpChange: (String) -> Unit = {},
    sentTo: String = "",
    isLoading: Boolean = false,
    error: String? = null,
    onStartEmail: () -> Unit = {},
    onGoogle: () -> Unit = {},
    onSendCode: () -> Unit = {},
    onVerifyCode: () -> Unit = {},
    onResend: () -> Unit = {},
    onChangeEmail: () -> Unit = {},
    onCloseEmail: () -> Unit = {},
    onOpenDocument: (String) -> Unit = {},
) {
    val colors = RdTheme.colors
    val normalizedEmail = email.trim().lowercase()
    val canSendCode = normalizedEmail.contains("@") && normalizedEmail.contains(".") && !isLoading
    val canVerifyCode = otp.length == 6 && !isLoading

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.paper),
    ) {
        Image(
            painter = painterResource(OnboardingR.drawable.auth_hero),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colorStops = arrayOf(
                            0.00f to Color.Transparent,
                            0.30f to Color.Transparent,
                            0.45f to colors.greenSoft.copy(alpha = 0.16f),
                            0.58f to colors.paper.copy(alpha = 0.28f),
                            0.72f to colors.paper.copy(alpha = 0.68f),
                            0.86f to colors.paper.copy(alpha = 0.94f),
                            0.96f to colors.paper,
                        ),
                    ),
                ),
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(116.dp)
                .background(
                    Brush.verticalGradient(
                        colorStops = arrayOf(
                            0.00f to colors.paper.copy(alpha = 0.72f),
                            0.43f to colors.paper.copy(alpha = 0.30f),
                            1.00f to Color.Transparent,
                        ),
                    ),
                ),
        )

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .imePadding()
                .navigationBarsPadding()
                .padding(bottom = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        Brush.horizontalGradient(
                            colorStops = arrayOf(
                                0.00f to Color.Transparent,
                                0.22f to colors.white.copy(alpha = 0.52f),
                                0.50f to colors.white.copy(alpha = 0.70f),
                                0.78f to colors.white.copy(alpha = 0.52f),
                                1.00f to Color.Transparent,
                            ),
                        ),
                    )
                    .padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Image(
                    painter = painterResource(OnboardingR.drawable.auth_logo),
                    contentDescription = stringResource(RdR.string.rd_riskdetected),
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.width(242.dp).height(68.dp),
                )
                Text(
                    text = stringResource(RdR.string.rd_auth_standalone_tagline),
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.graphite,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.widthIn(max = 270.dp),
                )
            }

            Spacer(Modifier.height(if (phase == EmailPhase.Hidden) 18.dp else 12.dp))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (phase == EmailPhase.Hidden) {
                    LoginOptionButton(
                        text = stringResource(RdR.string.rd_eposta_ile_giris_yap),
                        onClick = onStartEmail,
                        enabled = !isLoading,
                        icon = {
                            Icon(
                                Icons.Filled.Email,
                                contentDescription = null,
                                tint = colors.greenDark,
                                modifier = Modifier.size(22.dp),
                            )
                        },
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        HorizontalDivider(modifier = Modifier.weight(1f), color = colors.slate.copy(alpha = 0.22f))
                        Text(
                            stringResource(RdR.string.rd_veya),
                            style = RdFontStyle.Caption.toTextStyle(),
                            color = colors.graphite.copy(alpha = 0.78f),
                        )
                        HorizontalDivider(modifier = Modifier.weight(1f), color = colors.slate.copy(alpha = 0.22f))
                    }

                    LoginOptionButton(
                        text = stringResource(
                            if (isLoading) RdR.string.rd_google_baglaniyor else RdR.string.rd_google_devam,
                        ),
                        onClick = onGoogle,
                        enabled = !isLoading,
                        googleWordmark = !isLoading,
                        icon = {
                            Image(
                                painter = painterResource(OnboardingR.drawable.google_mark),
                                contentDescription = null,
                                modifier = Modifier.size(22.dp),
                            )
                        },
                    )
                    if (error != null) {
                        Spacer(Modifier.height(10.dp))
                        AuthErrorBanner(error)
                    }
                    Spacer(Modifier.height(14.dp))
                    StandaloneLegalNotice(onOpenDocument)
                } else {
                    EmailAuthPanel(
                        phase = phase,
                        email = email,
                        onEmailChange = onEmailChange,
                        otp = otp,
                        onOtpChange = onOtpChange,
                        sentTo = sentTo,
                        canSendCode = canSendCode,
                        canVerifyCode = canVerifyCode,
                        isLoading = isLoading,
                        error = error,
                        onSendCode = onSendCode,
                        onVerifyCode = onVerifyCode,
                        onResend = onResend,
                        onChangeEmail = onChangeEmail,
                        onClose = onCloseEmail,
                    )
                    Spacer(Modifier.height(10.dp))
                    StandaloneLegalNotice(onOpenDocument)
                }
            }
        }
    }
}

@Composable
private fun LoginOptionButton(
    text: String,
    onClick: () -> Unit,
    enabled: Boolean,
    googleWordmark: Boolean = false,
    icon: @Composable () -> Unit,
) {
    val colors = RdTheme.colors
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp)
            .shadow(elevation = 8.dp, shape = shape, clip = false)
            .clip(shape)
            .background(colors.white)
            .border(1.5.dp, colors.onyx, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.75f)
            .padding(horizontal = 18.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon()
        Spacer(Modifier.width(9.dp))
        if (googleWordmark) {
            GoogleProviderWordmark(text)
        } else {
            Text(
                text,
                style = RdFontStyle.Body.toTextStyle().copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold),
                color = colors.onyx,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun GoogleProviderWordmark(localizedTitle: String) {
    val colors = listOf(
        Color(0xFF4285F4),
        Color(0xFFEA4335),
        Color(0xFFFBBC05),
        Color(0xFF4285F4),
        Color(0xFF34A853),
        Color(0xFFEA4335),
    )
    val word = "Google"
    val start = localizedTitle.indexOf(word)
    val title = if (start < 0) {
        buildAnnotatedString { append(localizedTitle) }
    } else {
        buildAnnotatedString {
            append(localizedTitle.substring(0, start))
            word.forEachIndexed { index, letter ->
                withStyle(SpanStyle(color = colors[index])) { append(letter) }
            }
            append(localizedTitle.substring(start + word.length))
        }
    }
    Text(
        text = title,
        style = RdFontStyle.Body.toTextStyle().copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold),
        color = RdTheme.colors.onyx,
        textAlign = TextAlign.Center,
    )
}

@Composable
private fun StandaloneLegalNotice(onOpenDocument: (String) -> Unit) {
    val colors = RdTheme.colors
    val annotated = buildAnnotatedString {
        append(stringResource(RdR.string.rd_auth_legal_standalone_prefix))
        append(" ")
        fun legalLink(label: String, kind: String) {
            pushStringAnnotation(tag = "legal", annotation = kind)
            withStyle(SpanStyle(color = colors.greenDark, textDecoration = TextDecoration.Underline)) {
                append(label)
            }
            pop()
        }
        legalLink(stringResource(RdR.string.rd_hizmet_sartlarimiz), "terms")
        append(", ")
        legalLink(stringResource(RdR.string.rd_gizlilik_politikamiz), "privacy")
        append(", ")
        legalLink(stringResource(RdR.string.rd_kvkk_aydinlatma_metnini), "kvkk")
        append(" ve ")
        legalLink(stringResource(RdR.string.rd_acik_riza_beyanini), "consent")
        append(" ")
        append(stringResource(RdR.string.rd_auth_legal_standalone_suffix))
    }
    ClickableText(
        text = annotated,
        style = RdFontStyle.Caption.toTextStyle().copy(
            fontSize = 10.sp,
            lineHeight = 14.sp,
            color = colors.slate,
            textAlign = TextAlign.Center,
        ),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 2.dp),
        onClick = { offset ->
            annotated.getStringAnnotations("legal", offset, offset)
                .firstOrNull()
                ?.let { onOpenDocument(it.item) }
        },
    )
}

/**
 * Port of App/Views/Onboarding/V2/Screens/OBAuthView.swift (2026-08-08 visual pass, Faz D) —
 * email OTP, Apple OAuth/PKCE and Google Sign-In share the same screen. Real structure ported:
 * hero, "Son adım." headline, plan-recap
 * card (real sector/certificate labels), lock-icon timing reassurance banner, auth button stack,
 * inline error banner, "Zaten hesabım var" pill, OTP digit boxes (the actual invisible-textfield-
 * over-visual-boxes technique iOS uses, not a simplification). Deliberately simplified, documented
 * not silent:
 * - Email/OTP capture is an inline expanding card in the normal scroll flow, not iOS's floating
 *   bottom-sheet overlay with a dimmed backdrop + keyboard-height-tracking padding animation — no
 *   custom keyboard observer built this pass, the system already pans/resizes adequately.
 * - No auto-focus-on-phase-change (iOS's `focusRequest` retry-with-delay dance) — user taps the
 *   field, standard Android behavior.
 * - Google's real 4-color "G" logo (iOS draws it with `Canvas` arc segments) simplified to a
 *   plain "G" letter in Google blue — no custom Canvas drawing, matching this pass's policy.
 * - Legal notice ("Devam ederek...") now uses real per-phrase tappable links (2026-08-09 gap
 *   sweep) into the same [RdLegalDocumentSheet] the Profile screen's "Yasal Bilgilendirme" row
 *   opens — closes the "static informational text only" gap this comment used to describe.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthScreen(
    onAuthenticated: () -> Unit,
    onBack: (() -> Unit)? = null,
    primarySectorLabel: String? = null,
    certificateLabel: String? = null,
    viewModel: AuthViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()

    var emailPhase by remember { mutableStateOf(EmailPhase.Hidden) }
    var email by remember { mutableStateOf("") }
    var otp by remember { mutableStateOf("") }
    var sentTo by remember { mutableStateOf("") }
    var legalDocumentKind by remember { mutableStateOf<String?>(null) }

    val isLoading = state is AuthUiState.Loading
    val normalizedEmail = email.trim().lowercase()
    val canSendCode = normalizedEmail.contains("@") && normalizedEmail.contains(".") && !isLoading
    val canVerifyCode = otp.length == 6 && !isLoading
    val failure = (state as? AuthUiState.Failed)?.error?.message

    LaunchedEffect(state) {
        when (val s = state) {
            is AuthUiState.SignedIn -> onAuthenticated()
            is AuthUiState.OtpSent -> {
                sentTo = normalizedEmail
                otp = ""
                emailPhase = EmailPhase.Otp
            }
            else -> Unit
        }
    }

    // Mirrors iOS's autoVerifiedCode behavior: 6 digits typed -> verify immediately, no extra tap.
    LaunchedEffect(otp) {
        if (emailPhase == EmailPhase.Otp && otp.length == 6 && !isLoading) {
            viewModel.verifyEmailOtp(sentTo, otp)
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        if (onBack != null) {
            IconButton(onClick = onBack, modifier = Modifier.padding(start = 12.dp, top = 8.dp).size(40.dp)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(RdR.string.rd_geri), tint = colors.onyx)
            }
        } else {
            Spacer(Modifier.height(48.dp))
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RdSpacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            RdHeroTile(tint = RdHeroTint.Green) {
                Icon(Icons.Filled.VerifiedUser, contentDescription = null, tint = colors.green, modifier = Modifier.size(28.dp))
            }

            Spacer(Modifier.height(24.dp))
            Text(stringResource(RdR.string.rd_son_adim), style = RdFontStyle.Title1.toTextStyle(), color = colors.onyx, textAlign = TextAlign.Center)

            Spacer(Modifier.height(10.dp))
            Text(
                stringResource(RdR.string.rd_auth_plan_kaydet),
                style = RdFontStyle.Subheadline.toTextStyle(),
                color = colors.slate,
                textAlign = TextAlign.Center,
                modifier = Modifier.widthIn(max = 300.dp),
            )

            Spacer(Modifier.height(24.dp))
            PlanRecapCard(primarySectorLabel = primarySectorLabel, certificateLabel = certificateLabel)

            Spacer(Modifier.height(24.dp))
            HorizontalDivider(color = colors.line)

            Spacer(Modifier.height(16.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(colors.greenSoft.copy(alpha = 0.5f))
                    .border(1.dp, colors.green.copy(alpha = 0.18f), RoundedCornerShape(12.dp))
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Lock, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(8.dp))
                Text(
                    stringResource(RdR.string.rd_auth_on_saniye),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                )
            }

            // Android launch policy: Google and e-mail OTP are the visible sign-in methods.
            // Keep the Apple OAuth implementation below the UI layer for a future, explicitly
            // gated iOS-account recovery path; exposing it here would make an unconfigured
            // staging Apple client secret a release dependency without helping new Android users.
            Spacer(Modifier.height(14.dp))
            OnboardingAuthButton(
                text = stringResource(
                    if (isLoading && emailPhase == EmailPhase.Hidden) RdR.string.rd_google_baglaniyor else RdR.string.rd_google_devam,
                ),
                onClick = { viewModel.signInWithGoogle(context) },
                enabled = !isLoading,
                google = true,
            )

            Spacer(Modifier.height(10.dp))
            if (emailPhase == EmailPhase.Hidden) {
                OnboardingAuthButton(
                    text = stringResource(RdR.string.rd_eposta_devam),
                    onClick = { emailPhase = EmailPhase.Email },
                    enabled = !isLoading,
                    google = false,
                )
            } else {
                EmailAuthPanel(
                    phase = emailPhase,
                    email = email,
                    onEmailChange = { email = it },
                    otp = otp,
                    onOtpChange = { otp = it },
                    sentTo = sentTo,
                    canSendCode = canSendCode,
                    canVerifyCode = canVerifyCode,
                    isLoading = isLoading,
                    error = failure,
                    onSendCode = { viewModel.sendEmailOtp(normalizedEmail, resolveAppLanguage()) },
                    onVerifyCode = { viewModel.verifyEmailOtp(sentTo, otp) },
                    onResend = { viewModel.sendEmailOtp(sentTo, resolveAppLanguage()) },
                    onChangeEmail = { emailPhase = EmailPhase.Email; otp = "" },
                    onClose = { emailPhase = EmailPhase.Hidden },
                )
            }

            if (emailPhase == EmailPhase.Hidden && failure != null) {
                Spacer(Modifier.height(10.dp))
                AuthErrorBanner(failure)
            }

            Spacer(Modifier.height(18.dp))
            Row(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(colors.fog.copy(alpha = 0.6f))
                    .border(1.dp, colors.line, CircleShape)
                    .clickable { emailPhase = EmailPhase.Email }
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(RdR.string.rd_zaten_hesabim_var), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                Spacer(Modifier.width(4.dp))
                Text(stringResource(RdR.string.rd_giris_yap), style = RdFontStyle.Caption.toTextStyle(), color = colors.onyx)
            }

            Spacer(Modifier.height(20.dp))
            LegalAcceptanceNotice(onOpenDocument = { kind -> legalDocumentKind = kind })
            Spacer(Modifier.height(16.dp))
        }
    }

    if (legalDocumentKind != null) {
        var legalDocuments by remember { mutableStateOf<List<RdLegalDocument>>(emptyList()) }
        LaunchedEffect(Unit) {
            legalDocuments = LegalDocumentAssets.load(context)
                .map { RdLegalDocument(kind = it.kind, title = it.title, text = it.text) }
        }
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { legalDocumentKind = null }, sheetState = sheetState) {
            RdLegalDocumentSheet(
                documents = legalDocuments,
                initialKind = legalDocumentKind,
                onClose = { legalDocumentKind = null },
            )
        }
    }
}

@Composable
fun AuthOnboardingPreviewSurface() {
    val colors = RdTheme.colors
    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        IconButton(onClick = {}, modifier = Modifier.padding(start = 12.dp, top = 8.dp).size(40.dp)) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = colors.onyx)
        }
        Column(
            modifier = Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = RdSpacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            RdHeroTile(tint = RdHeroTint.Green) {
                Icon(Icons.Filled.VerifiedUser, contentDescription = null, tint = colors.green, modifier = Modifier.size(28.dp))
            }
            Spacer(Modifier.height(24.dp))
            Text(stringResource(RdR.string.rd_son_adim), style = RdFontStyle.Title1.toTextStyle(), color = colors.onyx)
            Spacer(Modifier.height(10.dp))
            Text(stringResource(RdR.string.rd_auth_plan_kaydet), style = RdFontStyle.Subheadline.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)
            Spacer(Modifier.height(24.dp))
            PlanRecapCard(primarySectorLabel = "İnşaat", certificateLabel = "A Sınıfı")
            Spacer(Modifier.height(24.dp))
            HorizontalDivider(color = colors.line)
            Spacer(Modifier.height(16.dp))
            Row(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(colors.greenSoft.copy(alpha = 0.5f))
                    .border(1.dp, colors.green.copy(alpha = 0.18f), RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Lock, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(8.dp))
                Text(stringResource(RdR.string.rd_auth_on_saniye), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }
            Spacer(Modifier.height(14.dp))
            OnboardingAuthButton(stringResource(RdR.string.rd_google_devam), {}, true, google = true)
            Spacer(Modifier.height(10.dp))
            OnboardingAuthButton(stringResource(RdR.string.rd_eposta_devam), {}, true, google = false)
            Spacer(Modifier.height(18.dp))
            Row(
                modifier = Modifier.clip(CircleShape).background(colors.fog.copy(alpha = 0.6f)).border(1.dp, colors.line, CircleShape)
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(RdR.string.rd_zaten_hesabim_var), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                Spacer(Modifier.width(4.dp))
                Text(stringResource(RdR.string.rd_giris_yap), style = RdFontStyle.Caption.toTextStyle(), color = colors.onyx)
            }
            Spacer(Modifier.height(20.dp))
            LegalAcceptanceNotice(onOpenDocument = {})
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun OnboardingAuthButton(
    text: String,
    onClick: () -> Unit,
    enabled: Boolean,
    google: Boolean,
) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(if (google) colors.white else colors.onyx)
            .border(1.dp, if (google) colors.line else colors.onyx, RoundedCornerShape(16.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.55f)
            .padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (google) {
            Image(
                painter = painterResource(OnboardingR.drawable.google_mark),
                contentDescription = null,
                modifier = Modifier.size(23.dp),
            )
        } else {
            Icon(Icons.Filled.Email, contentDescription = null, tint = colors.white, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.width(12.dp))
        Text(
            text = text,
            style = RdFontStyle.Body.toTextStyle(),
            color = if (google) colors.onyx else colors.white,
            textAlign = TextAlign.Center,
        )
    }
}

/** Real, per-phrase tappable version of the static notice this screen used to show — mirrors
 * `LegalAcceptanceNotice.swift`'s `AttributedString` link-building (`.link` on each phrase span)
 * closely enough to keep the exact same Turkish sentence and phrase boundaries, just built with
 * Compose's `ClickableText`/annotation offsets instead of SwiftUI's `openURL` environment action. */
@Composable
private fun LegalAcceptanceNotice(onOpenDocument: (String) -> Unit) {
    val colors = RdTheme.colors
    val prefix = stringResource(RdR.string.rd_legal_prefix)
    val termsLabel = stringResource(RdR.string.rd_kullanim_kosullari)
    val joiner = stringResource(RdR.string.rd_legal_joiner)
    val privacyLabel = stringResource(RdR.string.rd_gizlilik_politikasi)
    val suffix = stringResource(RdR.string.rd_legal_suffix)

    val annotated = buildAnnotatedString {
        append(prefix.trimEnd())
        append(" ")
        pushStringAnnotation(tag = "legal", annotation = "terms")
        withStyle(SpanStyle(color = colors.onyx, textDecoration = TextDecoration.Underline)) {
            append(termsLabel)
        }
        pop()
        append(" ")
        append(joiner.trim())
        append(" ")
        pushStringAnnotation(tag = "legal", annotation = "privacy")
        withStyle(SpanStyle(color = colors.onyx, textDecoration = TextDecoration.Underline)) {
            append(privacyLabel)
        }
        pop()
        append(suffix.trimStart())
    }

    ClickableText(
        text = annotated,
        style = RdFontStyle.Caption.toTextStyle().copy(
            color = colors.slate.copy(alpha = 0.85f),
            textAlign = TextAlign.Center,
        ),
        modifier = Modifier.fillMaxWidth(),
        onClick = { offset ->
            annotated.getStringAnnotations(tag = "legal", start = offset, end = offset)
                .firstOrNull()
                ?.let { onOpenDocument(it.item) }
        },
    )
}

@Composable
private fun PlanRecapCard(primarySectorLabel: String?, certificateLabel: String?) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(colors.fog)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(14.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(36.dp).clip(RoundedCornerShape(10.dp)).background(colors.green),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = colors.white, modifier = Modifier.size(16.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(colors.greenSoft)
                    .border(1.dp, colors.green.copy(alpha = 0.22f), CircleShape)
                    .padding(horizontal = 7.dp, vertical = 3.dp),
            ) {
                Text(stringResource(RdR.string.rd_sana_ozel), style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 9.sp), color = colors.greenDark)
            }
            Spacer(Modifier.height(4.dp))
            Text(stringResource(RdR.string.rd_planin_hazir_seni_bekliyor), style = RdFontStyle.Footnote.toTextStyle(), color = colors.onyx)
            Text(
                stringResource(
                    RdR.string.rd_auth_plan_recap_format,
                    primarySectorLabel ?: stringResource(RdR.string.rd_genel),
                    certificateLabel ?: stringResource(RdR.string.rd_tire),
                ),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
            )
        }
    }
}

@Composable
private fun AuthErrorBanner(message: String) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(colors.criticalBg.copy(alpha = 0.70f))
            .border(1.dp, colors.critical.copy(alpha = 0.22f), RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        Icon(Icons.Filled.ErrorOutline, contentDescription = null, tint = colors.critical, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(8.dp))
        Text(message, style = RdFontStyle.Caption.toTextStyle(), color = colors.criticalText)
    }
}

@Composable
private fun EmailAuthPanel(
    phase: EmailPhase,
    email: String,
    onEmailChange: (String) -> Unit,
    otp: String,
    onOtpChange: (String) -> Unit,
    sentTo: String,
    canSendCode: Boolean,
    canVerifyCode: Boolean,
    isLoading: Boolean,
    error: String?,
    onSendCode: () -> Unit,
    onVerifyCode: () -> Unit,
    onResend: () -> Unit,
    onChangeEmail: () -> Unit,
    onClose: () -> Unit,
) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(elevation = 12.dp, shape = RoundedCornerShape(24.dp))
            .clip(RoundedCornerShape(24.dp))
            .background(colors.white)
            .border(1.dp, colors.line.copy(alpha = 0.78f), RoundedCornerShape(24.dp))
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(colors.green.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (phase == EmailPhase.Otp) Icons.Filled.Pin else Icons.Filled.Email,
                    contentDescription = null,
                    tint = colors.green,
                    modifier = Modifier.size(17.dp),
                )
            }
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    stringResource(
                        if (phase == EmailPhase.Otp) RdR.string.rd_dogrulama_kodu_baslik else RdR.string.rd_eposta_adresi_giriniz,
                    ),
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.onyx,
                )
                Text(
                    if (phase == EmailPhase.Otp) {
                        stringResource(RdR.string.rd_kod_gonderildi_format, sentTo)
                    } else {
                        stringResource(RdR.string.rd_kod_icin_eposta)
                    },
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    maxLines = 2,
                )
            }
            IconButton(onClick = onClose, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_kapat), tint = colors.slate, modifier = Modifier.size(14.dp))
            }
        }

        Spacer(Modifier.height(13.dp))
        if (phase == EmailPhase.Email) {
            OutlinedTextField(
                value = email,
                onValueChange = onEmailChange,
                placeholder = { Text(stringResource(RdR.string.rd_mailinizi_yaziniz)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(10.dp))
            RdPrimaryButton(
                text = stringResource(if (isLoading) RdR.string.rd_kod_gonderiliyor else RdR.string.rd_kod_gonder),
                onClick = onSendCode,
                enabled = canSendCode,
                modifier = Modifier.height(50.dp),
            )
        } else {
            OtpDigitInput(value = otp, onValueChange = onOtpChange)
            Spacer(Modifier.height(10.dp))
            RdPrimaryButton(
                text = stringResource(if (isLoading) RdR.string.rd_dogrulaniyor else RdR.string.rd_dogrula_devam),
                onClick = onVerifyCode,
                enabled = canVerifyCode,
                style = RdButtonStyle.Green,
                modifier = Modifier.height(50.dp),
            )
            Spacer(Modifier.height(8.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(onClick = onResend, enabled = !isLoading) {
                    Text(stringResource(RdR.string.rd_yeni_kod_gonder), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                }
                TextButton(onClick = onChangeEmail) {
                    Text(stringResource(RdR.string.rd_e_postayi_degistir), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                }
            }
        }

        if (error != null) {
            Spacer(Modifier.height(6.dp))
            Text(error, style = RdFontStyle.Caption.toTextStyle(), color = colors.critical.copy(alpha = 0.88f))
        }
    }
}

/** Mirrors OBAuthView's `otpInputRow`: 6 visual digit boxes driven by a single invisible
 * [BasicTextField] laid on top — the real iOS technique (invisible textfield + visual boxes),
 * not a simplification. No auto-focus-on-appear (see file doc comment) — tap a box to focus. */
@Composable
private fun OtpDigitInput(value: String, onValueChange: (String) -> Unit) {
    val colors = RdTheme.colors
    Box(modifier = Modifier.fillMaxWidth().height(58.dp)) {
        Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            repeat(6) { index ->
                val digit = value.getOrNull(index)?.toString() ?: ""
                val isActive = index == value.length && value.length < 6
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(14.dp))
                        .background(colors.white)
                        .border(
                            width = if (isActive) 2.dp else 1.5.dp,
                            color = if (isActive) colors.green else if (digit.isNotEmpty()) colors.onyx.copy(alpha = 0.72f) else colors.line,
                            shape = RoundedCornerShape(14.dp),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(digit, style = RdFontStyle.Title2.toTextStyle(), color = colors.onyx)
                }
            }
        }
        BasicTextField(
            value = value,
            onValueChange = { onValueChange(it.filter(Char::isDigit).take(6)) },
            singleLine = true,
            textStyle = TextStyle(color = androidx.compose.ui.graphics.Color.Transparent, fontSize = 1.sp),
            cursorBrush = SolidColor(androidx.compose.ui.graphics.Color.Transparent),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            modifier = Modifier.fillMaxSize().alpha(0f),
        )
    }
}

/**
 * TODO(Faz 3 localization): resolve from the real per-app-language setting once Android's
 * localization pipeline exists (master §23.1) — mirrors RDLanguage.current on iOS. Hardcoded
 * to Turkish for now, matching this screen's hardcoded copy strings.
 */
private fun resolveAppLanguage(): RdAppLanguage = RdAppLanguage.Turkish
