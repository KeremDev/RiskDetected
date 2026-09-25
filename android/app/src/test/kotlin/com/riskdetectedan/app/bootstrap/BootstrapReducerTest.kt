package com.riskdetectedan.app.bootstrap

import org.junit.Assert.assertEquals
import org.junit.Test

class BootstrapReducerTest {
    @Test fun freshSignedOutInstallStartsOnboarding() {
        assertEquals(BootstrapState.Onboarding, BootstrapReducer.initial(true, false))
    }

    @Test fun completedOrReturningSignedOutInstallStartsAuth() {
        assertEquals(BootstrapState.Auth, BootstrapReducer.initial(false, false))
    }

    @Test fun authenticatedSessionStartsMain() {
        assertEquals(BootstrapState.Main, BootstrapReducer.initial(true, true))
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

    @Test fun heldRouteKeepsAuthUntilReleased() {
        // A reset's recovery session waits on the sign-in surface for the new password.
        assertEquals(BootstrapState.Auth, BootstrapReducer.sessionChanged(BootstrapState.Auth, true, routeHeld = true))
        assertEquals(BootstrapState.Main, BootstrapReducer.sessionChanged(BootstrapState.Auth, true, routeHeld = false))
    }
}
