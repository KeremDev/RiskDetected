package com.riskdetectedan.app.bootstrap

import org.junit.Assert.assertEquals
import org.junit.Test

class BootstrapReducerTest {
    @Test fun freshSignedOutInstallStartsOnboarding() {
        assertEquals(BootstrapState.Onboarding, BootstrapReducer.initial(false, false))
    }

    @Test fun completedSignedOutInstallStartsAuth() {
        assertEquals(BootstrapState.Auth, BootstrapReducer.initial(true, false))
    }

    @Test fun authenticatedSessionStartsMain() {
        assertEquals(BootstrapState.Main, BootstrapReducer.initial(false, true))
    }

    @Test fun authSessionTransitionOpensMain() {
        assertEquals(BootstrapState.Main, BootstrapReducer.sessionChanged(BootstrapState.Auth, true))
    }

    @Test fun signOutReturnsMainToAuth() {
        assertEquals(BootstrapState.Auth, BootstrapReducer.sessionChanged(BootstrapState.Main, false))
    }

    @Test fun onboardingDoesNotSkipRemainingStepsWhenAuthCompletes() {
        assertEquals(BootstrapState.Onboarding, BootstrapReducer.sessionChanged(BootstrapState.Onboarding, true))
    }
}
