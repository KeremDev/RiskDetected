package com.riskdetectedan.feature.onboarding.nova

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel

private val backScreens = setOf(NovaOBScreen.Questions, NovaOBScreen.Signup, NovaOBScreen.EmailForm, NovaOBScreen.Otp, NovaOBScreen.TrialHow)

/**
 * The Nova onboarding funnel for the pilot bundles (iOS `NovaOnboardingFlow`), one branch per
 * prototype screen. [onOpenLogin] leaves for the sign-in surface without completing onboarding;
 * [onFinished] runs once the funnel is done and its answers are stored as the pending draft.
 */
@Composable
fun NovaOnboardingFlow(onOpenLogin: () -> Unit, onFinished: () -> Unit, controller: NovaOnboardingController = hiltViewModel()) {
    BackHandler(enabled = controller.screen in backScreens) { controller.back() }
    val finish = {
        controller.saveDraft()
        onFinished()
    }
    AnimatedContent(controller.screen, Modifier.fillMaxSize().background(NovaOB.surface),
        transitionSpec = { fadeIn(tween(280, easing = FastOutSlowInEasing)) togetherWith fadeOut(tween(280, easing = FastOutSlowInEasing)) },
        label = "nova-onboarding") { screen ->
        when (screen) {
            NovaOBScreen.Splash -> NovaOBSplashScreen(controller)
            NovaOBScreen.Reveal -> NovaOBRevealScreen(controller, onOpenLogin)
            NovaOBScreen.Intro1 -> NovaOBIntroScreen(controller, 0, onOpenLogin)
            NovaOBScreen.Intro2 -> NovaOBIntroScreen(controller, 1, onOpenLogin)
            NovaOBScreen.Intro3 -> NovaOBIntroScreen(controller, 2, onOpenLogin)
            NovaOBScreen.Social -> NovaOBSocialProofScreen(controller, onOpenLogin)
            NovaOBScreen.Questions -> NovaOBQuestionScreen(controller)
            NovaOBScreen.Prep -> NovaOBPrepScreen(controller)
            NovaOBScreen.Card -> NovaOBProfileCardScreen(controller)
            NovaOBScreen.Signup -> NovaOBSignupScreen(controller, onOpenLogin)
            NovaOBScreen.EmailForm -> NovaOBEmailFormScreen(controller)
            NovaOBScreen.Otp -> NovaOBOtpScreen(controller)
            NovaOBScreen.Trial -> NovaOBTrialScreen(controller)
            NovaOBScreen.TrialHow -> NovaOBTrialHowScreen(controller)
            NovaOBScreen.Push -> NovaOBPushScreen(controller, finish)
        }
    }
}
