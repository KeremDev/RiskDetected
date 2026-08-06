package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.auth.RdAppLanguage
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * Port of App/Views/Onboarding/V2/Screens/OBAuthView.swift — email OTP + Google Sign-In only
 * for now (Apple Sign-In on Android is GATE-04-conditional per the plan, not a default path;
 * not wired here). Copy strings below are the same Turkish fallback strings iOS uses
 * (RDLocalization fallback values) — hardcoded until the Android localization pipeline exists
 * (same interim state Faz 1's placeholder screens are already in).
 */
@Composable
fun AuthScreen(
    onAuthenticated: () -> Unit,
    viewModel: AuthViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val state by viewModel.state.collectAsState()

    var email by remember { mutableStateOf("") }
    var otp by remember { mutableStateOf("") }
    var otpSentTo by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(state) {
        if (state is AuthUiState.SignedIn) onAuthenticated()
    }

    val isLoading = state is AuthUiState.Loading
    val normalizedEmail = email.trim().lowercase()
    val canSendCode = normalizedEmail.contains("@") && normalizedEmail.contains(".") && !isLoading
    val canVerifyCode = otp.length == 6 && !isLoading

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(RdSpacing.lg),
        verticalArrangement = Arrangement.Center,
    ) {
        Button(
            onClick = { viewModel.signInWithGoogle(context) },
            enabled = !isLoading,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(if (isLoading) "Google ile bağlanıyor..." else "Google ile devam et")
        }

        Spacer(modifier = Modifier.height(RdSpacing.md))

        if (otpSentTo == null) {
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("E-posta adresini gir") },
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    keyboardType = KeyboardType.Email,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(RdSpacing.sm))
            OutlinedButton(
                onClick = {
                    viewModel.sendEmailOtp(normalizedEmail, resolveAppLanguage())
                    otpSentTo = normalizedEmail
                },
                enabled = canSendCode,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (isLoading) "Kod gönderiliyor..." else "Kod gönder")
            }
        } else {
            Text("$otpSentTo adresine gönderildi")
            Spacer(modifier = Modifier.height(RdSpacing.sm))
            OutlinedTextField(
                value = otp,
                onValueChange = { if (it.length <= 6) otp = it },
                label = { Text("Doğrulama kodu") },
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    keyboardType = KeyboardType.NumberPassword,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(RdSpacing.sm))
            Button(
                onClick = { viewModel.verifyEmailOtp(otpSentTo.orEmpty(), otp) },
                enabled = canVerifyCode,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (isLoading) "Doğrulanıyor..." else "Doğrula ve devam et")
            }
            Spacer(modifier = Modifier.height(RdSpacing.xs))
            TextButton(onClick = { otpSentTo = null; otp = "" }) {
                Text("Yeni kod gönder")
            }
        }

        if (isLoading) {
            Spacer(modifier = Modifier.height(RdSpacing.md))
            CircularProgressIndicator()
        }

        val failure = state as? AuthUiState.Failed
        if (failure != null) {
            Spacer(modifier = Modifier.height(RdSpacing.sm))
            Text(failure.message)
        }
    }
}

/**
 * TODO(Faz 3 localization): resolve from the real per-app-language setting once Android's
 * localization pipeline exists (master §23.1) — mirrors RDLanguage.current on iOS. Hardcoded
 * to Turkish for now, matching this screen's hardcoded copy strings.
 */
private fun resolveAppLanguage(): RdAppLanguage = RdAppLanguage.Turkish
