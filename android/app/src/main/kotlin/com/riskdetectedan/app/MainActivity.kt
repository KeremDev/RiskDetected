package com.riskdetectedan.app

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.riskdetectedan.app.account.WelcomeEmailSender
import com.riskdetectedan.app.legal.LegalAcceptanceRecorder
import com.riskdetectedan.app.navigation.RdNavHost
import com.riskdetectedan.app.network.NetworkStatusBanner
import com.riskdetectedan.app.push.PushTokenRegistrar
import com.riskdetectedan.app.push.NotificationDeepLinkHandler
import com.riskdetectedan.app.release.ReleaseGate
import com.riskdetectedan.app.settings.AppearanceMode
import com.riskdetectedan.app.settings.AppearanceViewModel
import com.riskdetectedan.app.store.PlayUpdateController
import com.riskdetectedan.app.store.StoreReviewCoordinator
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.data.store.ReviewEligibilityRepository
import com.riskdetectedan.core.data.auth.AuthDeepLinkHandler
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.billing.BillingRepository
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import com.riskdetectedan.core.designsystem.RdTheme
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.res.stringResource
import kotlinx.coroutines.launch

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    private val appearanceViewModel: AppearanceViewModel by viewModels()

    @Inject lateinit var authDeepLinkHandler: AuthDeepLinkHandler

    @Inject lateinit var notificationDeepLinkHandler: NotificationDeepLinkHandler
    @Inject lateinit var reviewEligibilityRepository: ReviewEligibilityRepository
    @Inject lateinit var environmentConfig: RdEnvironmentConfig
    @Inject lateinit var authRepository: AuthRepository
    @Inject lateinit var billingRepository: BillingRepository

    private val updateResultLauncher = registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult(),
    ) { }
    private lateinit var playUpdateController: PlayUpdateController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        playUpdateController = PlayUpdateController(this, updateResultLauncher)
        enableEdgeToEdge()
        handleAuthDeepLink(intent)
        handleNotificationDeepLink(intent)
        setContent {
            val appearanceMode by appearanceViewModel.mode.collectAsState()
            val systemDark = isSystemInDarkTheme()
            RiskDetectedTheme(
                darkTheme = when (appearanceMode) {
                    AppearanceMode.System -> systemDark
                    AppearanceMode.Light -> false
                    AppearanceMode.Dark -> true
                },
            ) {
                // Mirrors AppState.swift: the release-policy gate wraps the whole app, checked
                // before anything else renders — a hard-update requirement replaces the nav
                // graph entirely, not just one screen inside it.
                ReleaseGate(onRequestUpdate = playUpdateController::request) {
                    // Box, not a bare sibling stack — NetworkStatusBanner needs BoxScope's
                    // `align` to overlay on top of RdNavHost the way RootView.swift's offline
                    // banner overlays the rest of the app (zIndex above the nav content, not a
                    // layout sibling pushing it down).
                    //
                    // `safeDrawingPadding()`: `enableEdgeToEdge()` above means every screen draws
                    // under the system status/navigation bars unless padded — a real, pre-existing,
                    // app-wide gap (every screenshot taken this whole session shows title text
                    // overlapping the clock/status icons), caught now because the new onboarding
                    // RdTopBar's "01 / 04" step label was rendering unreadably under the status
                    // bar. Fixed centrally here rather than per-screen, since it affects every
                    // screen in the app, not just onboarding.
                    // Background is intentionally applied before inset padding. On API 26 the
                    // transparent status bar otherwise reveals the black decor surface while
                    // light status-bar icons are requested, producing a black strip with no
                    // readable clock. The app surface now paints through the system insets while
                    // interactive content still respects the safe area.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(RdTheme.colors.cloud)
                            .safeDrawingPadding(),
                    ) {
                        // No UI of its own — registers/refreshes the FCM token for an already
                        // signed-in session (see its own doc comment for what onNewToken alone
                        // doesn't cover).
                        PushTokenRegistrar()
                        // No UI — records a background legal-acceptance audit row (consents
                        // table) for the Turkish document set once signed in. Mirrors
                        // AppState.swift's session-sink call to LegalAcceptanceService; there is
                        // no interactive consent screen for Turkish on iOS either (DEC-10
                        // changed the text, not this "continued use" model).
                        LegalAcceptanceRecorder()
                        // No UI — mirrors AppState.swift's sendWelcomeEmailIfPossible(), fires
                        // (server-deduped) on every authenticated session.
                        WelcomeEmailSender()
                        StoreReviewCoordinator(reviewEligibilityRepository, environmentConfig)
                        RdNavHost()
                        NetworkStatusBanner(modifier = Modifier.align(Alignment.TopCenter))
                    }
                }
                val flexibleUpdateReady by playUpdateController.flexibleUpdateReady.collectAsState()
                if (flexibleUpdateReady) {
                    AlertDialog(
                        onDismissRequest = {},
                        title = { Text(stringResource(R.string.update_ready_title)) },
                        text = { Text(stringResource(R.string.update_ready_message)) },
                        confirmButton = {
                            Button(onClick = playUpdateController::completeFlexibleUpdate) {
                                Text(stringResource(R.string.restart_and_update))
                            }
                        },
                        dismissButton = {
                            TextButton(onClick = playUpdateController::postponeFlexibleUpdate) {
                                Text(stringResource(R.string.later))
                            }
                        },
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthDeepLink(intent)
        handleNotificationDeepLink(intent)
    }

    private fun handleAuthDeepLink(intent: Intent) {
        authDeepLinkHandler.handle(intent)
    }

    private fun handleNotificationDeepLink(intent: Intent) {
        val payload = notificationDeepLinkHandler.handle(intent)
        if (BuildConfig.DEBUG) {
            // Typed route only; never log token, IDs, title/body or the raw FCM payload.
            Log.d(
                "RdNotificationRoute",
                "parsed=${payload?.type ?: "none"}:${payload?.target?.name ?: "none"};" +
                    " hasType=${intent.hasExtra("type")}",
            )
        }
    }

    override fun onResume() {
        super.onResume()
        if (::playUpdateController.isInitialized) playUpdateController.resumeInterruptedImmediateUpdate()
        if (authRepository.currentUserId != null) {
            // Detect renewal-intent changes immediately after returning from
            // Google Play subscription management; the backend remains the
            // only authority and this passive call never unlocks paid access.
            lifecycleScope.launch { billingRepository.reconcileBackendSubscription() }
        }
    }

    override fun onDestroy() {
        if (::playUpdateController.isInitialized) playUpdateController.close()
        super.onDestroy()
    }
}
