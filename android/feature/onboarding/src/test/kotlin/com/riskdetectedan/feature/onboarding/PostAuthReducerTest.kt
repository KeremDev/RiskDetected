package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.data.profile.SubscriptionTier
import org.junit.Assert.assertEquals
import org.junit.Test

class PostAuthReducerTest {
    @Test fun freeAndUnavailableProfilesContinueToTrialInvite() {
        assertEquals(PostAuthDestination.TrialInvite, PostAuthReducer.destination(null))
        assertEquals(PostAuthDestination.TrialInvite, PostAuthReducer.destination(SubscriptionTier.Free))
    }

    @Test fun existingPlusAndProUsersFinishOnboardingImmediately() {
        assertEquals(PostAuthDestination.Finish, PostAuthReducer.destination(SubscriptionTier.Plus))
        assertEquals(PostAuthDestination.Finish, PostAuthReducer.destination(SubscriptionTier.Pro))
    }
}
