package com.riskdetectedan.core.data.billing

import org.junit.Assert.*
import org.junit.Test

class BillingLaunchGuardTest {
    @Test fun `only one caller owns checkout until released`() {
        val guard = BillingLaunchGuard()
        assertTrue(guard.acquire())
        assertFalse(guard.acquire())
        guard.release()
        assertTrue(guard.acquire())
    }

    @Test fun `closed or background activity cannot launch payment`() {
        assertTrue(canLaunchBilling(false, false, true))
        assertFalse(canLaunchBilling(true, false, true))
        assertFalse(canLaunchBilling(false, true, true))
        assertFalse(canLaunchBilling(false, false, false))
    }
}
