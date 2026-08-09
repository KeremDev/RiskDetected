package com.riskdetectedan.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.viewModels
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
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
import com.riskdetectedan.core.data.auth.AuthDeepLinkHandler
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    private val appearanceViewModel: AppearanceViewModel by viewModels()

    @Inject lateinit var authDeepLinkHandler: AuthDeepLinkHandler

    @Inject lateinit var notificationDeepLinkHandler: NotificationDeepLinkHandler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleAuthDeepLink(intent)
        notificationDeepLinkHandler.handle(intent)
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
                ReleaseGate {
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
                    Box(modifier = Modifier.fillMaxSize().safeDrawingPadding()) {
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
                        RdNavHost()
                        NetworkStatusBanner(modifier = Modifier.align(Alignment.TopCenter))
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthDeepLink(intent)
        notificationDeepLinkHandler.handle(intent)
    }

    private fun handleAuthDeepLink(intent: Intent) {
        authDeepLinkHandler.handle(intent)
    }
}
