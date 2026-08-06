package com.riskdetectedan.feature.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * Port of OBNotificationPermissionView.swift. POST_NOTIFICATIONS is Android 13+ only (already
 * declared in the manifest); below that, the request is a no-op and this just continues —
 * mirrors iOS's "no payment/no hard requirement at this step" framing either way.
 */
@Composable
fun OBNotificationPermissionScreen(onContinue: () -> Unit) {
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { _ -> onContinue() }

    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Plan, teklif ve uygulama hatırlatmaları için bildirimleri aç.")
        Text("Bu adımda satın alma yapılmaz")
        Button(
            onClick = {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    onContinue()
                }
            },
        ) { Text("Bildirimleri Aç") }
        TextButton(onClick = onContinue) { Text("Ücretsiz devam et") }
    }
}
