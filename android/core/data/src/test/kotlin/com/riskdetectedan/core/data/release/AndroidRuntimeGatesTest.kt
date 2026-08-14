package com.riskdetectedan.core.data.release

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidRuntimeGatesTest {
    @Test
    fun missingContractKeepsMasterClientGateClosed() {
        val decision = AndroidRuntimeGates.CLOSED.decision(AndroidRuntimeGateName.Client)

        assertFalse(decision.enabled)
    }

    @Test
    fun explicitClientDecisionCanOpenMasterGate() {
        val gates = AndroidRuntimeGates(
            schemaVersion = 1,
            evaluatedVersionCode = 1,
            client = AndroidRuntimeGate(enabled = true, reason = "version_allowlist"),
        )

        assertTrue(gates.decision(AndroidRuntimeGateName.Client).enabled)
    }
}
