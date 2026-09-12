package com.riskdetectedan.core.data.billing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BillingOfferingSelectorTest {
    @Test fun `configured default wins over targeted current`() {
        assertEquals("production", selectBillingOffering("default", "targeted") {
            assertEquals("default", it)
            "production"
        })
    }

    @Test fun `missing configured default cannot fall back to QA current`() {
        assertNull(selectBillingOffering("default", "qa_test_store") { null })
    }

    @Test fun `missing configured QA cannot fall back to production current`() {
        assertNull(selectBillingOffering("qa_storekit", "production") { null })
    }

    @Test fun `empty configuration uses current without looking up an identifier`() {
        assertEquals("current", selectBillingOffering("", "current") {
            error("Lookup must not run for empty configuration")
        })
    }

    @Test fun `whitespace configuration uses current without lookup`() {
        assertEquals("current", selectBillingOffering(" \t\n", "current") {
            error("Lookup must not run for blank configuration")
        })
    }

    @Test fun `surrounding whitespace is trimmed before exact lookup`() {
        assertEquals("production", selectBillingOffering(" \tdefault\n", "other") {
            assertEquals("default", it)
            "production"
        })
    }

    @Test fun `identifier is case sensitive and not rewritten`() {
        assertNull(selectBillingOffering("DEFAULT", "production") {
            assertEquals("DEFAULT", it)
            if (it == "default") "production" else null
        })
    }

    @Test fun `no configured or current offering remains empty`() {
        assertNull(selectBillingOffering<String>("", null) { error("Unexpected lookup") })
    }

    @Test fun `configured offering works without current`() {
        assertEquals("qa", selectBillingOffering("qa_storekit", null) { "qa" })
    }

    @Test fun `missing configured offering and missing current remain empty`() {
        assertNull(selectBillingOffering<String>("default", null) { null })
    }
}
